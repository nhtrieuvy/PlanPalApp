abstract interface class OfflineStorage {
  Future<void> initialize();

  String? getString(String key);

  Set<String> getKeys();

  Future<void> setString(String key, String value);

  Future<void> remove(String key);

  Future<void> removeWhere(bool Function(String key) predicate);
}

const offlineStoragePrefixes = <String>[
  'offline_sync_queue:',
  'offline_sync_dead_letters:',
  'offline_draft:',
];

bool isOfflineStorageKeyForUser(String key, String userId) =>
    key == 'offline_sync_queue:$userId' ||
    key == 'offline_sync_dead_letters:$userId' ||
    key.startsWith('offline_draft:$userId:');
