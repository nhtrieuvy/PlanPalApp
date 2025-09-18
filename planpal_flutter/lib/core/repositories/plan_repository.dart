import 'package:dio/dio.dart';
import 'package:planpal_flutter/core/providers/auth_provider.dart';
import 'package:planpal_flutter/core/services/apis.dart';
import 'package:planpal_flutter/core/services/api_error.dart';
import 'package:planpal_flutter/core/dtos/plan_requests.dart';
import '../dtos/plan_summary.dart';
import '../dtos/plan_model.dart';
import '../dtos/plan_activity_requests.dart';

class PlanRepository {
  final AuthProvider _auth;
  final Map<String, PlanModel> _detailCache = {};

  PlanRepository(this._auth);

  // Plan CRUD operations
  Future<PlanModel> createPlan(CreatePlanRequest request) async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (c) => c.dio.post(Endpoints.plans, data: request.toJson()),
      );

      if (res.statusCode == 201 && res.data is Map) {
        return PlanModel.fromJson(Map<String, dynamic>.from(res.data as Map));
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  Future<List<PlanSummary>> getPlans() async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (c) => c.dio.get(Endpoints.plans),
      );

      if (res.statusCode == 200) {
        final data = res.data;
        // Handle paginated response with 'results' array
        final List<dynamic> rawList = (data is Map && data['results'] is List)
            ? List<dynamic>.from(data['results'] as List)
            : const <dynamic>[];

        if (rawList.isEmpty) return const <PlanSummary>[];
        final parsed = <PlanSummary>[];
        for (final item in rawList) {
          if (item is Map) {
            parsed.add(PlanSummary.fromJson(Map<String, dynamic>.from(item)));
          }
        }
        return parsed;
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  Future<PlanModel> getPlanDetail(String id) async {
    if (_detailCache.containsKey(id)) {
      return _detailCache[id]!;
    }

    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (c) => c.dio.get(Endpoints.planDetails(id)),
      );

      if (res.statusCode == 200 && res.data is Map) {
        final detail = PlanModel.fromJson(
          Map<String, dynamic>.from(res.data as Map),
        );
        _detailCache[id] = detail;
        return detail;
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  Future<PlanModel> updatePlan(String planId, UpdatePlanRequest request) async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (c) => c.dio.put(Endpoints.planDetails(planId), data: request.toJson()),
      );

      if (res.statusCode == 200 && res.data is Map) {
        final detail = PlanModel.fromJson(
          Map<String, dynamic>.from(res.data as Map),
        );
        _detailCache[planId] = detail;
        return detail;
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  Future<void> deletePlan(String planId) async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (c) => c.dio.delete(Endpoints.planDetails(planId)),
      );

      if (res.statusCode == 204 || res.statusCode == 200) {
        _detailCache.remove(planId);
        return;
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  // Plan activities operations
  Future<List<dynamic>> getPlanActivitiesByDate(
    String planId,
    String date,
  ) async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (c) => c.dio.get(Endpoints.planActivitiesByDate(planId, date)),
      );

      if (res.statusCode == 200) {
        // Activities by date might return different structure, check if it's activities array
        if (res.data is List) {
          return res.data;
        } else if (res.data is Map<String, dynamic>) {
          return res.data['activities'] ?? res.data['results'] ?? [];
        }
        return [];
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getPlanSchedule(String planId) async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (c) => c.dio.get(Endpoints.planSchedule(planId)),
      );

      if (res.statusCode == 200) {
        return res.data;
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  Future<PlanModel> joinPlan(String planId) async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (c) => c.dio.post(Endpoints.planJoin(planId)),
      );

      if (res.statusCode == 200 && res.data is Map) {
        final detail = PlanModel.fromJson(
          Map<String, dynamic>.from(res.data as Map),
        );
        _detailCache[planId] = detail;
        return detail;
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  Future<List<PlanSummary>> getGroupPlans(String groupId) async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (c) => c.dio.get(Endpoints.groupPlans(groupId)),
      );

      if (res.statusCode == 200) {
        final data = res.data;
        // Handle response with 'plans' array
        final List<dynamic> rawList = (data is Map && data['plans'] is List)
            ? List<dynamic>.from(data['plans'] as List)
            : const <dynamic>[];

        if (rawList.isEmpty) return const <PlanSummary>[];
        final parsed = <PlanSummary>[];
        for (final item in rawList) {
          if (item is Map) {
            try {
              parsed.add(PlanSummary.fromJson(Map<String, dynamic>.from(item)));
            } catch (e) {
              continue;
            }
          }
        }
        return parsed;
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  Future<List<PlanSummary>> getJoinedPlans() async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (c) => c.dio.get(Endpoints.joinedPlans),
      );

      if (res.statusCode == 200) {
        final data = res.data;
        // Handle paginated response with 'results' array
        final List<dynamic> rawList = (data is Map && data['results'] is List)
            ? List<dynamic>.from(data['results'] as List)
            : const <dynamic>[];

        if (rawList.isEmpty) return const <PlanSummary>[];
        final parsed = <PlanSummary>[];
        for (final item in rawList) {
          if (item is Map) {
            try {
              parsed.add(PlanSummary.fromJson(Map<String, dynamic>.from(item)));
            } catch (e) {
              continue;
            }
          }
        }
        return parsed;
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  Future<List<PlanSummary>> searchPublicPlans(String query) async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (c) => c.dio.get(
          Endpoints.publicPlans,
          queryParameters: {'search': query},
        ),
      );

      if (res.statusCode == 200) {
        final data = res.data;
        // Handle paginated response with 'results' array
        final List<dynamic> rawList = (data is Map && data['results'] is List)
            ? List<dynamic>.from(data['results'] as List)
            : const <dynamic>[];

        if (rawList.isEmpty) return const <PlanSummary>[];
        final parsed = <PlanSummary>[];
        for (final item in rawList) {
          if (item is Map) {
            try {
              parsed.add(PlanSummary.fromJson(Map<String, dynamic>.from(item)));
            } catch (e) {
              continue;
            }
          }
        }
        return parsed;
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  // Activity CRUD operations
  Future<Map<String, dynamic>> createActivity(
    CreatePlanActivityRequest request,
  ) async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (c) => c.dio.post(Endpoints.activities, data: request.toJson()),
      );

      if (res.statusCode == 201) {
        return res.data;
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> updateActivity(
    String activityId,
    UpdatePlanActivityRequest request,
  ) async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (c) => c.dio.put(
          Endpoints.activityDetails(activityId),
          data: request.toJson(),
        ),
      );

      if (res.statusCode == 200) {
        return res.data;
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  Future<void> deleteActivity(String activityId) async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (c) => c.dio.delete(Endpoints.activityDetails(activityId)),
      );

      if (res.statusCode != 204) {
        throw buildApiException(res);
      }
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> toggleActivityCompletion(
    String planId,
    String activityId,
  ) async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (c) =>
            c.dio.post(Endpoints.activityToggleCompletion(planId, activityId)),
      );

      if (res.statusCode == 200) {
        return res.data;
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  // // Additional methods from PlanService
  // Future<Map<String, dynamic>> getPlanSummary(String planId) async {
  //   try {
  //     final Response res = await _auth.requestWithAutoRefresh(
  //       (c) => c.dio.get(Endpoints.planSummary(planId)),
  //     );

  //     if (res.statusCode == 200) {
  //       return Map<String, dynamic>.from(res.data);
  //     }
  //     throw buildApiException(res);
  //   } on DioException catch (e) {
  //     if (e.response != null) throw buildApiException(e.response!);
  //     rethrow;
  //   }
  // }

  // Future<List<Map<String, dynamic>>> getPlanCollaborators(String planId) async {
  //   try {
  //     final Response res = await _auth.requestWithAutoRefresh(
  //       (c) => c.dio.get(Endpoints.planCollaborators(planId)),
  //     );

  //     if (res.statusCode == 200) {
  //       final data = res.data;
  //       final List<dynamic> rawList =
  //           (data is Map && data['collaborators'] is List)
  //           ? List<dynamic>.from(data['collaborators'] as List)
  //           : (data is List ? List<dynamic>.from(data) : const <dynamic>[]);

  //       return rawList
  //           .map((item) => Map<String, dynamic>.from(item as Map))
  //           .toList();
  //     }
  //     throw buildApiException(res);
  //   } on DioException catch (e) {
  //     if (e.response != null) throw buildApiException(e.response!);
  //     rethrow;
  //   }
  // }

  // Cache management
  void clearCache() => _detailCache.clear();

  void clearCacheEntry(String id) => _detailCache.remove(id);
}
