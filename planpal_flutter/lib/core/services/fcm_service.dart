import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:planpal_flutter/core/services/apis.dart';

// FCM helper: initialize Firebase Messaging, get token, and register it with backend.

class FcmService {
  // Initialize and request permission on iOS
  // onToken: callback invoked when a token is available or refreshed. If provided,
  // we will call it instead of performing the built-in backend registration.
  static Future<void> initAndRegister({
    String? token,
    String? authToken,
    Function(String token)? onToken,
  }) async {
    try {
      // Ensure Firebase app is initialized. If not, try initializing here.
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp();
          debugPrint('FcmService: Firebase.initializeApp() completed');
        }
      } catch (e) {
        debugPrint('FcmService: Firebase.initializeApp failed: $e');
        debugPrint(
          'FcmService: Skipping FCM registration - add google-services.json / GoogleService-Info.plist for platform or initialize Firebase in main.',
        );
        return;
      }

      final messaging = FirebaseMessaging.instance;

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      final fcmToken = token ?? await messaging.getToken();
      debugPrint(
        'FcmService: got token: ${fcmToken?.substring(0, fcmToken.length > 8 ? 8 : fcmToken.length)}...',
      );
      if (fcmToken != null && fcmToken.isNotEmpty) {
        if (onToken != null) {
          try {
            onToken(fcmToken);
          } catch (e) {
            debugPrint('FcmService: onToken callback error: $e');
          }
        } else {
          await registerTokenWithBackend(fcmToken, authToken: authToken);
        }
      } else {
        debugPrint('FcmService: token is null or empty');
      }

      // Listen for token refresh and re-register
      messaging.onTokenRefresh.listen((newToken) async {
        debugPrint('FcmService: token refreshed');
        if (newToken.isNotEmpty) {
          if (onToken != null) {
            try {
              onToken(newToken);
            } catch (e) {
              debugPrint('FcmService: onToken callback error (refresh): $e');
            }
          } else {
            await registerTokenWithBackend(newToken, authToken: authToken);
          }
        }
      });
    } catch (e) {
      debugPrint('FCM init error: $e');
    }
  }

  static Future<void> registerTokenWithBackend(
    String token, {
    String? authToken,
  }) async {
    try {
      debugPrint(
        'FcmService: registering token with backend (auth=${authToken != null})',
      );
      final api = ApiClient(token: authToken);
      final response = await api.dio.post(
        Endpoints.registerDeviceToken,
        data: {'fcm_token': token},
      );
      debugPrint('FcmService: register response status=${response.statusCode}');
    } on DioException catch (e) {
      final res = e.response;
      if (res != null) {
        debugPrint(
          'FcmService: register failed status=${res.statusCode} data=${res.data}',
        );
      } else {
        debugPrint('FcmService: register network error: $e');
      }
    } catch (e) {
      debugPrint('FcmService: unexpected error while registering token: $e');
    }
  }
}
