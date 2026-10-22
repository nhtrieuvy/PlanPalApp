import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planpal_flutter/core/auth/auth_session.dart';
import 'package:planpal_flutter/core/dtos/friendship.dart';
import 'package:planpal_flutter/core/dtos/user_model.dart';
import 'package:planpal_flutter/core/dtos/user_summary.dart';
import 'package:planpal_flutter/core/repositories/friend_repository.dart';
import 'package:planpal_flutter/core/riverpod/auth_notifier.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/presentation/pages/friends/friends_page.dart';

import 'test_app.dart';

void main() {
  setUpAll(() => dotenv.testLoad(fileInput: 'CLIENT_ID=test-client'));

  testWidgets('aligns friend content and keeps it visible on return', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = AuthProvider()
      ..setUser(
        UserModel.fromJson(const {
          'id': 'self',
          'username': 'self',
          'full_name': 'Current User',
        }),
      );
    final friend = UserSummary.fromJson(const {
      'id': 'friend-1',
      'username': 'nguyencao',
      'full_name': 'Nguyễn Cao',
      'initials': 'NC',
    });
    final refresh = Completer<List<UserSummary>>();
    final repository = _FakeFriendRepository(
      auth,
      friend: friend,
      refreshFriends: refresh.future,
    );
    final showFriends = ValueNotifier(true);
    addTearDown(showFriends.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith((ref) => auth),
          friendRepositoryProvider.overrideWithValue(repository),
        ],
        child: buildLocalizedTestApp(
          ValueListenableBuilder<bool>(
            valueListenable: showFriends,
            builder: (_, visible, _) =>
                visible ? const FriendsPage() : const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nguyễn Cao'), findsOneWidget);
    expect(
      tester.getCenter(find.text('NC')).dy,
      closeTo(tester.getCenter(find.byIcon(Icons.arrow_forward_rounded)).dy, 1),
    );

    showFriends.value = false;
    await tester.pump();
    showFriends.value = true;
    await tester.pump();
    expect(find.text('Nguyễn Cao'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Nguyễn Cao'), findsOneWidget);

    refresh.complete([friend]);
    await tester.pumpAndSettle();
  });
}

class _FakeFriendRepository extends FriendRepository {
  _FakeFriendRepository(
    super.auth, {
    required this.friend,
    required this.refreshFriends,
  });

  final UserSummary friend;
  final Future<List<UserSummary>> refreshFriends;
  int _friendCalls = 0;

  @override
  Future<List<UserSummary>> getFriends() {
    _friendCalls += 1;
    return _friendCalls == 1 ? Future.value([friend]) : refreshFriends;
  }

  @override
  Future<List<Friendship>> getPendingRequests() async => [];

  @override
  Future<List<Friendship>> getSentRequests() async => [];

  @override
  Future<List<Map<String, dynamic>>> getTripInvitations() async => [];
}
