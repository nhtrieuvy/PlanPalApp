import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import './apis.dart';
import '../../firebase_options.dart';

/// Firebase Push Notification Service
/// This class handles Firebase initialization, token management,
/// and backend synchronization. All debug logging has been removed
/// for production readiness.
class FirebaseService {
  static FirebaseService? _instance;
  static FirebaseService get instance => _instance ??= FirebaseService._();

  FirebaseService._();

  FirebaseMessaging? _messaging;
  String? _currentToken;
  bool _initialized = false;
  FlutterLocalNotificationsPlugin? _localNotifications;
  // Message stream subscriptions (stored so we can cancel on reset)
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onMessageOpenedAppSub;

  /// Initialize Firebase Core and Messaging
  /// Returns true if successful, false otherwise
  Future<bool> initialize() async {
    if (_initialized) {
      return true;
    }

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      _messaging = FirebaseMessaging.instance;

      await _initializeLocalNotifications();

      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          final permissionStatus = await Permission.notification.status;

          if (permissionStatus.isDenied ||
              permissionStatus.isPermanentlyDenied) {
            final status = await Permission.notification.request();
            if (status.isPermanentlyDenied) {
              // Permission permanently denied; notifications may not work.
            }
          }
        } catch (e) {
          // Ignore permission request errors in production flow
        }
      }

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _messaging!.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      await _getFCMTokenWithRetry();

      _setupMessageHandlers();

      _initialized = true;
      return true;
    } catch (e) {
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
        await Future.delayed(Duration(milliseconds: 500 + (attempt * 500)));

        _currentToken = await _messaging!.getToken();

        if (_currentToken != null) {
          _messaging!.onTokenRefresh.listen((newToken) {
            _currentToken = newToken;
          });
          return _currentToken;
        }
      } catch (e) {
        if (e.toString().contains('FIS_AUTH_ERROR')) {
          if (attempt == 1) {
            // Authentication with Firebase Installations failed.
            // Common causes include incorrect project configuration,
            // mismatched google-services.json, disabled Installations API,
            // network issues, or API key restrictions.
          }
        }

        if (attempt == maxRetries) {
          return null;
        }

        await Future.delayed(retryDelay);
      }
    }

    return null;
  }

  /// Initialize local notifications for foreground display
  Future<void> _initializeLocalNotifications() async {
    try {
      _localNotifications = FlutterLocalNotificationsPlugin();

      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

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

      if (defaultTargetPlatform == TargetPlatform.android) {
        await _createNotificationChannel();
      }
    } catch (e) {
      // Initialization errors are intentionally ignored here; callers can
      // still use the messaging features even if local notifications fail.
    }
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
    if (details.payload != null) {
      try {
        // Parse payload and handle navigation as needed.
      } catch (e) {
        // Ignore payload parsing errors
      }
    }
  }

  /// Register FCM token with backend
  /// Requires auth token for API authentication
  Future<bool> registerToken(String authToken) async {
    if (_currentToken == null) {
      return false;
    }

    try {
      final api = ApiClient(token: authToken);
      final response = await api.dio.post(
        Endpoints.registerDeviceToken,
        data: {
          'fcm_token': _currentToken,
          'platform': defaultTargetPlatform == TargetPlatform.iOS
              ? 'ios'
              : 'android',
        },
      );

      if (response.statusCode == 200) {
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  void _setupMessageHandlers() {
    if (_messaging == null) return;

    // If subscriptions already exist, don't register again
    if (_onMessageSub != null || _onMessageOpenedAppSub != null) return;

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    _onMessageSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      try {
        _showInAppNotification(message);
      } catch (_) {}
    });

    _onMessageOpenedAppSub = FirebaseMessaging.onMessageOpenedApp.listen((
      RemoteMessage message,
    ) {
      try {
        _handleNotificationTap(message);
      } catch (_) {
        // ignore
      }
    });

    // Handle initial message if app was opened from terminated state
    _messaging!.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        try {
          _handleNotificationTap(message);
        } catch (_) {
          // ignore
        }
      }
    });
  }

  void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;

    final _ = data.keys;
  }

  /// Show in-app notification for foreground messages
  Future<void> _showInAppNotification(RemoteMessage message) async {
    final notification = message.notification;
    final data = message.data;
    final extracted = _extractTitleAndBody(notification, data);
    final title = extracted['title'];
    final body = extracted['body'];

    if ((title != null || body != null) && _localNotifications != null) {
      String payload = '';
      if (data.containsKey('conversation_id')) {
        payload = 'conversation_id:${data['conversation_id']}';
        if (data.containsKey('message_id')) {
          payload += ',message_id:${data['message_id']}';
        }
      } else if (data.containsKey('from_user_id')) {
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
      } catch (e) {
        // Ignore local notification errors in production flow
      }
    }

    if (onNotificationReceived != null) {
      onNotificationReceived!(message);
    }
  }

  static Function(RemoteMessage)? onNotificationReceived;

  Map<String?, String?> _extractTitleAndBody(
    RemoteNotification? notification,
    Map<String, dynamic> data,
  ) {
    String? title = notification?.title;
    String? body = notification?.body;

    if ((title == null || title.isEmpty) && data.containsKey('title')) {
      title = data['title']?.toString();
    }
    if ((body == null || body.isEmpty) && data.containsKey('body')) {
      body = data['body']?.toString();
    }

    if ((title == null || title.isEmpty) || (body == null || body.isEmpty)) {
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
      case 'user.friend_request':
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
    // Cancel subscriptions to avoid leaks and allow re-registration
    _onMessageSub?.cancel();
    _onMessageOpenedAppSub?.cancel();
    _onMessageSub = null;
    _onMessageOpenedAppSub = null;
  }
}

/// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Background message received handler
}
