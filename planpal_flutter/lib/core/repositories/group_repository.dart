import 'dart:io';

import 'package:dio/dio.dart';
import 'package:planpal_flutter/core/auth/auth_session.dart';
import 'package:planpal_flutter/core/services/api_error.dart';
import 'package:planpal_flutter/core/services/apis.dart';

import '../dtos/group_model.dart';
import '../dtos/group_invite_model.dart';
import '../dtos/group_requests.dart';
import '../dtos/group_summary.dart';

class GroupRepository {
  final AuthProvider auth;

  GroupRepository(this.auth);

  static const Duration _detailCacheTtl = Duration(seconds: 20);

  // Group roles are permission data. Keep detail cache short-lived so role
  // changes made by another device are not displayed as stale state forever.
  final Map<String, GroupModel> _detailCache = {};
  final Map<String, DateTime> _detailCacheStoredAt = {};

  Never _throwApiError(Response res) => throw buildApiException(res);

  bool _hasFreshDetailCache(String id) {
    final cachedAt = _detailCacheStoredAt[id];
    if (!_detailCache.containsKey(id) || cachedAt == null) return false;
    return DateTime.now().difference(cachedAt) < _detailCacheTtl;
  }

  void _setDetailCache(GroupModel detail) {
    _detailCache[detail.id] = detail;
    _detailCacheStoredAt[detail.id] = DateTime.now();
  }

  void _removeDetailCache(String groupId) {
    _detailCache.remove(groupId);
    _detailCacheStoredAt.remove(groupId);
  }

