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
  final String paidByUserId;
  final UserSummary paidByUser;
  final double amount;
  final String currency;
  final String category;
  final String description;
  final String splitStrategy;
  final List<ExpenseParticipantModel> participants;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const ExpenseModel({
    required this.id,
    required this.planId,
    required this.userId,
    required this.user,
    required this.paidByUserId,
    required this.paidByUser,
    required this.amount,
    required this.currency,
    required this.category,
    required this.description,
    required this.splitStrategy,
    required this.participants,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ExpenseModel.fromJson(Map<String, dynamic> json) {
    final userJson = Map<String, dynamic>.from(
      json['user'] as Map? ?? const <String, dynamic>{},
    );
    final rawPaidByUser =
        json['paid_by_user'] as Map? ??
        json['user'] as Map? ??
        const <String, dynamic>{};
    final paidByUserJson = Map<String, dynamic>.from(rawPaidByUser);
    final rawParticipants =
        json['participants'] as List<dynamic>? ?? const <dynamic>[];
    return ExpenseModel(
      id: json['id']?.toString() ?? '',
      planId: json['plan_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      user: UserSummary.fromJson(userJson),
      paidByUserId:
          json['paid_by_user_id']?.toString() ??
          json['user_id']?.toString() ??
          '',
      paidByUser: UserSummary.fromJson(paidByUserJson),
      amount: _asDouble(json['amount']),
      currency: json['currency']?.toString() ?? 'VND',
      category: json['category']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      splitStrategy: json['split_strategy']?.toString() ?? 'equal',
      participants: rawParticipants
          .whereType<Map>()
          .map(
            (item) => ExpenseParticipantModel.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
      createdAt: parseServerDateTime(json['created_at']) ?? DateTime.now(),
      updatedAt: parseServerDateTime(json['updated_at']),
    );
  }

  String get splitStrategyLabel {
    switch (splitStrategy) {
      case 'percentage':
        return 'Percentage';
      case 'exact':
        return 'Exact';
      case 'equal':
      default:
        return 'Equal';
    }
  }

  @override
  List<Object?> get props => [
    id,
    planId,
    userId,
    user,
    paidByUserId,
    paidByUser,
    amount,
    currency,
    category,
    description,
    splitStrategy,
    participants,
    createdAt,
    updatedAt,
  ];
}

class ExpenseParticipantModel extends Equatable {
  final String id;
  final String expenseId;
  final String userId;
  final UserSummary user;
  final double owedAmount;
  final double settledAmount;
  final double balance;

  const ExpenseParticipantModel({
    required this.id,
    required this.expenseId,
    required this.userId,
    required this.user,
    required this.owedAmount,
    required this.settledAmount,
    required this.balance,
  });

  factory ExpenseParticipantModel.fromJson(Map<String, dynamic> json) {
    return ExpenseParticipantModel(
      id: json['id']?.toString() ?? '',
      expenseId: json['expense_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      user: UserSummary.fromJson(
        Map<String, dynamic>.from(
          json['user'] as Map? ?? const <String, dynamic>{},
        ),
      ),
      owedAmount: _asDouble(json['owed_amount']),
      settledAmount: _asDouble(json['settled_amount']),
      balance: _asDouble(json['balance']),
    );
  }

  @override
  List<Object?> get props => [
    id,
    expenseId,
    userId,
    user,
    owedAmount,
    settledAmount,
    balance,
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

class ExpenseParticipantInput extends Equatable {
  final String userId;
  final double? amount;
  final double? percentage;

  const ExpenseParticipantInput({
    required this.userId,
    this.amount,
    this.percentage,
  });

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      if (amount != null) 'amount': amount,
      if (percentage != null) 'percentage': percentage,
    };
  }

  @override
  List<Object?> get props => [userId, amount, percentage];
}

class BalanceUser extends Equatable {
  final String id;
  final String username;
  final String fullName;

  const BalanceUser({
    required this.id,
    required this.username,
    required this.fullName,
  });

  factory BalanceUser.fromJson(Map<String, dynamic> json) {
    return BalanceUser(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      fullName:
          json['full_name']?.toString() ?? json['username']?.toString() ?? '',
    );
  }

  @override
  List<Object?> get props => [id, username, fullName];
}

class UserBalanceModel extends Equatable {
  final BalanceUser user;
  final double totalPaid;
  final double totalOwed;
  final double settlementPaid;
  final double settlementReceived;
  final double netBalance;

  const UserBalanceModel({
    required this.user,
    required this.totalPaid,
    required this.totalOwed,
    required this.settlementPaid,
    required this.settlementReceived,
    required this.netBalance,
  });

  factory UserBalanceModel.fromJson(Map<String, dynamic> json) {
    return UserBalanceModel(
      user: BalanceUser.fromJson(
        Map<String, dynamic>.from(
          json['user'] as Map? ?? const <String, dynamic>{},
        ),
      ),
      totalPaid: _asDouble(json['total_paid']),
      totalOwed: _asDouble(json['total_owed']),
      settlementPaid: _asDouble(json['settlement_paid']),
      settlementReceived: _asDouble(json['settlement_received']),
      netBalance: _asDouble(json['net_balance']),
    );
  }

  @override
  List<Object?> get props => [
    user,
    totalPaid,
    totalOwed,
    settlementPaid,
    settlementReceived,
    netBalance,
  ];
}

class DebtSuggestionModel extends Equatable {
  final BalanceUser fromUser;
  final BalanceUser toUser;
  final double amount;

  const DebtSuggestionModel({
    required this.fromUser,
    required this.toUser,
    required this.amount,
  });

  factory DebtSuggestionModel.fromJson(Map<String, dynamic> json) {
    return DebtSuggestionModel(
      fromUser: BalanceUser.fromJson(
        Map<String, dynamic>.from(
          json['from_user'] as Map? ?? const <String, dynamic>{},
        ),
      ),
      toUser: BalanceUser.fromJson(
        Map<String, dynamic>.from(
          json['to_user'] as Map? ?? const <String, dynamic>{},
        ),
      ),
      amount: _asDouble(json['amount']),
    );
  }

  @override
  List<Object?> get props => [fromUser, toUser, amount];
}

class BalanceSummaryModel extends Equatable {
  final String planId;
  final String currency;
  final double totalExpenses;
  final List<UserBalanceModel> balances;
  final List<DebtSuggestionModel> settlementSuggestions;

  const BalanceSummaryModel({
    required this.planId,
    required this.currency,
    required this.totalExpenses,
    required this.balances,
    required this.settlementSuggestions,
  });

  factory BalanceSummaryModel.fromJson(Map<String, dynamic> json) {
    final rawBalances = json['balances'] as List<dynamic>? ?? const <dynamic>[];
    final rawSuggestions =
        json['settlement_suggestions'] as List<dynamic>? ?? const <dynamic>[];
    return BalanceSummaryModel(
      planId: json['plan_id']?.toString() ?? '',
      currency: json['currency']?.toString() ?? 'VND',
      totalExpenses: _asDouble(json['total_expenses']),
      balances: rawBalances
          .whereType<Map>()
          .map(
            (item) =>
                UserBalanceModel.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      settlementSuggestions: rawSuggestions
          .whereType<Map>()
          .map(
            (item) =>
                DebtSuggestionModel.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }

  @override
  List<Object?> get props => [
    planId,
    currency,
    totalExpenses,
    balances,
    settlementSuggestions,
  ];
}

class SettlementModel extends Equatable {
  final String id;
  final String planId;
  final String fromUserId;
  final String toUserId;
  final double amount;
  final String currency;
  final String status;
  final String note;
  final DateTime? settledAt;
  final DateTime createdAt;

  const SettlementModel({
    required this.id,
    required this.planId,
    required this.fromUserId,
    required this.toUserId,
    required this.amount,
    required this.currency,
    required this.status,
    required this.note,
    required this.settledAt,
    required this.createdAt,
  });

  factory SettlementModel.fromJson(Map<String, dynamic> json) {
    return SettlementModel(
      id: json['id']?.toString() ?? '',
      planId: json['plan_id']?.toString() ?? '',
      fromUserId: json['from_user_id']?.toString() ?? '',
      toUserId: json['to_user_id']?.toString() ?? '',
      amount: _asDouble(json['amount']),
      currency: json['currency']?.toString() ?? 'VND',
      status: json['status']?.toString() ?? 'completed',
      note: json['note']?.toString() ?? '',
      settledAt: parseServerDateTime(json['settled_at']),
      createdAt: parseServerDateTime(json['created_at']) ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
    id,
    planId,
    fromUserId,
    toUserId,
    amount,
    currency,
    status,
    note,
    settledAt,
    createdAt,
  ];
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
