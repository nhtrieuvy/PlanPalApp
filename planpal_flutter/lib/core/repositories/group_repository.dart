import 'package:dio/dio.dart';
import 'package:planpal_flutter/core/providers/auth_provider.dart';
import 'package:planpal_flutter/core/services/apis.dart';

class GroupRepository {
  final AuthProvider auth;
  GroupRepository(this.auth); // Constructor

  Never _throwApiError(Response res) {
    final data = res.data;
    if (data is Map && data['error'] != null) {
      throw Exception(data['error'].toString());
    }
    if (data is Map && data['detail'] != null) {
      throw Exception(data['detail'].toString());
    }
    if (data is Map && data['message'] != null) {
      throw Exception(data['message'].toString());
    }
    if (data is Map && data.isNotEmpty) {
      throw Exception(data.values.first.toString());
    }
    throw Exception('Yêu cầu thất bại (${res.statusCode})');
  }

  Future<List<Map<String, dynamic>>> getGroups() async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.get(Endpoints.groups),
      );
      if (res.statusCode == 200) {
        final data = res.data;
        final list = (data is Map && data['groups'] is List)
            ? data['groups']
            : <dynamic>[];
        return List<Map<String, dynamic>>.from(list);
      }
      return _throwApiError(res);
    } on DioException catch (e) {
      final res = e.response;
      if (res != null) return _throwApiError(res);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getGroupDetail(String id) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.get(Endpoints.groupDetails(id)),
      );
      if (res.statusCode == 200 && res.data is Map) {
        return Map<String, dynamic>.from(res.data as Map);
      }
      return _throwApiError(res);
    } on DioException catch (e) {
      final res = e.response;
      if (res != null) return _throwApiError(res);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createGroup(Map<String, dynamic> payload) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.post(Endpoints.groups, data: payload),
      );
      if ((res.statusCode ?? 0) >= 200 && (res.statusCode ?? 0) < 300) {
        return Map<String, dynamic>.from(res.data as Map);
      }
      return _throwApiError(res);
    } on DioException catch (e) {
      final res = e.response;
      if (res != null) return _throwApiError(res);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> updateGroup(
    String id,
    Map<String, dynamic> payload,
  ) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.patch(Endpoints.groupDetails(id), data: payload),
      );
      if (res.statusCode == 200) {
        return Map<String, dynamic>.from(res.data as Map);
      }
      return _throwApiError(res);
    } on DioException catch (e) {
      final res = e.response;
      if (res != null) return _throwApiError(res);
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
      final res = e.response;
      if (res != null) _throwApiError(res);
      rethrow;
    }
  }
}
