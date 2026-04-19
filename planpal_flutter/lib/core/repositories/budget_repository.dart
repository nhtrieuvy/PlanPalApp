import 'package:dio/dio.dart';
import 'package:planpal_flutter/core/auth/auth_session.dart';
import 'package:planpal_flutter/core/dtos/budget_model.dart';
import 'package:planpal_flutter/core/services/api_error.dart';
import 'package:planpal_flutter/core/services/apis.dart';

class BudgetRepository {
  final AuthProvider _auth;

  BudgetRepository(this._auth);

  Future<BudgetModel> getBudget(String planId) async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (c) => c.dio.get(Endpoints.planBudget(planId)),
      );
      if (res.statusCode == 200 && res.data is Map) {
        return BudgetModel.fromJson(Map<String, dynamic>.from(res.data as Map));
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  Future<BudgetModel> updateBudget(
    String planId, {
    required double totalBudget,
    String currency = 'VND',
  }) async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (c) => c.dio.post(
          Endpoints.planBudget(planId),
          data: {'total_budget': totalBudget, 'currency': currency},
        ),
      );
      if (res.statusCode == 200 && res.data is Map) {
        return BudgetModel.fromJson(Map<String, dynamic>.from(res.data as Map));
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  Future<ExpenseCreateResult> addExpense(
    String planId, {
    required double amount,
    required String category,
    String description = '',
  }) async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (c) => c.dio.post(
          Endpoints.planExpenses(planId),
          data: {
            'amount': amount,
            'category': category,
            'description': description,
          },
        ),
      );
      if (res.statusCode == 201 && res.data is Map) {
        return ExpenseCreateResult.fromJson(
          Map<String, dynamic>.from(res.data as Map),
        );
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  Future<ExpensePageResponse> getExpenses(
    String planId, {
    ExpenseFilter filter = const ExpenseFilter(),
    String? nextPageUrl,
  }) async {
    try {
      final normalizedNext = _normalizePageUrl(nextPageUrl);
      final Response res = await _auth.requestWithAutoRefresh(
        (c) => c.getPaginated(
          Endpoints.planExpenses(planId),
          pageUrl: normalizedNext,
          queryParameters: normalizedNext == null
              ? filter.toQueryParameters()
              : null,
        ),
      );
      if (res.statusCode == 200 && res.data is Map) {
        return ExpensePageResponse.fromJson(
          Map<String, dynamic>.from(res.data as Map),
        );
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  String? _normalizePageUrl(String? pageUrl) {
    if (pageUrl == null || pageUrl.isEmpty) return null;

    final parsed = Uri.tryParse(pageUrl);
    if (parsed == null) return pageUrl;
    if (!parsed.hasAuthority || !parsed.hasScheme) return pageUrl;

    final target = Uri.parse(baseUrl);
    return parsed
        .replace(
          scheme: target.scheme,
          host: target.host,
          port: target.hasPort ? target.port : parsed.port,
        )
        .toString();
  }
}
