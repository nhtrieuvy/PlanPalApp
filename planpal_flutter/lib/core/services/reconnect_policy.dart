import 'dart:math' as math;

/// Shared bounded exponential-backoff policy for every realtime client.
class ReconnectPolicy {
  const ReconnectPolicy({
    this.maxAttempts = 5,
    this.baseDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(seconds: 30),
    this.maxJitter = const Duration(milliseconds: 500),
  });

  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;
  final Duration maxJitter;

  bool canRetry(int completedAttempts) => completedAttempts < maxAttempts;

  Duration delayForAttempt(int attempt, {int jitterMilliseconds = 0}) {
    final normalizedAttempt = math.max(attempt, 1);
    final exponent = math.min(normalizedAttempt - 1, 30);
    final exponentialMs = baseDelay.inMilliseconds * (1 << exponent);
    final cappedMs = math.min(exponentialMs, maxDelay.inMilliseconds);
    final safeJitter = jitterMilliseconds
        .clamp(0, math.max(maxJitter.inMilliseconds - 1, 0))
        .toInt();
    return Duration(milliseconds: cappedMs + safeJitter);
  }
}

const defaultReconnectPolicy = ReconnectPolicy();
