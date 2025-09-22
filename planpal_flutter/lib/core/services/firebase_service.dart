import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dio/dio.dart';
import './apis.dart';
import '../../firebase_options.dart';

/// Simple and reliable Firebase Push Notification Service
/// Handles Firebase initialization, token management, and backend synchronization
class FirebaseService {
  static FirebaseService? _instance;
  static FirebaseService get instance => _instance ??= FirebaseService._();

  FirebaseService._();

  FirebaseMessaging? _messaging;
  String? _currentToken;
  bool _initialized = false;
  FlutterLocalNotificationsPlugin? _localNotifications;

  /// Initialize Firebase Core and Messaging
  /// Returns true if successful, false otherwise
  Future<bool> initialize() async {
    if (_initialized) {
      debugPrint('FirebaseService: Already initialized');
      return true;
    }

    try {
      // Initialize Firebase Core if not already done
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        debugPrint('FirebaseService: Firebase Core initialized');
      }

      // Debug Firebase app configuration
      _debugFirebaseConfig();

      // Initialize Firebase Messaging
      _messaging = FirebaseMessaging.instance;

      // Initialize local notifications
      await _initializeLocalNotifications();

      // Request notification permission on Android 13+ at runtime
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          final sdkInt =
              (await _localNotifications
                      ?.resolvePlatformSpecificImplementation<
                        AndroidFlutterLocalNotificationsPlugin
                      >()
                      ?.getActiveNotifications())
                  ?.length; // quick probe (not reliable for SDK)
          // Instead of relying on sdkInt probe, use permission_handler to request
          if (await Permission.notification.isDenied ||
              await Permission.notification.isPermanentlyDenied) {
            final status = await Permission.notification.request();
            debugPrint(
              'FirebaseService: Android notification permission: $status',
            );
          }
        } catch (e) {
          // Fall back to direct permission request
          final status = await Permission.notification.request();
          debugPrint(
            'FirebaseService: Android notification permission (fallback): $status',
          );
        }
      }
      // Request permission on iOS
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final settings = await _messaging!.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        debugPrint(
          'FirebaseService: iOS permission status: ${settings.authorizationStatus}',
        );
      }

      // Get FCM token with retry
      await _getFCMTokenWithRetry();

      // Setup message handlers
      _setupMessageHandlers();

      _initialized = true;
      debugPrint('FirebaseService: Initialization completed successfully');
      return true;
    } catch (e) {
      debugPrint('FirebaseService: Initialization failed: $e');
      return false;
    }
  }

  /// Get FCM token with retry logic
  Future<String?> _getFCMTokenWithRetry() async {
    if (_messaging == null) return null;

    const maxRetries = 3;
    const retryDelay = Duration(seconds: 2);

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        debugPrint('FirebaseService: FCM token attempt $attempt/$maxRetries');

        // Add delay to ensure Firebase services are fully ready
        await Future.delayed(Duration(milliseconds: 500 + (attempt * 500)));

        _currentToken = await _messaging!.getToken();

        if (_currentToken != null) {
          debugPrint(
            'FirebaseService: ✅ FCM token obtained on attempt $attempt',
          );
          debugPrint('FirebaseService: Token length: ${_currentToken!.length}');

          // Setup token refresh listener
          _messaging!.onTokenRefresh.listen((newToken) {
            _currentToken = newToken;
            debugPrint('FirebaseService: Token refreshed');
          });
          return _currentToken;
        } else {
          debugPrint(
            'FirebaseService: ⚠️ No FCM token received on attempt $attempt',
          );
        }
      } catch (e) {
        debugPrint('FirebaseService: ❌ Token attempt $attempt failed: $e');

        // Check for specific FIS_AUTH_ERROR
        if (e.toString().contains('FIS_AUTH_ERROR')) {
          debugPrint(
            'FirebaseService: 🔍 FIS_AUTH_ERROR detected on attempt $attempt',
          );
          if (attempt == 1) {
            debugPrint(
              '  - Firebase Installations Service authentication failed',
            );
            debugPrint('  - Common causes:');
            debugPrint('    1. Incorrect Firebase project configuration');
            debugPrint(
              '    2. google-services.json doesn\'t match Firebase project',
            );
            debugPrint('    3. Firebase Installations API not enabled');
            debugPrint('    4. Network connectivity issues');
            debugPrint('    5. API key restrictions in Firebase Console');
          }
        }

        // If this is the last attempt, don't retry
        if (attempt == maxRetries) {
          debugPrint('FirebaseService: ❌ All FCM token attempts failed');
          return null;
        }

        // Wait before retry
        debugPrint(
          'FirebaseService: ⏳ Retrying in ${retryDelay.inSeconds}s...',
        );
        await Future.delayed(retryDelay);
      }
    }

    return null;
  }

  /// Debug Firebase configuration
  void _debugFirebaseConfig() {
    try {
      final app = Firebase.app();
      final options = app.options;

      debugPrint('FirebaseService: 🔧 Configuration Debug:');
      debugPrint('  Project ID: ${options.projectId}');
      debugPrint('  App ID: ${options.appId}');
      debugPrint('  API Key: ${options.apiKey.substring(0, 10)}***');
      debugPrint('  Messaging Sender ID: ${options.messagingSenderId}');
      debugPrint('  Storage Bucket: ${options.storageBucket}');

      if (defaultTargetPlatform == TargetPlatform.android) {
        debugPrint('  Platform: Android');
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        debugPrint('  Platform: iOS');
      }
    } catch (e) {
      debugPrint('FirebaseService: ❌ Error reading Firebase config: $e');
    }
  }

  /// Initialize local notifications for foreground display
  Future<void> _initializeLocalNotifications() async {
    _localNotifications = FlutterLocalNotificationsPlugin();

    // Android initialization
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );

    await _localNotifications!.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create notification channel for Android
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _createNotificationChannel();
    }

    debugPrint('FirebaseService: Local notifications initialized');
  }

  /// Create notification channel for Android
  Future<void> _createNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'planpal_chat_channel',
      'Chat Messages',
      description: 'Notifications for chat messages',
      importance: Importance.high,
    );

    await _localNotifications!
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse details) {
    debugPrint('FirebaseService: Notification tapped: ${details.payload}');

    if (details.payload != null) {
      // Parse payload and handle navigation
      try {
        // Payload should contain conversation_id, message_id, etc.
        debugPrint('Navigating based on payload: ${details.payload}');
        // Add navigation logic here
      } catch (e) {
        debugPrint('Error parsing notification payload: $e');
      }
    }
  }

  /// Register FCM token with backend
  /// Requires auth token for API authentication
  Future<bool> registerToken(String authToken) async {
    if (_currentToken == null) {
      debugPrint('FirebaseService: No FCM token to register');
      return false;
    }

    try {
      final dio = Dio();
      dio.options.baseUrl = baseUrl;
      dio.options.headers['Authorization'] = 'Bearer $authToken';
      dio.options.headers['Content-Type'] = 'application/json';

      final response = await dio.post(
        Endpoints.registerDeviceToken,
        data: {
          'fcm_token': _currentToken,
          'platform': defaultTargetPlatform == TargetPlatform.iOS
              ? 'ios'
              : 'android',
        },
      );

      if (response.statusCode == 200) {
        debugPrint(
          'FirebaseService: Token registered successfully with backend',
        );
        return true;
      } else {
        debugPrint(
          'FirebaseService: Backend registration failed: ${response.statusCode}',
        );
        return false;
      }
    } catch (e) {
      debugPrint('FirebaseService: Failed to register token with backend: $e');
      return false;
    }
  }

  /// Setup message handlers for push notifications
  void _setupMessageHandlers() {
    if (_messaging == null) return;

    // Handle background messages
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('FirebaseService: 📱 Foreground message received');
      debugPrint('Title: ${message.notification?.title}');
      debugPrint('Body: ${message.notification?.body}');
      debugPrint('Data: ${message.data}');

      // Show in-app notification for foreground messages
      _showInAppNotification(message);
    });

    // Handle notification taps when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('FirebaseService: App opened from notification');
      _handleNotificationTap(message);
    });

    // Handle initial message if app was opened from terminated state
    _messaging!.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        debugPrint(
          'FirebaseService: App opened from terminated state via notification',
        );
        _handleNotificationTap(message);
      }
    });
  }

  /// Handle notification tap navigation
  void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    debugPrint('FirebaseService: Handling notification tap with data: $data');

    // Add navigation logic based on notification data
    // Example:
    // if (data.containsKey('type')) {
    //   switch (data['type']) {
    //     case 'plan_update':
    //       // Navigate to plan details
    //       break;
    //     case 'group_message':
    //       // Navigate to group chat
    //       break;
    //   }
    // }
  }

  /// Show in-app notification for foreground messages
  Future<void> _showInAppNotification(RemoteMessage message) async {
    debugPrint('FirebaseService: 🔔 Showing in-app notification');

    final notification = message.notification;
    final data = message.data;
    // Determine title/body: prefer notification payload, fall back to data fields
    final extracted = _extractTitleAndBody(notification, data);
    final title = extracted['title'];
    final body = extracted['body'];

    debugPrint('FirebaseService: Raw FCM data fields: ${data.keys.toList()}');
    debugPrint(
      'FirebaseService: event_type=${data['event_type']}, action=${data['action']}',
    );
    debugPrint('FirebaseService: extracted title="$title" body="$body"');

    if ((title != null || body != null) && _localNotifications != null) {
      debugPrint('📢 NOTIFICATION: $title');
      debugPrint('📝 MESSAGE: $body');
      debugPrint('📊 DATA: $data');

      // Create notification payload for tap handling
      String payload = '';
      if (data.containsKey('conversation_id')) {
        payload = 'conversation_id:${data['conversation_id']}';
        if (data.containsKey('message_id')) {
          payload += ',message_id:${data['message_id']}';
        }
      } else if (data.containsKey('from_user_id')) {
        // Friend request payload
        payload = 'from_user_id:${data['from_user_id']}';
        if (data.containsKey('event_type')) {
          payload += ',event_type:${data['event_type']}';
        }
      } else if (data.containsKey('user_id')) {
        payload = 'user_id:${data['user_id']}';
      } else if (data.containsKey('plan_id')) {
        payload = 'plan_id:${data['plan_id']}';
        if (data.containsKey('event_type')) {
          payload += ',event_type:${data['event_type']}';
        }
      }

      try {
        // Show local notification
        await _localNotifications!.show(
          DateTime.now().millisecondsSinceEpoch.remainder(100000),
          title,
          body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              'planpal_chat_channel',
              'Chat Messages',
              channelDescription: 'Notifications for chat messages',
              importance: Importance.high,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              icon: '@mipmap/ic_launcher',
            ),
            iOS: DarwinNotificationDetails(
              sound: 'default',
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
          payload: payload,
        );

        debugPrint('FirebaseService: ✅ Local notification displayed');
      } catch (e) {
        debugPrint('FirebaseService: ❌ Error showing local notification: $e');
      }
    } else {
      debugPrint(
        'FirebaseService: ⚠️ No title/body available to display or local notifications not initialized',
      );
    }

    // Call external callback if set
    if (onNotificationReceived != null) {
      onNotificationReceived!(message);
    }
  }

  /// Callback for when notification is received in foreground
  static Function(RemoteMessage)? onNotificationReceived;

  /// Helper: extract title and body from RemoteMessage.notification or data payload
  Map<String?, String?> _extractTitleAndBody(
    RemoteNotification? notification,
    Map<String, dynamic> data,
  ) {
    String? title = notification?.title;
    String? body = notification?.body;

    // Prefer explicit data fields if provided
    if ((title == null || title.isEmpty) && data.containsKey('title')) {
      title = data['title']?.toString();
    }
    if ((body == null || body.isEmpty) && data.containsKey('body')) {
      body = data['body']?.toString();
    }

    // If still missing, derive from action or event_type
    if ((title == null || title.isEmpty) || (body == null || body.isEmpty)) {
      // Backend sends 'event_type' field (e.g., 'user.friend_request')
      final action =
          data['action']?.toString() ?? data['event_type']?.toString();
      final derived = _deriveMessageFromAction(action, data);
      title ??= derived['title'];
      body ??= derived['body'];
    }

    return {'title': title, 'body': body};
  }

  /// Map common action keys to human-friendly titles and messages
  Map<String?, String?> _deriveMessageFromAction(
    String? action,
    Map<String, dynamic> data,
  ) {
    switch (action) {
      case 'new_message':
        final sender = data['sender_name'] ?? 'Someone';
        return {
          'title': 'Tin nhắn từ $sender',
          'body':
              data['preview']?.toString() ??
              data['body']?.toString() ??
              'Bạn có tin nhắn mới',
        };
      case 'friend_request':
      case 'user.friend_request': // Backend uses EventType.FRIEND_REQUEST = 'user.friend_request'
        final user = data['from_name'] ?? data['user_name'] ?? 'Ai đó';
        return {
          'title': 'Lời mời kết bạn',
          'body': '$user đã gửi lời mời kết bạn',
        };
      case 'friend_accepted':
      case 'user.friend_accepted':
        final user = data['from_name'] ?? data['user_name'] ?? 'Ai đó';
        return {
          'title': 'Đã chấp nhận',
          'body': '$user đã chấp nhận lời mời của bạn',
        };
      case 'plan_update':
      case 'plan.status_changed':
      case 'plan.activity_created':
      case 'plan.activity_updated':
        final title = data['title'] ?? 'Cập nhật kế hoạch';
        return {
          'title': title,
          'body':
              data['summary']?.toString() ??
              data['body']?.toString() ??
              'Kế hoạch có thay đổi',
        };
      default:
        return {
          'title': data['title']?.toString() ?? 'PlanPal',
          'body': data['body']?.toString() ?? '',
        };
    }
  }

  /// Get current FCM token
  String? get currentToken => _currentToken;

  /// Check if service is initialized
  bool get isInitialized => _initialized;

  /// Reset service (call on logout)
  void reset() {
    _currentToken = null;
    _initialized = false;
    _messaging = null;
    debugPrint('FirebaseService: Service reset');
  }
}

/// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('FirebaseService: Background message received');
  debugPrint('Title: ${message.notification?.title}');
  debugPrint('Body: ${message.notification?.body}');
}
