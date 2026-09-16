import 'package:flutter_test/flutter_test.dart';
import 'package:planpal_flutter/core/services/reconnect_policy.dart';

void main() {
  group('ReconnectPolicy', () {
    test('uses bounded exponential backoff', () {
      const policy = ReconnectPolicy(maxJitter: Duration.zero);

      expect(policy.delayForAttempt(1), const Duration(seconds: 2));
      expect(policy.delayForAttempt(2), const Duration(seconds: 4));
      expect(policy.delayForAttempt(3), const Duration(seconds: 8));
      expect(policy.delayForAttempt(4), const Duration(seconds: 16));
      expect(policy.delayForAttempt(5), const Duration(seconds: 30));
      expect(policy.delayForAttempt(8), const Duration(seconds: 30));
    });

    test('adds only bounded non-negative jitter', () {
      const policy = ReconnectPolicy();

      expect(
        policy.delayForAttempt(1, jitterMilliseconds: 499),
        const Duration(milliseconds: 2499),
      );
      expect(
        policy.delayForAttempt(1, jitterMilliseconds: 900),
        const Duration(milliseconds: 2499),
      );
      expect(
        policy.delayForAttempt(1, jitterMilliseconds: -20),
        const Duration(seconds: 2),
      );
    });

    test('stops after the configured retry budget', () {
      const policy = ReconnectPolicy(maxAttempts: 5);

      expect(policy.canRetry(0), isTrue);
      expect(policy.canRetry(4), isTrue);
      expect(policy.canRetry(5), isFalse);
    });
  });
}
