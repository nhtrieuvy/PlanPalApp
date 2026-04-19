import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planpal_flutter/core/auth/auth_session.dart';
import 'package:planpal_flutter/core/dtos/budget_model.dart';
import 'package:planpal_flutter/core/dtos/user_summary.dart';
import 'package:planpal_flutter/core/repositories/budget_repository.dart';
import 'package:planpal_flutter/core/riverpod/auth_notifier.dart';
import 'package:planpal_flutter/core/riverpod/budget_providers.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/presentation/pages/budget/budget_overview_page.dart';

void main() {
  setUpAll(() async {
    dotenv.testLoad(fileInput: 'CLIENT_ID=test-client');
  });

  final summary = BudgetModel(
    budgetId: 'budget-1',
    planId: 'plan-1',
    currency: 'VND',
    totalBudget: 1000000,
    totalSpent: 450000,
    remainingBudget: 550000,
    spentPercentage: 45,
    nearLimit: false,
    overBudget: false,
    expenseCount: 2,
    breakdown: const [
      BudgetBreakdownItem(
        user: BudgetBreakdownUser(
          id: 'user-1',
          username: 'owner',
          fullName: 'Plan Owner',
        ),
        amount: 250000,
      ),
      BudgetBreakdownItem(
        user: BudgetBreakdownUser(
          id: 'user-2',
          username: 'member',
          fullName: 'Group Member',
        ),
        amount: 200000,
      ),
    ],
    trend: [
      BudgetTrendPoint(date: DateTime(2026, 4, 1), amount: 100000),
      BudgetTrendPoint(date: DateTime(2026, 4, 2), amount: 200000),
      BudgetTrendPoint(date: DateTime(2026, 4, 3), amount: 150000),
    ],
  );

  ExpenseModel buildExpense({
    required String id,
    required double amount,
    required String category,
  }) {
    return ExpenseModel(
      id: id,
      planId: 'plan-1',
      userId: 'user-1',
      user: UserSummary(
        id: 'user-1',
        username: 'owner',
        firstName: 'Plan',
        lastName: 'Owner',
        email: null,
        isOnline: true,
        onlineStatus: 'online',
        avatarUrl: null,
        hasAvatar: false,
        dateJoined: DateTime(2026, 1, 1),
        lastSeen: null,
        fullName: 'Plan Owner',
        initials: 'PO',
      ),
      amount: amount,
      category: category,
      description: 'Expense $id',
      createdAt: DateTime(2026, 4, 5, 10),
      updatedAt: null,
    );
  }

  testWidgets('BudgetOverviewPage renders summary and breakdown', (
    tester,
  ) async {
    final repository = FakeBudgetRepository(
      summary: summary,
      pages: [
        ExpensePageResponse(
          items: [buildExpense(id: 'exp-1', amount: 250000, category: 'Food')],
          nextPageUrl: null,
          count: 1,
          currentPage: 1,
          totalPages: 1,
          pageSize: 20,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authNotifierProvider.overrideWithValue(AuthProvider()),
          budgetRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: BudgetOverviewPage(
            planId: 'plan-1',
            planTitle: 'Da Nang Trip',
            canManageBudget: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Budget Overview'), findsWidgets);
    expect(find.text('Da Nang Trip'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Per-user Breakdown'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Per-user Breakdown'), findsOneWidget);
    expect(find.text('Plan Owner'), findsOneWidget);
    expect(find.text('View expenses'), findsOneWidget);
    expect(find.text('Update budget'), findsOneWidget);
  });

  test('expensesProvider appends the next page', () async {
    final repository = FakeBudgetRepository(
      summary: summary,
      pages: [
        ExpensePageResponse(
          items: [buildExpense(id: 'exp-1', amount: 250000, category: 'Food')],
          nextPageUrl: 'page-2',
          count: 2,
          currentPage: 1,
          totalPages: 2,
          pageSize: 20,
        ),
        ExpensePageResponse(
          items: [buildExpense(id: 'exp-2', amount: 200000, category: 'Taxi')],
          nextPageUrl: null,
          count: 2,
          currentPage: 2,
          totalPages: 2,
          pageSize: 20,
        ),
      ],
    );

    final container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWithValue(AuthProvider()),
        budgetRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final query = const ExpenseListQuery(planId: 'plan-1');
    final initial = await container.read(expensesProvider(query).future);
    expect(initial.items.length, 1);

    await container.read(expensesProvider(query).notifier).loadMore();
    final updated = container.read(expensesProvider(query)).valueOrNull;

    expect(updated, isNotNull);
    expect(updated!.items.length, 2);
    expect(updated.hasMore, isFalse);
    expect(updated.items.last.category, 'Taxi');
  });
}

class FakeBudgetRepository extends BudgetRepository {
  final BudgetModel summary;
  final List<ExpensePageResponse> pages;

  FakeBudgetRepository({required this.summary, this.pages = const []})
    : super(AuthProvider());

  @override
  Future<BudgetModel> getBudget(String planId) async => summary;

  @override
  Future<BudgetModel> updateBudget(
    String planId, {
    required double totalBudget,
    String currency = 'VND',
  }) async {
    return BudgetModel(
      budgetId: summary.budgetId,
      planId: planId,
      currency: currency,
      totalBudget: totalBudget,
      totalSpent: summary.totalSpent,
      remainingBudget: totalBudget - summary.totalSpent,
      spentPercentage: totalBudget <= 0
          ? 0
          : (summary.totalSpent / totalBudget) * 100,
      nearLimit: false,
      overBudget: false,
      expenseCount: summary.expenseCount,
      breakdown: summary.breakdown,
      trend: summary.trend,
    );
  }

  @override
  Future<ExpenseCreateResult> addExpense(
    String planId, {
    required double amount,
    required String category,
    String description = '',
  }) async {
    return ExpenseCreateResult(
      expense: buildFakeExpense(
        id: 'created',
        amount: amount,
        category: category,
      ),
      summary: summary,
      warnings: const [],
    );
  }

  @override
  Future<ExpensePageResponse> getExpenses(
    String planId, {
    ExpenseFilter filter = const ExpenseFilter(),
    String? nextPageUrl,
  }) async {
    if (pages.isEmpty) {
      return ExpensePageResponse(
        items: const [],
        nextPageUrl: null,
        count: 0,
        currentPage: 1,
        totalPages: 0,
        pageSize: filter.pageSize,
      );
    }
    if (nextPageUrl == null || pages.length == 1) {
      return pages.first;
    }
    return pages.last;
  }

  ExpenseModel buildFakeExpense({
    required String id,
    required double amount,
    required String category,
  }) {
    return ExpenseModel(
      id: id,
      planId: 'plan-1',
      userId: 'user-1',
      user: UserSummary(
        id: 'user-1',
        username: 'owner',
        firstName: 'Plan',
        lastName: 'Owner',
        email: null,
        isOnline: true,
        onlineStatus: 'online',
        avatarUrl: null,
        hasAvatar: false,
        dateJoined: DateTime(2026, 1, 1),
        lastSeen: null,
        fullName: 'Plan Owner',
        initials: 'PO',
      ),
      amount: amount,
      category: category,
      description: 'Expense $id',
      createdAt: DateTime(2026, 4, 5, 10),
      updatedAt: null,
    );
  }
}
