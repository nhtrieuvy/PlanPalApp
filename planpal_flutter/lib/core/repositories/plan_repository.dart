import 'package:dio/dio.dart';
import 'package:planpal_flutter/core/providers/auth_provider.dart';
import 'package:planpal_flutter/core/services/apis.dart';
import 'package:planpal_flutter/core/services/api_error.dart';
import '../models/plan_summary.dart';
import '../models/plan_detail.dart';

class PlanRepository {
  final AuthProvider auth;
  PlanRepository(this.auth);

  // Simple in-memory cache for plan details to avoid redundant network calls
  final Map<String, PlanDetail> _detailCache = {};

  Never _throwApiError(Response res) => throw buildApiException(res);

  Future<List<PlanSummary>> getPlans({int? page}) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.get(
          Endpoints.plans,
          queryParameters: {if (page != null) 'page': page},
        ),
      );
      if (res.statusCode == 200) {
        final data = res.data;
        final List<dynamic> rawList = (data is Map && data['plans'] is List)
            ? List<dynamic>.from(data['plans'] as List)
            : (data is List ? List<dynamic>.from(data) : const <dynamic>[]);
        if (rawList.isEmpty) return const <PlanSummary>[]; // fast path
        final parsed = <PlanSummary>[];
        for (final m in rawList) {
          if (m is Map) {
            try {
              parsed.add(PlanSummary.fromJson(Map<String, dynamic>.from(m)));
            } catch (_) {
              /* skip malformed item */
            }
          }
        }
        return parsed;
      }
      return _throwApiError(res);
    } on DioException catch (e) {
      final r = e.response;
      if (r != null) return _throwApiError(r);
      rethrow;
    }
  }

  Future<PlanDetail> getPlanDetail(
    String id, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _detailCache.containsKey(id)) {
      return _detailCache[id]!;
    }
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.get(Endpoints.planDetails(id)),
      );
      if (res.statusCode == 200 && res.data is Map) {
        final detail = PlanDetail.fromJson(
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

  Future<PlanDetail> createPlan(Map<String, dynamic> payload) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.post(Endpoints.plans, data: payload),
      );
      if ((res.statusCode ?? 0) >= 200 && (res.statusCode ?? 0) < 300) {
        final detail = PlanDetail.fromJson(
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

  Future<PlanDetail> updatePlan(String id, Map<String, dynamic> payload) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.patch(Endpoints.planDetails(id), data: payload),
      );
      if (res.statusCode == 200 && res.data is Map) {
        final detail = PlanDetail.fromJson(
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

  Future<void> deletePlan(String id) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.delete(Endpoints.planDetails(id)),
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
