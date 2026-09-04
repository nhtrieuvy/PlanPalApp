import 'package:flutter/foundation.dart';

/// Production & Development Configuration
class AppConfig {
  // ============= PRODUCTION (Release APK) =============
  // LUÔN sử dụng production URL và CLIENT_ID khi build APK release
  static const String BASE_URL = 'https://planpal-backend.fly.dev';
  static const String CLIENT_ID = 'UhBBWfbCi72eNYMTTn3XqUBR5wGdCcO7TCWmMA7L';

  // ============= DEVELOPMENT (Debug/Local) =============
  // Chỉ dùng khi chạy `flutter run` ở development
  static const String DEV_BASE_URL = 'http://10.0.2.2:8000';
  static const String DEV_CLIENT_ID =
      'UmrrG84UV5li86D7F5e9TDAOugedMLnrErUS1Cvj';

  /// Lấy Base URL
  /// - APK release: https://planpal-backend.fly.dev
  /// - flutter run (debug): http://10.0.2.2:8000
  static String getBaseUrl() {
    // kDebugMode = true CHỈ khi flutter run
    // kDebugMode = false khi APK release
    if (kDebugMode) {
      return DEV_BASE_URL; // Development
    }
    return BASE_URL; // Production (APK release)
  }

  /// Lấy CLIENT_ID tương ứng với môi trường đang chạy
  static String getClientId() {
    if (kDebugMode) {
      return DEV_CLIENT_ID;
    }
    return CLIENT_ID;
  }

  /// Lấy WebSocket URL
  static String getWebSocketUrl() {
    final baseUrl = getBaseUrl();
    final uri = Uri.parse(baseUrl);
    final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return '$wsScheme://${uri.authority}';
  }
}
