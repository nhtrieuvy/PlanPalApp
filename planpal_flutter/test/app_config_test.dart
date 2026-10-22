import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planpal_flutter/config/app_config.dart';

void main() {
  test('debug test builds default to the local environment', () {
    expect(AppConfig.environment, 'local');
    final localHost = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : '127.0.0.1';
    expect(AppConfig.getBaseUrl(), 'http://$localHost:8000');
    expect(AppConfig.getWebSocketUrl(), 'ws://$localHost:8000');
    expect(AppConfig.getClientId(), isNotEmpty);
  });
}
