import 'package:equatable/equatable.dart';
import 'package:planpal_flutter/core/dtos/user_summary.dart';
import 'package:planpal_flutter/core/utils/server_datetime.dart';

double _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

class BudgetBreakdownUser extends Equatable {
  final String id;
  final String username;
  final String fullName;

  const BudgetBreakdownUser({
    required this.id,
    required this.username,
    required this.fullName,
  });

  factory BudgetBreakdownUser.fromJson(Map<String, dynamic> json) {
    return BudgetBreakdownUser(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      fullName:
          json['full_name']?.toString() ?? json['username']?.toString() ?? '',
    );
  }

  @override
  List<Object?> get props => [id, username, fullName];
}

class BudgetBreakdownItem extends Equatable {
  final BudgetBreakdownUser user;
  final double amount;

  const BudgetBreakdownItem({required this.user, required this.amount});

  factory BudgetBreakdownItem.fromJson(Map<String, dynamic> json) {
    return BudgetBreakdownItem(
      user: BudgetBreakdownUser.fromJson(
        Map<String, dynamic>.from(
          json['user'] as Map? ?? const <String, dynamic>{},
        ),
      ),
      amount: _asDouble(json['amount']),
    );
  }

  @override
  List<Object?> get props => [user, amount];
}

class BudgetTrendPoint extends Equatable {
  final DateTime date;
  final double amount;

  const BudgetTrendPoint({required this.date, required this.amount});

  factory BudgetTrendPoint.fromJson(Map<String, dynamic> json) {
    return BudgetTrendPoint(
      date: parseServerDateTime(json['date']) ?? DateTime.now(),
      amount: _asDouble(json['amount']),
    );
  }

  @override
  List<Object?> get props => [date, amount];
}

class BudgetModel extends Equatable {
  final String budgetId;
  final String planId;
  final String currency;
  final double totalBudget;
  final double totalSpent;
  final double remainingBudget;
  final double spentPercentage;
  final bool nearLimit;
  final bool overBudget;
  final int expenseCount;
  final List<BudgetBreakdownItem> breakdown;
  final List<BudgetTrendPoint> trend;

  const BudgetModel({
    required this.budgetId,
    required this.planId,
    required this.currency,
    required this.totalBudget,
    required this.totalSpent,
    required this.remainingBudget,
    required this.spentPercentage,
    required this.nearLimit,
    required this.overBudget,
    required this.expenseCount,
    required this.breakdown,
    required this.trend,
  });

