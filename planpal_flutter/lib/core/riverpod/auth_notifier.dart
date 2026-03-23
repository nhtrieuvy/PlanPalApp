import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_session.dart';

/// Exposes the existing [AuthProvider] instance through Riverpod.
///
/// The [AuthProvider] session service is initialized before runApp and
/// passed as an override in [ProviderScope].  This provider simply holds
/// that reference so other Riverpod providers (repositories, notifiers)
/// can depend on it without going through any widget-tree provider package.
///
/// Override in main.dart:
/// ```dart
/// ProviderScope(
///   overrides: [
///     authNotifierProvider.overrideWithValue(authProvider),
///   ],
///   child: ...
/// )
/// ```
final authNotifierProvider = Provider<AuthProvider>((ref) {
  throw UnimplementedError(
    'authNotifierProvider must be overridden with the pre-initialized AuthProvider',
  );
});
