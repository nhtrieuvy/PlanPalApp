import 'package:shared_preferences/shared_preferences.dart';

import 'offline_storage.dart';
import 'offline_storage_native.dart'
    if (dart.library.js_interop) 'offline_storage_web.dart'
    as implementation;

Future<OfflineStorage> createOfflineStorage(
  SharedPreferences preferences,
) async {
  final storage = implementation.createPlatformOfflineStorage(preferences);
  await storage.initialize();
  return storage;
}
