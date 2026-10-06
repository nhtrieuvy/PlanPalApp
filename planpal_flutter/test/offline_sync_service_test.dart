import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planpal_flutter/core/auth/auth_session.dart';
import 'package:planpal_flutter/core/dtos/user_model.dart';
import 'package:planpal_flutter/core/services/offline_sync_service.dart';
import 'package:planpal_flutter/core/services/apis.dart';
import 'package:planpal_flutter/core/storage/offline_storage_factory.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DelayedAuthProvider extends AuthProvider {
  final requested = Completer<void>();
  final release = Completer<void>();
  int requests = 0;

  @override
  bool get isLoggedIn => true;

  @override
  Future<Response<T>> requestWithAutoRefresh<T>(
    Future<Response<T>> Function(ApiClient client) requestFn,
  ) async {
    requests++;
    if (requests == 1) {
      requested.complete();
      await release.future;
    }
    return Response<T>(requestOptions: RequestOptions(path: '/'));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  test('drafts persist by scope and clear only when requested', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final storage = await createOfflineStorage(preferences);
    final auth = AuthProvider();
    final service = OfflineSyncService(storage, auth);

    await service.saveDraft('plan_form:new', {
      'title': 'Offline trip',
      'is_public': false,
    });

    expect(service.loadDraft('plan_form:new'), {
      'title': 'Offline trip',
      'is_public': false,
    });
    expect(service.loadDraft('group_form:new'), isNull);

    await service.clearDraft('plan_form:new');
    expect(service.loadDraft('plan_form:new'), isNull);
    service.dispose();
    auth.dispose();
  });

  test('mutation ids are unique and include the current user scope', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final storage = await createOfflineStorage(preferences);
    final auth = AuthProvider();
    final service = OfflineSyncService(storage, auth);

    final first = service.newMutationId();
    final second = service.newMutationId();

    expect(first, startsWith('anonymous_'));
    expect(second, isNot(first));
    service.dispose();
    auth.dispose();
  });

  test(
    'flush preserves mutations enqueued while a request is in flight',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final storage = await createOfflineStorage(preferences);
      final auth = _DelayedAuthProvider();
      final service = OfflineSyncService(storage, auth);

      await service.enqueue(
        id: 'first',
        method: 'POST',
        path: '/first',
        data: {},
      );
      await auth.requested.future;
      await service.enqueue(
        id: 'second',
        method: 'POST',
        path: '/second',
        data: {},
      );
      auth.release.complete();
      while (service.isSyncing) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      final queued =
          jsonDecode(storage.getString('offline_sync_queue:anonymous')!)
              as List<dynamic>;
      expect(queued.map((item) => item['id']), ['second']);
      service.dispose();
      auth.dispose();
    },
  );

  test('logout removes only the active user offline namespace', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final storage = await createOfflineStorage(preferences);
    await storage.setString('offline_sync_queue:user-a', '[]');
    await storage.setString('offline_draft:user-a:plan:new', '{}');
    await storage.setString('offline_sync_queue:user-b', '[{"id":"keep"}]');

    final auth = AuthProvider(offlineStorage: storage)
      ..setUser(
        UserModel.fromJson({
          'id': 'user-a',
          'username': 'user-a',
          'date_joined': DateTime.now().toIso8601String(),
        }),
      );

    await auth.logout();

    expect(storage.getString('offline_sync_queue:user-a'), isNull);
    expect(storage.getString('offline_draft:user-a:plan:new'), isNull);
    expect(storage.getString('offline_sync_queue:user-b'), '[{"id":"keep"}]');
    auth.dispose();
  });
}
