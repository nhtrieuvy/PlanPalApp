import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

import 'offline_storage.dart';

OfflineStorage createPlatformOfflineStorage(SharedPreferences preferences) =>
    IndexedDbOfflineStorage(preferences);

class IndexedDbOfflineStorage implements OfflineStorage {
  IndexedDbOfflineStorage(this._legacyPreferences);

  static const _databaseName = 'planpal_offline';
  static const _storeName = 'state';
  static const _snapshotKey = 'snapshot';
  final SharedPreferences _legacyPreferences;
  final Map<String, String> _cache = {};
  web.IDBDatabase? _database;
  Future<void> _writeTail = Future<void>.value();

  @override
  Future<void> initialize() async {
    _database = await _openDatabase();
    final raw = await _readSnapshot();
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        _cache.addAll(decoded.map((key, value) => MapEntry(key, '$value')));
      } catch (_) {
        _cache.clear();
      }
    }
    await _migrateLegacyPreferences();
  }

  @override
  String? getString(String key) => _cache[key];

  @override
  Set<String> getKeys() => _cache.keys.toSet();

  @override
  Future<void> setString(String key, String value) {
    _cache[key] = value;
    return _persist();
  }

  @override
  Future<void> remove(String key) {
    _cache.remove(key);
    return _persist();
  }

  @override
  Future<void> removeWhere(bool Function(String key) predicate) {
    _cache.removeWhere((key, _) => predicate(key));
    return _persist();
  }

  Future<void> _migrateLegacyPreferences() async {
    final legacyKeys = _legacyPreferences.getKeys().where(
      (key) => offlineStoragePrefixes.any(key.startsWith),
    );
    var changed = false;
    final migratedKeys = <String>[];
    for (final key in legacyKeys) {
      final value = _legacyPreferences.getString(key);
      if (value == null) continue;
      _cache.putIfAbsent(key, () => value);
      migratedKeys.add(key);
      changed = true;
    }
    if (!changed) return;
    await _persist();
    await Future.wait(migratedKeys.map(_legacyPreferences.remove));
  }

  Future<web.IDBDatabase> _openDatabase() {
    final completer = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(_databaseName, 1);
    request.onupgradeneeded = ((web.Event _) {
      final database = request.result! as web.IDBDatabase;
      if (!database.objectStoreNames.contains(_storeName)) {
        database.createObjectStore(_storeName);
      }
    }).toJS;
    request.onsuccess = ((web.Event _) {
      completer.complete(request.result! as web.IDBDatabase);
    }).toJS;
    request.onerror = ((web.Event _) {
      completer.completeError(
        StateError(request.error?.message ?? 'Could not open IndexedDB.'),
      );
    }).toJS;
    return completer.future;
  }

  Future<String?> _readSnapshot() async {
    final database = _database!;
    final transaction = database.transaction(_storeName.toJS, 'readonly');
    final request = transaction.objectStore(_storeName).get(_snapshotKey.toJS);
    final result = await _waitForRequest(request);
    return result?.dartify()?.toString();
  }

  Future<void> _persist() {
    final snapshot = jsonEncode(_cache);
    _writeTail = _writeTail.catchError((_) {}).then((_) async {
      final database = _database!;
      final transaction = database.transaction(_storeName.toJS, 'readwrite');
      final request = transaction
          .objectStore(_storeName)
          .put(snapshot.toJS, _snapshotKey.toJS);
      await _waitForRequest(request);
      await _waitForTransaction(transaction);
    });
    return _writeTail;
  }

  Future<void> _waitForTransaction(web.IDBTransaction transaction) {
    final completer = Completer<void>();
    transaction.oncomplete = ((web.Event _) {
      completer.complete();
    }).toJS;
    transaction.onerror = ((web.Event _) {
      completer.completeError(
        StateError(transaction.error?.message ?? 'IndexedDB write failed.'),
      );
    }).toJS;
    transaction.onabort = ((web.Event _) {
      completer.completeError(StateError('IndexedDB write was aborted.'));
    }).toJS;
    return completer.future;
  }

  Future<JSAny?> _waitForRequest(web.IDBRequest request) {
    final completer = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) {
      completer.complete(request.result);
    }).toJS;
    request.onerror = ((web.Event _) {
      completer.completeError(
        StateError(request.error?.message ?? 'IndexedDB operation failed.'),
      );
    }).toJS;
    return completer.future;
  }
}
