import 'package:dio/dio.dart';
import 'package:planpal_flutter/core/auth/auth_session.dart';
import 'dart:io';
import 'package:planpal_flutter/core/services/apis.dart';
import 'package:planpal_flutter/core/services/api_error.dart';
import '../dtos/group_summary.dart';
import '../dtos/group_model.dart';
import '../dtos/group_requests.dart';

class GroupRepository {
  final AuthProvider auth;
  GroupRepository(this.auth); // Constructor

  // Simple in-memory cache for group details
  final Map<String, GroupModel> _detailCache = {};

  Never _throwApiError(Response res) => throw buildApiException(res);

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
    // Trả về từ cache nếu có
    if (!forceRefresh && _detailCache.containsKey(id)) {
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
        _detailCache[id] = detail;
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
        _detailCache[detail.id] = detail;
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
        _detailCache[id] = detail;
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
      _detailCache.remove(id);
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
        // Clear cache để reload dữ liệu mới
        _detailCache.remove(groupId);
        return;
      }
      _throwApiError(res);
    } on DioException catch (e) {
      final r = e.response;
      if (r != null) _throwApiError(r);
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
        _detailCache[detail.id] = detail;
        return detail;
      }
      return _throwApiError(res);
    } on DioException catch (e) {
      final r = e.response;
      if (r != null) return _throwApiError(r);
      rethrow;
    }
  }

  // API rời nhóm
  Future<void> leaveGroup(String groupId) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.post(Endpoints.groupLeave(groupId)),
      );
      if (res.statusCode == 200) {
        _detailCache.remove(groupId);
        return;
      }
      _throwApiError(res);
    } on DioException catch (e) {
      final r = e.response;
      if (r != null) _throwApiError(r);
      rethrow;
    }
  }

  // API xóa thành viên khỏi nhóm
  Future<void> removeMember(String groupId, RemoveMemberRequest request) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.post(
          Endpoints.groupRemoveMember(groupId),
          data: request.toJson(),
        ),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        // Clear cache để reload dữ liệu mới
        _detailCache.remove(groupId);
        return;
      }
      _throwApiError(res);
    } on DioException catch (e) {
      final r = e.response;
      if (r != null) _throwApiError(r);
      rethrow;
    }
  }

  // Cache management
  void clearCache() {
    _detailCache.clear();
  }

  void clearCacheEntry(String groupId) {
    _detailCache.remove(groupId);
  }
}
