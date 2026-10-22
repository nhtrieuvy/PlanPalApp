import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cross_file/cross_file.dart';
import 'package:planpal_flutter/core/auth/auth_session.dart';
import 'package:planpal_flutter/core/dtos/budget_model.dart';
import 'package:planpal_flutter/core/dtos/plan_model.dart';
import 'package:planpal_flutter/core/dtos/user_summary.dart';
import 'package:planpal_flutter/core/repositories/budget_repository.dart';
import 'package:planpal_flutter/core/repositories/plan_repository.dart';
import 'package:planpal_flutter/core/riverpod/auth_notifier.dart';
import 'package:planpal_flutter/core/riverpod/budget_providers.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/presentation/pages/budget/budget_overview_page.dart';
import 'package:planpal_flutter/presentation/pages/budget/balances_page.dart';
import 'package:planpal_flutter/presentation/pages/budget/expense_detail_page.dart';
import 'package:planpal_flutter/presentation/widgets/forms/app_select_field.dart';
import 'test_app.dart';

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
    List<ExpenseParticipantModel> participants = const [],
    List<ExpensePaymentModel> payments = const [],
  }) {
    final user = UserSummary(
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
    );
    return ExpenseModel(
      id: id,
      planId: 'plan-1',
      userId: 'user-1',
      user: user,
      paidByUserId: 'user-1',
      paidByUser: user,
      amount: amount,
      currency: 'VND',
      category: category,
      description: 'Expense $id',
      paymentNote: '',
      receiptUrl: null,
      splitStrategy: 'equal',
      entryType: 'original',
      correctsExpenseId: null,
      correctionReason: '',
      recurrenceId: null,
      occurrenceAt: null,
      participants: participants,
      payments: payments,
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
          authNotifierProvider.overrideWith((ref) => AuthProvider()),
          budgetRepositoryProvider.overrideWithValue(repository),
        ],
        child: buildLocalizedTestApp(
          const BudgetOverviewPage(
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
      find.text('Per-user breakdown'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Per-user breakdown'), findsOneWidget);
    expect(find.text('Plan Owner'), findsOneWidget);
    expect(find.text('Add expense'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Manage'));
    await tester.pumpAndSettle();
    expect(find.text('View expenses'), findsOneWidget);
    expect(find.text('Update budget'), findsOneWidget);
  });

  testWidgets('Expense detail keeps correction actions visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: buildLocalizedTestApp(
          ExpenseDetailPage(
            expense: buildExpense(
              id: 'exp-visible-actions',
              amount: 60000,
              category: 'Food',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Correct expense'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Edit participants'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Edit participants'), findsOneWidget);
  });

  testWidgets('expense correction submits the selected payer', (tester) async {
    final member = UserSummary.fromJson(const {
      'id': 'user-2',
      'username': 'member',
      'full_name': 'Group Member',
      'initials': 'GM',
    });
    final expense = buildExpense(
      id: 'exp-payer',
      amount: 60000,
      category: 'Food',
      participants: [
        ExpenseParticipantModel(
          id: 'participant-2',
          expenseId: 'exp-payer',
          userId: member.id,
          user: member,
          owedAmount: 60000,
          settledAmount: 0,
          balance: -60000,
        ),
      ],
    );
    final repository = FakeBudgetRepository(summary: summary);
    final auth = AuthProvider();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          budgetRepositoryProvider.overrideWithValue(repository),
          planRepositoryProvider.overrideWithValue(
            _UnavailablePlanRepository(auth),
          ),
        ],
        child: buildLocalizedTestApp(ExpenseDetailPage(expense: expense)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Correct expense'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AppSelectField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Group Member').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, 'Member paid');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repository.correctedPaidByUserId, 'user-2');
    expect(repository.correctedPayments, isNull);
  });

  testWidgets('expense correction keeps multiple payer contributions', (
    tester,
  ) async {
    final owner = UserSummary.fromJson(const {
      'id': 'user-1',
      'username': 'owner',
      'full_name': 'Plan Owner',
    });
    final member = UserSummary.fromJson(const {
      'id': 'user-2',
      'username': 'member',
      'full_name': 'Group Member',
    });
    final expense = buildExpense(
      id: 'exp-shared',
      amount: 60000,
      category: 'Food',
      payments: [
        ExpensePaymentModel(
          id: 'payment-1',
          expenseId: 'exp-shared',
          userId: owner.id,
          user: owner,
          amount: 30000,
          createdAt: DateTime(2026, 4, 5),
        ),
        ExpensePaymentModel(
          id: 'payment-2',
          expenseId: 'exp-shared',
          userId: member.id,
          user: member,
          amount: 30000,
          createdAt: DateTime(2026, 4, 5),
        ),
      ],
    );
    final repository = FakeBudgetRepository(summary: summary);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          budgetRepositoryProvider.overrideWithValue(repository),
          planRepositoryProvider.overrideWithValue(
            _UnavailablePlanRepository(AuthProvider()),
          ),
        ],
        child: buildLocalizedTestApp(ExpenseDetailPage(expense: expense)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Correct expense'));
    await tester.pumpAndSettle();
    expect(find.text('More than one person paid'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Plan Owner'),
      '20000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Group Member'),
      '40000',
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, 'Both paid');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repository.correctedPaidByUserId, isNull);
    expect(repository.correctedPayments?.length, 2);
    expect(repository.correctedPayments?.map((item) => item.userId).toSet(), {
      'user-1',
      'user-2',
    });
    expect(repository.correctedPayments?.map((item) => item.amount).toList(), [
      20000,
      40000,
    ]);
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
        authNotifierProvider.overrideWith((ref) => AuthProvider()),
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

  testWidgets('BalancesPage shows the cumulative plan ledger', (tester) async {
    const balances = BalanceSummaryModel(
      planId: 'plan-1',
      currency: 'VND',
      totalExpenses: 1000000,
      balances: [
        UserBalanceModel(
          user: BalanceUser(
            id: 'user-1',
            username: 'owner',
            fullName: 'Plan Owner',
          ),
          totalPaid: 600000,
          totalOwed: 500000,
          settlementPaid: 0,
          settlementReceived: 0,
          netBalance: 100000,
        ),
        UserBalanceModel(
          user: BalanceUser(
            id: 'user-2',
            username: 'member',
            fullName: 'Group Member',
          ),
          totalPaid: 400000,
          totalOwed: 500000,
          settlementPaid: 0,
          settlementReceived: 0,
          netBalance: -100000,
        ),
      ],
      settlementSuggestions: [
        DebtSuggestionModel(
          fromUser: BalanceUser(
            id: 'user-2',
            username: 'member',
            fullName: 'Group Member',
          ),
          toUser: BalanceUser(
            id: 'user-1',
            username: 'owner',
            fullName: 'Plan Owner',
          ),
          amount: 100000,
        ),
      ],
    );
    final repository = FakeBudgetRepository(
      summary: summary,
      balanceSummary: balances,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith((ref) => AuthProvider()),
          budgetRepositoryProvider.overrideWithValue(repository),
        ],
        child: buildLocalizedTestApp(
          const BalancesPage(planId: 'plan-1', planTitle: 'Da Nang Trip'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Plan balances'), findsOneWidget);
    expect(find.text('Total to receive'), findsOneWidget);
    expect(find.text('Total to pay'), findsOneWidget);
    expect(find.text('Plan Owner'), findsWidgets);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Group Member'), findsWidgets);
  });
}

class FakeBudgetRepository extends BudgetRepository {
  final BudgetModel summary;
  final List<ExpensePageResponse> pages;
  final BalanceSummaryModel? balanceSummary;
  String? correctedPaidByUserId;
  List<ExpensePaymentInput>? correctedPayments;

  FakeBudgetRepository({
    required this.summary,
    this.pages = const [],
    this.balanceSummary,
  }) : super(AuthProvider());

  @override
  Future<ExpenseCreateResult> correctExpense(
    String planId,
    String expenseId, {
    required double amount,
    required String category,
    required String reason,
    String description = '',
    String paymentNote = '',
    XFile? receiptFile,
    String? paidByUserId,
    List<ExpensePaymentInput>? payments,
    String? splitStrategy,
    List<ExpenseParticipantInput>? participants,
  }) async {
    correctedPaidByUserId = paidByUserId;
    correctedPayments = payments;
    return ExpenseCreateResult(
      expense: buildFakeExpense(
        id: 'corrected',
        amount: amount,
        category: category,
      ),
      summary: summary,
      warnings: const [],
    );
  }

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
    String? paidByUserId,
    String currency = 'VND',
    String splitStrategy = 'equal',
    List<ExpenseParticipantInput> participants = const [],
    List<ExpensePaymentInput> payments = const [],
    String paymentNote = '',
    XFile? receiptFile,
    RecurrenceInput? recurrence,
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
  Future<BalanceSummaryModel> getBalances(String planId) async {
    return balanceSummary ??
        const BalanceSummaryModel(
          planId: 'plan-1',
          currency: 'VND',
          totalExpenses: 0,
          balances: [],
          settlementSuggestions: [],
        );
  }

  @override
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
    const fromUser = BalanceUser(
      id: 'user-1',
      username: 'payer',
      fullName: 'Payer',
    );
    const toUser = BalanceUser(
      id: 'user-2',
      username: 'receiver',
      fullName: 'Receiver',
    );
    return SettlementModel(
      id: 'settlement-1',
      planId: planId,
      fromUserId: fromUserId,
      toUserId: toUserId,
      fromUser: fromUser,
      toUser: toUser,
      amount: amount,
      currency: currency,
      status: 'pending',
      note: note,
      paymentNote: paymentNote,
      receiptUrl: null,
      requestedByUserId: fromUserId,
      rejectionReason: '',
      settledAt: DateTime(2026, 4, 5),
      respondedAt: null,
      createdAt: DateTime(2026, 4, 5),
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
    final user = UserSummary(
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
    );
    return ExpenseModel(
      id: id,
      planId: 'plan-1',
      userId: 'user-1',
      user: user,
      paidByUserId: 'user-1',
      paidByUser: user,
      amount: amount,
      currency: 'VND',
      category: category,
      description: 'Expense $id',
      paymentNote: '',
      receiptUrl: null,
      splitStrategy: 'equal',
      entryType: 'original',
      correctsExpenseId: null,
      correctionReason: '',
      recurrenceId: null,
      occurrenceAt: null,
      participants: const [],
      payments: const [],
      createdAt: DateTime(2026, 4, 5, 10),
      updatedAt: null,
    );
  }
}

class _UnavailablePlanRepository extends PlanRepository {
  _UnavailablePlanRepository(super.auth);

  @override
  Future<PlanModel> getPlanDetail(String id) async =>
      throw StateError('Plan detail is unavailable in this widget test');
}
