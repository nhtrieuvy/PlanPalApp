import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:planpal_flutter/core/riverpod/auth_notifier.dart';
import 'package:planpal_flutter/core/services/offline_sync_service.dart';
import 'package:planpal_flutter/core/storage/offline_storage.dart';

/// Secure storage for tokens
final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

/// SharedPreferences — must be overridden in ProviderScope with the
/// pre-initialized instance obtained before runApp.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden with a pre-initialized instance',
  );
});

final offlineStorageProvider = Provider<OfflineStorage>((ref) {
  throw UnimplementedError(
    'offlineStorageProvider must be overridden with an initialized instance',
  );
});

final offlineSyncProvider = ChangeNotifierProvider<OfflineSyncService>((ref) {
  final service = OfflineSyncService(
    ref.watch(offlineStorageProvider),
    ref.read(authNotifierProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
