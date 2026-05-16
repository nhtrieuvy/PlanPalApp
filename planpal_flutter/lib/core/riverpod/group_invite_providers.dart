import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dtos/group_invite_model.dart';
import '../repositories/group_repository.dart';
import 'groups_notifier.dart';
import 'repository_providers.dart';

class GroupInvitesNotifier
    extends FamilyAsyncNotifier<List<GroupInviteModel>, String> {
  late GroupRepository _repo;
  late String _groupId;

  @override
  Future<List<GroupInviteModel>> build(String arg) async {
    _repo = ref.watch(groupRepositoryProvider);
    _groupId = arg;
    return _repo.getGroupInvites(arg);
  }

  Future<GroupInviteModel?> createInvite(
    CreateGroupInviteRequest request,
  ) async {
    GroupInviteModel? created;
    state = await AsyncValue.guard(() async {
      created = await _repo.createGroupInvite(_groupId, request);
      return _repo.getGroupInvites(_groupId);
    });
    return created;
  }

  Future<void> revokeInvite(String inviteId) async {
    final previous = state.valueOrNull ?? const <GroupInviteModel>[];
    state = AsyncData(
      previous
          .map(
            (invite) => invite.id == inviteId
                ? GroupInviteModel(
                    id: invite.id,
                    groupId: invite.groupId,
                    token: invite.token,
                    inviteCode: invite.inviteCode,
                    groupVisibility: invite.groupVisibility,
                    createdBy: invite.createdBy,
                    expiresAt: invite.expiresAt,
                    maxUses: invite.maxUses,
                    currentUses: invite.currentUses,
                    remainingUses: invite.remainingUses,
                    isActive: false,
                    isExpired: invite.isExpired,
                    deepLink: invite.deepLink,
                    webLink: invite.webLink,
                    createdAt: invite.createdAt,
                    updatedAt: invite.updatedAt,
                  )
                : invite,
          )
          .toList(),
    );
    final result = await AsyncValue.guard(() async {
      await _repo.revokeGroupInvite(inviteId);
      return _repo.getGroupInvites(_groupId);
    });
    if (result.hasError) {
      state = AsyncData(previous);
      state = AsyncError(result.error!, result.stackTrace!);
      return;
    }
    state = result;
  }
}

final groupInvitesProvider =
    AsyncNotifierProviderFamily<
      GroupInvitesNotifier,
      List<GroupInviteModel>,
      String
    >(GroupInvitesNotifier.new);

class JoinGroupInviteNotifier
    extends AutoDisposeAsyncNotifier<JoinGroupInviteResult?> {
  @override
  Future<JoinGroupInviteResult?> build() async => null;

  Future<JoinGroupInviteResult?> join(String token) async {
    state = const AsyncLoading();
    final repo = ref.read(groupRepositoryProvider);
    final result = await AsyncValue.guard(() => repo.joinGroupViaInvite(token));
    state = result;
    if (result.hasValue && result.value != null) {
      ref.invalidate(groupsNotifierProvider);
    }
    return result.valueOrNull;
  }

  Future<JoinGroupInviteResult?> joinCode(String code) async {
    state = const AsyncLoading();
    final repo = ref.read(groupRepositoryProvider);
    final result = await AsyncValue.guard(
      () => repo.joinGroupByInviteCode(code),
    );
    state = result;
    if (result.hasValue && result.value != null) {
      ref.invalidate(groupsNotifierProvider);
    }
    return result.valueOrNull;
  }
}

final joinGroupProvider =
    AutoDisposeAsyncNotifierProvider<
      JoinGroupInviteNotifier,
      JoinGroupInviteResult?
    >(JoinGroupInviteNotifier.new);

class GroupJoinRequestsNotifier
    extends FamilyAsyncNotifier<List<GroupJoinRequestModel>, String> {
  late GroupRepository _repo;
  late String _groupId;

  @override
  Future<List<GroupJoinRequestModel>> build(String arg) async {
    _repo = ref.watch(groupRepositoryProvider);
    _groupId = arg;
    return _repo.getGroupJoinRequests(arg);
  }

  Future<void> approve(String requestId) async {
    state = await AsyncValue.guard(() async {
      await _repo.approveGroupJoinRequest(requestId);
      return _repo.getGroupJoinRequests(_groupId);
    });
  }

  Future<void> reject(String requestId) async {
    state = await AsyncValue.guard(() async {
      await _repo.rejectGroupJoinRequest(requestId);
      return _repo.getGroupJoinRequests(_groupId);
    });
  }
}

final groupJoinRequestsProvider =
    AsyncNotifierProviderFamily<
      GroupJoinRequestsNotifier,
      List<GroupJoinRequestModel>,
      String
    >(GroupJoinRequestsNotifier.new);
