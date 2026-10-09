import 'package:flutter/foundation.dart';

/// Centralizes platform differences so presentation code does not scatter
/// browser checks across feature implementations.
abstract final class PlatformCapabilities {
  static bool get isWeb => kIsWeb;

  /// Browser camera capture support varies by browser and permission policy.
  /// A file picker is the reliable web fallback and still supports photos
  /// captured by the operating system where the browser exposes that option.
  static bool get useFilePickerForCamera => kIsWeb;

  static bool get locationRequiresSecureContext => kIsWeb;

  static bool get supportsLocalPushNotifications =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
}
