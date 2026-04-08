import 'package:flutter/foundation.dart';

class FirebaseRuntimeConfig {
  const FirebaseRuntimeConfig._();

  static const String _pushFlag = String.fromEnvironment(
    'PLANPAL_ENABLE_PUSH',
    defaultValue: 'true',
  );

  static bool get pushEnabled => _pushFlag.toLowerCase() != 'false';

  static bool get isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
}
