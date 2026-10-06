import 'package:shared_preferences/shared_preferences.dart';

import 'offline_storage.dart';

OfflineStorage createPlatformOfflineStorage(SharedPreferences preferences) =>
    SharedPreferencesOfflineStorage(preferences);

class SharedPreferencesOfflineStorage implements OfflineStorage {
  SharedPreferencesOfflineStorage(this._preferences);

  final SharedPreferences _preferences;

  @override
  Future<void> initialize() async {}

  @override
  String? getString(String key) => _preferences.getString(key);

  @override
  Set<String> getKeys() => _preferences.getKeys();

  @override
  Future<void> setString(String key, String value) async {
    await _preferences.setString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await _preferences.remove(key);
  }

  @override
  Future<void> removeWhere(bool Function(String key) predicate) async {
    final keys = _preferences.getKeys().where(predicate).toList();
    await Future.wait(keys.map(_preferences.remove));
  }
}