  factory BudgetModel.fromJson(Map<String, dynamic> json) {
    final rawBreakdown =
        json['breakdown'] as List<dynamic>? ?? const <dynamic>[];
    final rawTrend = json['trend'] as List<dynamic>? ?? const <dynamic>[];
    return BudgetModel(
      budgetId: json['budget_id']?.toString() ?? '',
      planId: json['plan_id']?.toString() ?? '',
      currency: json['currency']?.toString() ?? 'VND',
      totalBudget: _asDouble(json['total_budget']),
      totalSpent: _asDouble(json['total_spent']),
      remainingBudget: _asDouble(json['remaining_budget']),
      spentPercentage: _asDouble(json['spent_percentage']),
      nearLimit: json['near_limit'] == true,
      overBudget: json['over_budget'] == true,
      expenseCount: _asInt(json['expense_count']),
      breakdown: rawBreakdown
          .whereType<Map>()
          .map(
            (item) =>
                BudgetBreakdownItem.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      trend: rawTrend
          .whereType<Map>()
          .map(
            (item) =>
                BudgetTrendPoint.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }

  bool get hasBudgetConfigured => totalBudget > 0;

  @override
  List<Object?> get props => [
    budgetId,
    planId,
    currency,
    totalBudget,
    totalSpent,
    remainingBudget,
    spentPercentage,
    nearLimit,
    overBudget,
    expenseCount,
    breakdown,
    trend,
  ];
}

class ExpenseModel extends Equatable {
  final String id;
  final String planId;
  final String userId;
  final UserSummary user;
  final double amount;
  final String category;
  final String description;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const ExpenseModel({
    required this.id,
    required this.planId,
    required this.userId,
    required this.user,
    required this.amount,
    required this.category,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ExpenseModel.fromJson(Map<String, dynamic> json) {
    return ExpenseModel(
      id: json['id']?.toString() ?? '',
      planId: json['plan_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      user: UserSummary.fromJson(
        Map<String, dynamic>.from(
          json['user'] as Map? ?? const <String, dynamic>{},
        ),
      ),
      amount: _asDouble(json['amount']),
      category: json['category']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      createdAt: parseServerDateTime(json['created_at']) ?? DateTime.now(),
      updatedAt: parseServerDateTime(json['updated_at']),
    );
  }

  @override
  List<Object?> get props => [
    id,
    planId,
    userId,
    user,
    amount,
    category,
    description,
    createdAt,
    updatedAt,
  ];
}

class ExpenseWarningModel extends Equatable {
  final String code;
  final String level;
  final String message;
  final Map<String, dynamic> data;

  const ExpenseWarningModel({
    required this.code,
    required this.level,
    required this.message,
    required this.data,
  });

  factory ExpenseWarningModel.fromJson(Map<String, dynamic> json) {
    return ExpenseWarningModel(
      code: json['code']?.toString() ?? '',
      level: json['level']?.toString() ?? 'info',
      message: json['message']?.toString() ?? '',
      data: json['data'] is Map
          ? Map<String, dynamic>.from(json['data'] as Map)
          : const <String, dynamic>{},
    );
  }

  @override
  List<Object?> get props => [code, level, message, data];
}

class ExpenseCreateResult extends Equatable {
  final ExpenseModel expense;
  final BudgetModel summary;
  final List<ExpenseWarningModel> warnings;

  const ExpenseCreateResult({
    required this.expense,
    required this.summary,
    required this.warnings,
  });

  factory ExpenseCreateResult.fromJson(Map<String, dynamic> json) {
    final rawWarnings = json['warnings'] as List<dynamic>? ?? const <dynamic>[];
    return ExpenseCreateResult(
      expense: ExpenseModel.fromJson(
        Map<String, dynamic>.from(
          json['expense'] as Map? ?? const <String, dynamic>{},
        ),
      ),
      summary: BudgetModel.fromJson(
        Map<String, dynamic>.from(
          json['summary'] as Map? ?? const <String, dynamic>{},
        ),
      ),
      warnings: rawWarnings
          .whereType<Map>()
          .map(
            (item) =>
                ExpenseWarningModel.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }

  @override
  List<Object?> get props => [expense, summary, warnings];
}

class ExpenseFilter extends Equatable {
  final String? category;
  final String? userId;
  final String sortBy;
  final String sortDirection;
  final int pageSize;

  const ExpenseFilter({
    this.category,
    this.userId,
    this.sortBy = 'created_at',
    this.sortDirection = 'desc',
    this.pageSize = 20,
  });

  Map<String, dynamic> toQueryParameters() {
    return {
      if (category != null && category!.trim().isNotEmpty) 'category': category,
      if (userId != null && userId!.trim().isNotEmpty) 'user_id': userId,
      'sort_by': sortBy,
      'sort_direction': sortDirection,
      'page_size': pageSize,
    };
  }

  ExpenseFilter copyWith({
    String? category,
    String? userId,
    String? sortBy,
    String? sortDirection,
    int? pageSize,
  }) {
    return ExpenseFilter(
      category: category ?? this.category,
      userId: userId ?? this.userId,
      sortBy: sortBy ?? this.sortBy,
      sortDirection: sortDirection ?? this.sortDirection,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  @override
  List<Object?> get props => [
    category,
    userId,
    sortBy,
    sortDirection,
    pageSize,
  ];
}

class ExpenseListQuery extends Equatable {
  final String planId;
  final ExpenseFilter filter;

  const ExpenseListQuery({
    required this.planId,
    this.filter = const ExpenseFilter(),
  });

  ExpenseListQuery copyWith({String? planId, ExpenseFilter? filter}) {
    return ExpenseListQuery(
      planId: planId ?? this.planId,
      filter: filter ?? this.filter,
    );
  }

  @override
  List<Object?> get props => [planId, filter];
}

class ExpensePageResponse extends Equatable {
  final List<ExpenseModel> items;
  final String? nextPageUrl;
  final int count;
  final int currentPage;
  final int totalPages;
  final int pageSize;

  const ExpensePageResponse({
    required this.items,
    required this.nextPageUrl,
    required this.count,
    required this.currentPage,
    required this.totalPages,
    required this.pageSize,
  });

  factory ExpensePageResponse.fromJson(Map<String, dynamic> json) {
    final rawResults = json['results'] as List<dynamic>? ?? const <dynamic>[];
    return ExpensePageResponse(
      items: rawResults
          .whereType<Map>()
          .map((item) => ExpenseModel.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      nextPageUrl: json['next']?.toString(),
      count: _asInt(json['count']),
      currentPage: _asInt(json['current_page']),
      totalPages: _asInt(json['total_pages']),
      pageSize: _asInt(json['page_size']),
    );
  }

  bool get hasMore => nextPageUrl != null && nextPageUrl!.isNotEmpty;

  @override
  List<Object?> get props => [
    items,
    nextPageUrl,
    count,
    currentPage,
    totalPages,
    pageSize,
  ];
}
