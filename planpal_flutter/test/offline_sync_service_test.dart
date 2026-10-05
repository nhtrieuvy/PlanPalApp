import 'package:flutter_test/flutter_test.dart';
import 'package:planpal_flutter/core/auth/auth_session.dart';
import 'package:planpal_flutter/core/services/offline_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('drafts persist by scope and clear only when requested', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final auth = AuthProvider();
    final service = OfflineSyncService(preferences, auth);

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
    final auth = AuthProvider();
    final service = OfflineSyncService(preferences, auth);

    final first = service.newMutationId();
    final second = service.newMutationId();

    expect(first, startsWith('anonymous_'));
    expect(second, isNot(first));
    service.dispose();
    auth.dispose();
  });
}
