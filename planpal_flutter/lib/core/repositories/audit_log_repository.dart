import 'package:dio/dio.dart';
import 'package:planpal_flutter/core/auth/auth_session.dart';
import 'package:planpal_flutter/core/dtos/audit_log_model.dart';
import 'package:planpal_flutter/core/services/api_error.dart';
import 'package:planpal_flutter/core/services/apis.dart';

class AuditLogRepository {
  final AuthProvider _auth;

  AuditLogRepository(this._auth);

  Future<AuditLogsResponse> getAuditLogs({
    AuditLogFilter filters = const AuditLogFilter(),
    String? nextPageUrl,
  }) async {
    return _fetchLogs(
      endpoint: Endpoints.auditLogs,
      filters: filters,
      nextPageUrl: nextPageUrl,
    );
  }

  Future<AuditLogsResponse> getLogsByResource({
    required String resourceType,
    required String resourceId,
    AuditLogFilter filters = const AuditLogFilter(),
    String? nextPageUrl,
  }) async {
    return _fetchLogs(
      endpoint: Endpoints.resourceAuditLogs(resourceType, resourceId),
      filters: filters,
      nextPageUrl: nextPageUrl,
    );
  }

  Future<AuditLogsResponse> _fetchLogs({
    required String endpoint,
    required AuditLogFilter filters,
    String? nextPageUrl,
  }) async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (client) => client.getPaginated(
          endpoint,
          pageUrl: nextPageUrl,
          queryParameters: nextPageUrl == null
              ? filters.toQueryParameters()
              : null,
        ),
      );

      if (res.statusCode == 200 && res.data is Map) {
        return AuditLogsResponse.fromJson(
          Map<String, dynamic>.from(res.data as Map),
        );
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }
}
