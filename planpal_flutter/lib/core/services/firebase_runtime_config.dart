import 'package:flutter/foundation.dart';
import 'package:planpal_flutter/core/platform/platform_capabilities.dart';

class FirebaseRuntimeConfig {
  const FirebaseRuntimeConfig._();

  static const String _pushFlag = String.fromEnvironment(
    'PLANPAL_ENABLE_PUSH',
    defaultValue: 'true',
  );

  static bool get pushEnabled => _pushFlag.toLowerCase() != 'false';

  static const String webVapidKey = String.fromEnvironment(
    'FIREBASE_WEB_VAPID_KEY',
  );

  static bool get webPushConfigured => !kIsWeb || webVapidKey.isNotEmpty;

  static bool get isSupportedPlatform =>
      kIsWeb || PlatformCapabilities.supportsLocalPushNotifications;
}
