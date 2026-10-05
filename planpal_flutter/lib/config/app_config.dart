import 'package:flutter/foundation.dart';

/// Build-time environment configuration.
///
/// Switch environments with `--dart-define=APP_ENV=local|production`.
/// `API_BASE_URL` and `OAUTH_CLIENT_ID` are optional overrides for physical
/// devices, staging servers, or a rotated OAuth public client ID.
class AppConfig {
  const AppConfig._();

  static const String _requestedEnvironment = String.fromEnvironment('APP_ENV');
  static const String _baseUrlOverride = String.fromEnvironment('API_BASE_URL');
  static const String _clientIdOverride = String.fromEnvironment(
    'OAUTH_CLIENT_ID',
  );

  static const String _productionBaseUrl = 'https://planpal-backend.fly.dev';
  static const String _productionClientId =
      'UhBBWfbCi72eNYMTTn3XqUBR5wGdCcO7TCWmMA7L';
  static const String _localBaseUrl = 'http://10.0.2.2:8000';
  static const String _localClientId =
      'UmrrG84UV5li86D7F5e9TDAOugedMLnrErUS1Cvj';

  static String get environment {
    final requested = _requestedEnvironment.trim().toLowerCase();
    if (requested.isEmpty) {
      return kReleaseMode ? 'production' : 'local';
    }
    if (requested != 'local' && requested != 'production') {
      throw StateError('APP_ENV must be either local or production.');
    }
    return requested;
  }

  static bool get isProduction => environment == 'production';

  static String getBaseUrl() {
    final override = _baseUrlOverride.trim();
    final value = override.isNotEmpty
        ? override
        : (isProduction ? _productionBaseUrl : _localBaseUrl);
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  static String getClientId() {
    final override = _clientIdOverride.trim();
    if (override.isNotEmpty) return override;
    return isProduction ? _productionClientId : _localClientId;
  }

  static String getWebSocketUrl() {
    final uri = Uri.parse(getBaseUrl());
    final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return '$wsScheme://${uri.authority}';
  }
}