  Future<List<GroupSummary>> getGroups() async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.get(Endpoints.groups),
      );
      if (res.statusCode == 200) {
        final data = res.data;
        final List<dynamic> rawList = (data is Map && data['results'] is List)
            ? List<dynamic>.from(data['results'] as List)
            : const <dynamic>[];

        if (rawList.isEmpty) return const <GroupSummary>[];
        final parsed = <GroupSummary>[];
        for (final item in rawList) {
          if (item is Map) {
            parsed.add(GroupSummary.fromJson(Map<String, dynamic>.from(item)));
          }
        }
        return parsed;
      }
      return _throwApiError(res);
    } on DioException catch (e) {
      final res = e.response;
      if (res != null) return _throwApiError(res);
      rethrow;
    }
  }

  Future<GroupModel> getGroupDetail(
    String id, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _hasFreshDetailCache(id)) {
      return _detailCache[id]!;
    }

    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.get(Endpoints.groupDetails(id)),
      );
      if (res.statusCode == 200 && res.data is Map) {
        final detail = GroupModel.fromJson(
          Map<String, dynamic>.from(res.data as Map),
        );
        _setDetailCache(detail);
        return detail;
      }
      return _throwApiError(res);
    } on DioException catch (e) {
      final r = e.response;
      if (r != null) return _throwApiError(r);
      rethrow;
    }
  }

  Future<GroupModel> createGroup(
    CreateGroupRequest request, {
    File? avatar,
    File? coverImage,
  }) async {
    try {
      final Response res = await auth.requestWithAutoRefresh((c) {
        if (avatar != null || coverImage != null) {
          final formMap = <String, dynamic>{...request.toJson()};
          if (avatar != null) {
            formMap['avatar'] = MultipartFile.fromFileSync(
              avatar.path,
              filename: avatar.path.split(Platform.pathSeparator).last,
            );
          }
          if (coverImage != null) {
            formMap['cover_image'] = MultipartFile.fromFileSync(
              coverImage.path,
              filename: coverImage.path.split(Platform.pathSeparator).last,
            );
          }
          final form = FormData.fromMap(formMap);
          return c.dio.post(Endpoints.groups, data: form);
        }
        return c.dio.post(Endpoints.groups, data: request.toJson());
      });
      if ((res.statusCode ?? 0) >= 200 && (res.statusCode ?? 0) < 300) {
        final detail = GroupModel.fromJson(
          Map<String, dynamic>.from(res.data as Map),
        );
        _setDetailCache(detail);
        return detail;
      }
      return _throwApiError(res);
    } on DioException catch (e) {
      final r = e.response;
      if (r != null) return _throwApiError(r);
      rethrow;
    }
  }

  Future<GroupModel> updateGroup(
    String id,
    UpdateGroupRequest request, {
    File? avatar,
    File? coverImage,
  }) async {
    try {
      final Response res = await auth.requestWithAutoRefresh((c) {
        if (avatar != null || coverImage != null) {
          final formMap = <String, dynamic>{...request.toJson()};
          if (avatar != null) {
            formMap['avatar'] = MultipartFile.fromFileSync(
              avatar.path,
              filename: avatar.path.split(Platform.pathSeparator).last,
            );
          }
          if (coverImage != null) {
            formMap['cover_image'] = MultipartFile.fromFileSync(
              coverImage.path,
              filename: coverImage.path.split(Platform.pathSeparator).last,
            );
          }
          final form = FormData.fromMap(formMap);
          return c.dio.patch(Endpoints.groupDetails(id), data: form);
        }
        return c.dio.patch(Endpoints.groupDetails(id), data: request.toJson());
      });
      if (res.statusCode == 200) {
        final detail = GroupModel.fromJson(
          Map<String, dynamic>.from(res.data as Map),
        );
        _setDetailCache(detail);
        return detail;
      }
      return _throwApiError(res);
    } on DioException catch (e) {
      final r = e.response;
      if (r != null) return _throwApiError(r);
      rethrow;
    }
  }

  Future<void> deleteGroup(String id) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.delete(Endpoints.groupDetails(id)),
      );
      if ((res.statusCode ?? 0) == 204 || (res.statusCode ?? 0) == 200) return;
      _throwApiError(res);
    } on DioException catch (e) {
      final r = e.response;
      if (r != null) _throwApiError(r);
      rethrow;
    } finally {
      _removeDetailCache(id);
    }
  }

  Future<void> addMember(String groupId, AddMemberRequest request) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.post(
          Endpoints.groupAddMember(groupId),
          data: request.toJson(),
        ),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        _removeDetailCache(groupId);
        return;
      }
      _throwApiError(res);
    } on DioException catch (e) {
      final r = e.response;
      if (r != null) _throwApiError(r);
      rethrow;
    }
  }

  Future<List<GroupInviteModel>> getGroupInvites(String groupId) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.get(Endpoints.groupInvites(groupId)),
      );
      if (res.statusCode == 200 && res.data is Map) {
        final raw = (res.data as Map)['results'];
        if (raw is! List) return const <GroupInviteModel>[];
        return raw
            .whereType<Map>()
            .map(
              (item) =>
                  GroupInviteModel.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList();
      }
      return _throwApiError(res);
    } on DioException catch (e) {
      final r = e.response;
      if (r != null) return _throwApiError(r);
      rethrow;
    }
  }

  Future<GroupInviteModel> createGroupInvite(
    String groupId,
    CreateGroupInviteRequest request,
  ) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) =>
            c.dio.post(Endpoints.groupInvites(groupId), data: request.toJson()),
      );
      if (res.statusCode == 201 && res.data is Map) {
        return GroupInviteModel.fromJson(
          Map<String, dynamic>.from(res.data as Map),
        );
      }
      return _throwApiError(res);
    } on DioException catch (e) {
      final r = e.response;
      if (r != null) return _throwApiError(r);
      rethrow;
    }
  }

  Future<void> revokeGroupInvite(String inviteId) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.delete(Endpoints.groupInviteRevoke(inviteId)),
      );
      if (res.statusCode == 204 || res.statusCode == 200) return;
      _throwApiError(res);
    } on DioException catch (e) {
      final r = e.response;
      if (r != null) _throwApiError(r);
      rethrow;
    }
  }

  Future<List<GroupJoinRequestModel>> getGroupJoinRequests(
    String groupId,
  ) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.get(Endpoints.groupJoinRequests(groupId)),
      );
      if (res.statusCode == 200 && res.data is Map) {
        final raw = (res.data as Map)['results'];
        if (raw is! List) return const <GroupJoinRequestModel>[];
        return raw
            .whereType<Map>()
            .map(
              (item) => GroupJoinRequestModel.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList();
      }
      return _throwApiError(res);
    } on DioException catch (e) {
      final r = e.response;
      if (r != null) return _throwApiError(r);
      rethrow;
    }
  }

  Future<JoinGroupInviteResult> approveGroupJoinRequest(
    String requestId,
  ) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.post(Endpoints.groupJoinRequestApprove(requestId)),
      );
      if (res.statusCode == 200 && res.data is Map) {
        clearCache();
        return JoinGroupInviteResult.fromJson(
          Map<String, dynamic>.from(res.data as Map),
        );
      }
      return _throwApiError(res);
    } on DioException catch (e) {
      final r = e.response;
      if (r != null) return _throwApiError(r);
      rethrow;
    }
  }

  Future<GroupJoinRequestModel> rejectGroupJoinRequest(String requestId) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.post(Endpoints.groupJoinRequestReject(requestId)),
      );
      if (res.statusCode == 200 && res.data is Map) {
        final requestRaw = (res.data as Map)['join_request'];
        if (requestRaw is Map) {
          return GroupJoinRequestModel.fromJson(
            Map<String, dynamic>.from(requestRaw),
          );
        }
      }
      return _throwApiError(res);
    } on DioException catch (e) {
      final r = e.response;
      if (r != null) return _throwApiError(r);
      rethrow;
    }
  }

  Future<JoinGroupInviteResult> joinGroupViaInvite(String token) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.post(Endpoints.groupJoinInvite(token)),
      );
      if (res.statusCode == 200 && res.data is Map) {
        final result = JoinGroupInviteResult.fromJson(
          Map<String, dynamic>.from(res.data as Map),
        );
        clearCache();
        return result;
      }
      return _throwApiError(res);
    } on DioException catch (e) {
      final r = e.response;
      if (r != null) return _throwApiError(r);
      rethrow;
    }
  }

  Future<JoinGroupInviteResult> joinGroupByInviteCode(String code) async {
    try {
      final normalizedCode = code.trim();
      final Response res = await auth.requestWithAutoRefresh(
        (c) =>
            c.dio.post(Endpoints.groupJoinCode, data: {'code': normalizedCode}),
      );
      if (res.statusCode == 200 && res.data is Map) {
        final result = JoinGroupInviteResult.fromJson(
          Map<String, dynamic>.from(res.data as Map),
        );
        clearCache();
        return result;
      }
      return _throwApiError(res);
    } on DioException catch (e) {
      final r = e.response;
      if (r != null) return _throwApiError(r);
      rethrow;
    }
  }

  Future<GroupModel> joinGroup(JoinGroupRequest request) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.post(Endpoints.groupJoin(request.groupId)),
      );
      if (res.statusCode == 200 && res.data is Map) {
        final detail = GroupModel.fromJson(
          Map<String, dynamic>.from(res.data as Map),
        );
        _setDetailCache(detail);
        return detail;
      }
      return _throwApiError(res);
    } on DioException catch (e) {
      final r = e.response;
      if (r != null) return _throwApiError(r);
      rethrow;
    }
  }

  Future<void> leaveGroup(String groupId) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.post(Endpoints.groupLeave(groupId)),
      );
      if (res.statusCode == 200) {
        _removeDetailCache(groupId);
        return;
      }
      _throwApiError(res);
    } on DioException catch (e) {
      final r = e.response;
      if (r != null) _throwApiError(r);
      rethrow;
    }
  }

  Future<void> removeMember(String groupId, RemoveMemberRequest request) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.post(
          Endpoints.groupRemoveMember(groupId),
          data: request.toJson(),
        ),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        _removeDetailCache(groupId);
        return;
      }
      _throwApiError(res);
    } on DioException catch (e) {
      final r = e.response;
      if (r != null) _throwApiError(r);
      rethrow;
    }
  }

  Future<void> changeMemberRole(
    String groupId,
    ChangeMemberRoleRequest request,
  ) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.post(
          Endpoints.groupChangeRole(groupId),
          data: request.toJson(),
        ),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        _removeDetailCache(groupId);
        return;
      }
      _throwApiError(res);
    } on DioException catch (e) {
      final r = e.response;
      if (r != null) _throwApiError(r);
      rethrow;
    }
  }

  void clearCache() {
    _detailCache.clear();
    _detailCacheStoredAt.clear();
  }

  void clearCacheEntry(String groupId) {
    _removeDetailCache(groupId);
  }
}
