import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:planpal_flutter/core/auth/auth_session.dart';
import 'package:planpal_flutter/core/dtos/budget_model.dart';
import 'package:planpal_flutter/core/files/upload_file.dart';
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
    String? paidByUserId,
    String currency = 'VND',
    String splitStrategy = 'equal',
    List<ExpenseParticipantInput> participants = const [],
    List<ExpensePaymentInput> payments = const [],
    String paymentNote = '',
    XFile? receiptFile,
    RecurrenceInput? recurrence,
  }) async {
    try {
      final payload = <String, dynamic>{
        'amount': amount,
        'category': category,
        'description': description,
        'payment_note': paymentNote,
        'currency': currency,
        'split_strategy': splitStrategy,
        if (paidByUserId != null && paidByUserId.isNotEmpty)
          'paid_by_user_id': paidByUserId,
        if (participants.isNotEmpty)
          'participants': participants.map((item) => item.toJson()).toList(),
        if (payments.isNotEmpty)
          'payments': payments.map((item) => item.toJson()).toList(),
        if (recurrence != null) 'recurrence': recurrence.toJson(),
      };
      Object data = payload;
      if (receiptFile != null) {
        data = FormData.fromMap({
          ...payload,
          if (participants.isNotEmpty)
            'participants': jsonEncode(payload['participants']),
          if (payments.isNotEmpty) 'payments': jsonEncode(payload['payments']),
          if (recurrence != null)
            'recurrence': jsonEncode(payload['recurrence']),
          'receipt': await multipartFromXFile(receiptFile),
        });
      }
      final Response res = await _auth.requestWithAutoRefresh(
        (c) => c.dio.post(Endpoints.planExpenses(planId), data: data),
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

  Future<BalanceSummaryModel> getBalances(String planId) async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (c) => c.dio.get(Endpoints.planBalances(planId)),
      );
      if (res.statusCode == 200 && res.data is Map) {
        return BalanceSummaryModel.fromJson(
          Map<String, dynamic>.from(res.data as Map),
        );
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  Future<SettlementModel> createSettlement({
    required String planId,
    required String fromUserId,
    required String toUserId,
    required double amount,
    String currency = 'VND',
    String note = '',
    String paymentNote = '',
    XFile? receiptFile,
  }) async {
    try {
      final payload = <String, dynamic>{
        'plan_id': planId,
        'from_user_id': fromUserId,
        'to_user_id': toUserId,
        'amount': amount,
        'currency': currency,
        'note': note,
        'payment_note': paymentNote,
      };
      final Object data = receiptFile == null
          ? payload
          : FormData.fromMap({
              ...payload,
              'receipt': await multipartFromXFile(receiptFile),
            });
      final Response res = await _auth.requestWithAutoRefresh(
        (c) => c.dio.post(Endpoints.settlements, data: data),
      );
      if (res.statusCode == 201 && res.data is Map) {
        return SettlementModel.fromJson(
          Map<String, dynamic>.from(res.data as Map),
        );
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  Future<List<SettlementModel>> getSettlements(String planId) async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (c) => c.dio.get(
          Endpoints.settlements,
          queryParameters: {'plan_id': planId},
        ),
      );
      if (res.statusCode == 200 && res.data is List) {
        return (res.data as List)
            .whereType<Map>()
            .map(
              (item) =>
                  SettlementModel.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList();
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  Future<SettlementModel> respondToSettlement(
    String settlementId, {
    required String action,
    String rejectionReason = '',
  }) async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (c) => c.dio.post(
          Endpoints.settlementAction(settlementId, action),
          data: {'rejection_reason': rejectionReason},
        ),
      );
      if (res.statusCode == 200 && res.data is Map) {
        return SettlementModel.fromJson(
          Map<String, dynamic>.from(res.data as Map),
        );
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  Future<FinanceInsightsModel> getFinanceInsights(String planId) async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (c) => c.dio.get(Endpoints.planFinanceInsights(planId)),
      );
      if (res.statusCode == 200 && res.data is Map) {
        return FinanceInsightsModel.fromJson(
          Map<String, dynamic>.from(res.data as Map),
        );
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  Future<List<RecurringExpenseModel>> getRecurringExpenses(
    String planId,
  ) async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (c) => c.dio.get(Endpoints.planRecurringExpenses(planId)),
      );
      if (res.statusCode == 200 && res.data is List) {
        return (res.data as List)
            .whereType<Map>()
            .map(
              (item) => RecurringExpenseModel.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList();
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  Future<RecurringExpenseModel> setRecurringExpenseActive(
    String planId,
    String recurringId, {
    required bool isActive,
  }) async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (c) => c.dio.patch(
          Endpoints.planRecurringExpense(planId, recurringId),
          data: {'is_active': isActive},
        ),
      );
      if (res.statusCode == 200 && res.data is Map) {
        return RecurringExpenseModel.fromJson(
          Map<String, dynamic>.from(res.data as Map),
        );
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  Future<ExpenseCreateResult> correctExpense(
    String planId,
    String expenseId, {
    required double amount,
    required String category,
    required String reason,
    String description = '',
    String paymentNote = '',
    XFile? receiptFile,
    String? splitStrategy,
    List<ExpenseParticipantInput>? participants,
  }) async {
    try {
      final payload = <String, dynamic>{
        'amount': amount,
        'category': category,
        'description': description,
        'payment_note': paymentNote,
        'reason': reason,
        if (splitStrategy != null) 'split_strategy': splitStrategy,
        if (participants != null)
          'participants': participants.map((item) => item.toJson()).toList(),
      };
      final Object data = receiptFile == null
          ? payload
          : FormData.fromMap({
              ...payload,
              if (participants != null)
                'participants': jsonEncode(payload['participants']),
              'receipt': await multipartFromXFile(receiptFile),
            });
      final Response res = await _auth.requestWithAutoRefresh(
        (c) => c.dio.post(
          Endpoints.expenseCorrections(planId, expenseId),
          data: data,
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

  Future<void> deleteExpense(String planId, String expenseId) async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (c) => c.dio.delete(Endpoints.planExpense(planId, expenseId)),
      );
      if (res.statusCode == 204) return;
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
