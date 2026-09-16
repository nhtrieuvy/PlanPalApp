import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:planpal_flutter/core/auth/auth_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  OfflineSyncService(this._preferences, this._auth);

  static const _queuePrefix = 'offline_sync_queue';
  static const _deadLetterPrefix = 'offline_sync_dead_letters';
  static const _draftPrefix = 'offline_draft';

  final SharedPreferences _preferences;
  final AuthProvider _auth;
  Timer? _timer;
  bool _syncing = false;
  int _pendingCount = 0;
  int _mutationSequence = 0;

  bool get isSyncing => _syncing;
  int get pendingCount => _pendingCount;

  void start() {
    _timer ??= Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(flush()),
    );
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
    final queue = _loadQueue();
    final mutationId = id ?? newMutationId();
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
    await _saveQueue(queue);
    unawaited(flush());
  }

  String newMutationId() =>
      '${_userScope}_${DateTime.now().microsecondsSinceEpoch}_${_mutationSequence++}';

  Future<void> flush() async {
    if (_syncing || !_auth.isLoggedIn) return;
    final queue = _loadQueue();
    if (queue.isEmpty) return;
    _syncing = true;
    notifyListeners();
    final remaining = <OfflineMutation>[];
    final deadLetters = _loadDeadLetters();
    try {
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
      await _saveQueue(remaining);
      await _saveDeadLetters(deadLetters.take(50).toList());
    } finally {
      _syncing = false;
      _refreshCount();
      notifyListeners();
    }
  }

  Future<void> saveDraft(String scope, Map<String, dynamic> draft) async {
    await _preferences.setString(_draftKey(scope), jsonEncode(draft));
  }

  Map<String, dynamic>? loadDraft(String scope) {
    final raw = _preferences.getString(_draftKey(scope));
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearDraft(String scope) =>
      _preferences.remove(_draftKey(scope));

  List<OfflineMutation> _loadQueue() => _decodeList(_queueKey);
  List<OfflineMutation> _loadDeadLetters() => _decodeList(_deadLetterKey);

  List<OfflineMutation> _decodeList(String key) {
    try {
      final raw = jsonDecode(_preferences.getString(key) ?? '[]') as List;
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

  Future<void> _saveQueue(List<OfflineMutation> items) async {
    await _preferences.setString(
      _queueKey,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
    _refreshCount();
  }

  Future<void> _saveDeadLetters(List<OfflineMutation> items) =>
      _preferences.setString(
        _deadLetterKey,
        jsonEncode(items.map((item) => item.toJson()).toList()),
      );

  void _refreshCount() {
    final count = _loadQueue().length;
    if (count == _pendingCount) return;
    _pendingCount = count;
    notifyListeners();
  }

  String get _userScope => _auth.user?.id ?? 'anonymous';
  String get _queueKey => '$_queuePrefix:$_userScope';
  String get _deadLetterKey => '$_deadLetterPrefix:$_userScope';
  String _draftKey(String scope) => '$_draftPrefix:$_userScope:$scope';

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
