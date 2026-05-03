import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planpal_flutter/core/auth/auth_session.dart';
import 'package:planpal_flutter/core/dtos/friendship.dart';
import 'package:planpal_flutter/core/dtos/user_model.dart';
import 'package:planpal_flutter/core/dtos/user_summary.dart';
import 'package:planpal_flutter/core/repositories/friend_repository.dart';
import 'package:planpal_flutter/core/riverpod/auth_notifier.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/services/api_error.dart';
import 'package:planpal_flutter/presentation/pages/friends/user_profile_page.dart';

import 'test_app.dart';

void main() {
  setUpAll(() async {
    await dotenv.load(fileName: '.env');
  });

  UserSummary buildUserSummary({
    required String id,
    required String username,
    required String fullName,
  }) {
    return UserSummary(
      id: id,
      username: username,
      firstName: fullName.split(' ').first,
      lastName: fullName.split(' ').skip(1).join(' '),
      email: '$username@example.com',
      isOnline: false,
      onlineStatus: 'offline',
      avatarUrl: null,
      hasAvatar: false,
      dateJoined: DateTime(2024, 1, 1),
      lastSeen: DateTime(2024, 1, 1),
      fullName: fullName,
      initials: fullName
          .split(' ')
          .where((part) => part.isNotEmpty)
          .map((part) => part[0])
          .take(2)
          .join()
          .toUpperCase(),
    );
  }

  UserModel buildCurrentUser({required String id, required String username}) {
    return UserModel(
      id: id,
      username: username,
      email: '$username@example.com',
      firstName: 'Current',
      lastName: 'User',
      phoneNumber: null,
      avatar: null,
      avatarUrl: null,
      hasAvatar: false,
      dateOfBirth: null,
      bio: null,
      isOnline: true,
      lastSeen: null,
      isRecentlyOnline: true,
      onlineStatus: 'online',
      plansCount: 0,
      personalPlansCount: 0,
      groupPlansCount: 0,
      groupsCount: 0,
      friendsCount: 0,
      unreadMessagesCount: 0,
      dateJoined: DateTime(2024, 1, 1),
      isActive: true,
      isStaff: false,
      fullName: 'Current User',
      initials: 'CU',
    );
  }

  testWidgets('shows friends state when backend status is friends', (
    tester,
  ) async {
    final auth = AuthProvider()
      ..setUser(buildCurrentUser(id: 'self', username: 'self'));
    final profileUser = buildUserSummary(
      id: 'friend-1',
      username: 'friend1',
      fullName: 'Friend One',
    );

    final repository = _FakeFriendRepository(
      auth,
      profileUser: profileUser,
      initialDetails: const {'status': 'friends'},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authNotifierProvider.overrideWithValue(auth),
          friendRepositoryProvider.overrideWithValue(repository),
        ],
        child: buildLocalizedTestApp(UserProfilePage(user: profileUser)),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Friends'), findsOneWidget);
    expect(find.text('Add friend'), findsNothing);
  });

  testWidgets(
    'reconciles to friends when send request returns already friends',
    (tester) async {
      final auth = AuthProvider()
        ..setUser(buildCurrentUser(id: 'self', username: 'self'));
      final profileUser = buildUserSummary(
        id: 'friend-2',
        username: 'friend2',
        fullName: 'Friend Two',
      );

      final repository = _FakeFriendRepository(
        auth,
        profileUser: profileUser,
        initialDetails: const {'status': 'none'},
        afterSendFailureDetails: const {'status': 'friends'},
        throwAlreadyFriendsOnSend: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authNotifierProvider.overrideWithValue(auth),
            friendRepositoryProvider.overrideWithValue(repository),
          ],
          child: buildLocalizedTestApp(UserProfilePage(user: profileUser)),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Add friend'), findsOneWidget);

      await tester.tap(find.text('Add friend'));
      await tester.pumpAndSettle();

      expect(find.text('Friends'), findsWidgets);
      expect(find.text('Remove friend'), findsOneWidget);
      expect(find.text('Add friend'), findsNothing);
    },
  );
}

class _FakeFriendRepository extends FriendRepository {
  _FakeFriendRepository(
    super.auth, {
    required this.profileUser,
    required this.initialDetails,
    this.afterSendFailureDetails,
    this.throwAlreadyFriendsOnSend = false,
  });

  final UserSummary profileUser;
  final Map<String, dynamic>? initialDetails;
  final Map<String, dynamic>? afterSendFailureDetails;
  final bool throwAlreadyFriendsOnSend;

  int _friendshipDetailsCallCount = 0;

  @override
  Future<UserSummary> getUserProfile(String userId) async {
    return profileUser;
  }

  @override
  Future<Map<String, dynamic>?> getFriendshipDetails(String userId) async {
    _friendshipDetailsCallCount += 1;
    if (_friendshipDetailsCallCount == 1) {
      return initialDetails;
    }
    return afterSendFailureDetails ?? initialDetails;
  }

  @override
  Future<Friendship> sendFriendRequest(
    String friendId, {
    String? message,
  }) async {
    if (throwAlreadyFriendsOnSend) {
      throw const ApiException('Already friends', statusCode: 400);
    }

    return Friendship(
      id: 'friendship-1',
      user: profileUser,
      friend: profileUser,
      initiator: profileUser,
      status: 'pending',
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );
  }
}
