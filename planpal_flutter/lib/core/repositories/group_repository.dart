import 'package:dio/dio.dart';
import 'package:planpal_flutter/core/providers/auth_provider.dart';
import 'dart:io';
import 'package:planpal_flutter/core/services/apis.dart';
import 'package:planpal_flutter/core/services/api_error.dart';
import '../models/group_summary.dart';
import '../models/group_detail.dart';

class GroupRepository {
  final AuthProvider auth;
  GroupRepository(this.auth); // Constructor

  // Simple in-memory cache for group details
  final Map<String, GroupDetail> _detailCache = {};

  Never _throwApiError(Response res) => throw buildApiException(res);

  Future<List<GroupSummary>> getGroups() async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.get(Endpoints.groups),
      );
      if (res.statusCode == 200) {
        final data = res.data;
        final List<dynamic> rawList = (data is Map && data['groups'] is List)
            ? List<dynamic>.from(data['groups'] as List)
            : (data is List ? List<dynamic>.from(data) : const <dynamic>[]);
        if (rawList.isEmpty) return const <GroupSummary>[];
        final parsed = <GroupSummary>[];
        for (final m in rawList) {
          if (m is Map) {
            try {
              parsed.add(GroupSummary.fromJson(Map<String, dynamic>.from(m)));
            } catch (_) {
              /* skip malformed item */
            }
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

  Future<GroupDetail> getGroupDetail(
    String id, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _detailCache.containsKey(id)) {
      return _detailCache[id]!;
    }
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.get(Endpoints.groupDetails(id)),
      );
      if (res.statusCode == 200 && res.data is Map) {
        final detail = GroupDetail.fromJson(
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

  Future<GroupDetail> createGroup(
    Map<String, dynamic> payload, {
    File? avatar,
    File? coverImage,
  }) async {
    try {
      final Response res = await auth.requestWithAutoRefresh((c) {
        if (avatar != null || coverImage != null) {
          final formMap = <String, dynamic>{...payload};
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
        return c.dio.post(Endpoints.groups, data: payload);
      });
      if ((res.statusCode ?? 0) >= 200 && (res.statusCode ?? 0) < 300) {
        final detail = GroupDetail.fromJson(
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

  Future<GroupDetail> updateGroup(
    String id,
    Map<String, dynamic> payload, {
    File? avatar,
    File? coverImage,
  }) async {
    try {
      final Response res = await auth.requestWithAutoRefresh((c) {
        if (avatar != null || coverImage != null) {
          final formMap = <String, dynamic>{...payload};
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
        return c.dio.patch(Endpoints.groupDetails(id), data: payload);
      });
      if (res.statusCode == 200) {
        final detail = GroupDetail.fromJson(
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
}
