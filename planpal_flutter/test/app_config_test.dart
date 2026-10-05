import 'package:flutter_test/flutter_test.dart';
import 'package:planpal_flutter/config/app_config.dart';

void main() {
  test('debug test builds default to the local environment', () {
    expect(AppConfig.environment, 'local');
    expect(AppConfig.getBaseUrl(), 'http://10.0.2.2:8000');
    expect(AppConfig.getWebSocketUrl(), 'ws://10.0.2.2:8000');
    expect(AppConfig.getClientId(), isNotEmpty);
  });
}
