import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:planpal_flutter/core/auth/auth_session.dart';
import 'package:planpal_flutter/core/storage/offline_storage.dart';

class OfflineMutation {
  const OfflineMutation({
    required this.id,
    required this.method,
    required this.path,
    required this.data,
    required this.createdAt,
    this.attempts = 0,
  });

  final String id;
  final String method;
  final String path;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final int attempts;

  factory OfflineMutation.fromJson(Map<String, dynamic> json) =>
      OfflineMutation(
        id: json['id']?.toString() ?? '',
        method: json['method']?.toString() ?? 'POST',
        path: json['path']?.toString() ?? '',
        data: Map<String, dynamic>.from(json['data'] as Map? ?? const {}),
        createdAt:
            DateTime.tryParse(json['created_at']?.toString() ?? '') ??
            DateTime.now(),
        attempts: int.tryParse(json['attempts']?.toString() ?? '') ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'method': method,
    'path': path,
    'data': data,
    'created_at': createdAt.toIso8601String(),
    'attempts': attempts,
  };

  OfflineMutation attempted() => OfflineMutation(
    id: id,
    method: method,
    path: path,
    data: data,
    createdAt: createdAt,
    attempts: attempts + 1,
  );
}

class OfflineSyncService extends ChangeNotifier {
  OfflineSyncService(this._storage, this._auth) {
    _activeUserScope = _currentUserScope;
    _auth.addListener(_handleAuthChanged);
  }

  static const _queuePrefix = 'offline_sync_queue';
  static const _deadLetterPrefix = 'offline_sync_dead_letters';
  static const _draftPrefix = 'offline_draft';

  final OfflineStorage _storage;
  final AuthProvider _auth;
  Timer? _timer;
  bool _syncing = false;
  Future<void> _queueWrite = Future<void>.value();
  int _pendingCount = 0;
  int _mutationSequence = 0;
  late String _activeUserScope;

  bool get isSyncing => _syncing;
  int get pendingCount => _pendingCount;

  void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 20), (_) {
      if (_pendingCount > 0) unawaited(flush());
    });
    _refreshCount();
    unawaited(flush());
  }

  Future<void> onAppResumed() => flush();

  Future<void> enqueue({
    String? id,
    required String method,
    required String path,
    required Map<String, dynamic> data,
  }) async {
    final scope = _userScope;
    final mutationId = id ?? newMutationId();
    await _withQueueWrite(() async {
      final queue = _loadQueue(scope);
      if (queue.any((item) => item.id == mutationId)) return;
      queue.add(
        OfflineMutation(
          id: mutationId,
          method: method.toUpperCase(),
          path: path,
          data: data,
          createdAt: DateTime.now().toUtc(),
        ),
      );
      await _saveQueue(scope, queue);
    });
    unawaited(flush());
  }

  String newMutationId() =>
      '${_userScope}_${DateTime.now().microsecondsSinceEpoch}_${_mutationSequence++}';

  Future<void> flush() async {
    if (_syncing || !_auth.isLoggedIn) return;
    final scope = _userScope;
    final queue = await _withQueueWrite(() async => _loadQueue(scope));
    if (queue.isEmpty) {
      _refreshCount();
      return;
    }
    _syncing = true;
    notifyListeners();
    try {
      final remaining = <OfflineMutation>[];
      final deadLetters = _loadDeadLetters(scope);
      for (var index = 0; index < queue.length; index++) {
        final mutation = queue[index];
        try {
          await _auth.requestWithAutoRefresh(
            (client) => client.dio.request<dynamic>(
              mutation.path,
              data: mutation.data,
              options: Options(
                method: mutation.method,
                headers: {'X-Client-Mutation-ID': mutation.id},
              ),
            ),
          );
        } on DioException catch (error) {
          final status = error.response?.statusCode;
          if (status != null && status >= 400 && status < 500) {
            deadLetters.add(mutation.attempted());
            continue;
          }
          remaining.add(mutation.attempted());
          remaining.addAll(queue.skip(index + 1));
          break;
        } catch (_) {
          remaining.add(mutation.attempted());
          remaining.addAll(queue.skip(index + 1));
          break;
        }
      }
      await _withQueueWrite(() async {
        if (scope != _userScope || !_auth.isLoggedIn) return;
        final snapshotIds = queue.map((item) => item.id).toSet();
        final newlyQueued = _loadQueue(
          scope,
        ).where((item) => !snapshotIds.contains(item.id));
        await _saveDeadLetters(scope, deadLetters.take(50).toList());
        await _saveQueue(scope, [...remaining, ...newlyQueued]);
      });
    } finally {
      _syncing = false;
      _refreshCount();
      if (!_syncing) notifyListeners();
    }
  }

  Future<void> saveDraft(String scope, Map<String, dynamic> draft) async {
    await _storage.setString(_draftKey(scope), jsonEncode(draft));
  }

  Map<String, dynamic>? loadDraft(String scope) {
    final raw = _storage.getString(_draftKey(scope));
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearDraft(String scope) => _storage.remove(_draftKey(scope));

  List<OfflineMutation> _loadQueue(String scope) =>
      _decodeList(_queueKeyFor(scope));
  List<OfflineMutation> _loadDeadLetters(String scope) =>
      _decodeList(_deadLetterKeyFor(scope));

  List<OfflineMutation> _decodeList(String key) {
    try {
      final raw = jsonDecode(_storage.getString(key) ?? '[]') as List;
      return raw
          .whereType<Map>()
          .map(
            (item) => OfflineMutation.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveQueue(String scope, List<OfflineMutation> items) async {
    await _storage.setString(
      _queueKeyFor(scope),
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
    _refreshCount();
  }

  Future<void> _saveDeadLetters(String scope, List<OfflineMutation> items) =>
      _storage.setString(
        _deadLetterKeyFor(scope),
        jsonEncode(items.map((item) => item.toJson()).toList()),
      );

  Future<T> _withQueueWrite<T>(Future<T> Function() action) async {
    final previous = _queueWrite;
    final completed = Completer<void>();
    _queueWrite = completed.future;
    await previous;
    try {
      return await action();
    } finally {
      completed.complete();
    }
  }

  void _refreshCount() {
    final count = _loadQueue(_userScope).length;
    if (count == _pendingCount) return;
    _pendingCount = count;
    notifyListeners();
  }

  String get _currentUserScope => _auth.user?.id ?? 'anonymous';
  String get _userScope => _activeUserScope;
  String _queueKeyFor(String scope) => '$_queuePrefix:$scope';
  String _deadLetterKeyFor(String scope) => '$_deadLetterPrefix:$scope';
  String _draftKey(String scope) => '$_draftPrefix:$_userScope:$scope';

  void _handleAuthChanged() {
    final nextScope = _currentUserScope;
    if (nextScope == _activeUserScope) return;
    _activeUserScope = nextScope;
    _refreshCount();
    if (_auth.isLoggedIn) unawaited(flush());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _auth.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
