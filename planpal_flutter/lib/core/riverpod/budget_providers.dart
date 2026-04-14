import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/dtos/budget_model.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';

class BudgetNotifier extends FamilyAsyncNotifier<BudgetModel, String> {
  @override
  Future<BudgetModel> build(String arg) async {
    final repo = ref.watch(budgetRepositoryProvider);
    return repo.getBudget(arg);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build(arg));
  }

  Future<void> updateBudget({
    required double totalBudget,
    String currency = 'VND',
  }) async {
    final repo = ref.read(budgetRepositoryProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () =>
          repo.updateBudget(arg, totalBudget: totalBudget, currency: currency),
    );
  }
}

class ExpenseFeedState {
  final List<ExpenseModel> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? nextPageUrl;
  final Object? loadMoreError;

  const ExpenseFeedState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.nextPageUrl,
    this.loadMoreError,
  });

  ExpenseFeedState copyWith({
    List<ExpenseModel>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? nextPageUrl,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
  }) {
    return ExpenseFeedState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      nextPageUrl: nextPageUrl ?? this.nextPageUrl,
      loadMoreError: clearLoadMoreError
          ? null
          : (loadMoreError ?? this.loadMoreError),
    );
  }
}

class ExpensesNotifier
    extends FamilyAsyncNotifier<ExpenseFeedState, ExpenseListQuery> {
  final Set<String> _loadedPageUrls = <String>{};
  bool _isRequestInFlight = false;

  @override
  Future<ExpenseFeedState> build(ExpenseListQuery arg) async {
    return _loadInitial(arg);
  }

  Future<ExpenseFeedState> _loadInitial(ExpenseListQuery query) async {
    if (_isRequestInFlight) {
      return state.valueOrNull ?? const ExpenseFeedState(isLoading: true);
    }

    _isRequestInFlight = true;
    try {
      final repo = ref.read(budgetRepositoryProvider);
      final page = await repo.getExpenses(query.planId, filter: query.filter);
      _loadedPageUrls
        ..clear()
        ..add('FIRST_PAGE');
      return ExpenseFeedState(
        items: page.items,
        hasMore: page.hasMore,
        nextPageUrl: page.nextPageUrl,
      );
    } finally {
      _isRequestInFlight = false;
    }
  }

  Future<void> refresh() async {
    state = AsyncData(
      (state.valueOrNull ?? const ExpenseFeedState()).copyWith(
        isLoading: true,
        clearLoadMoreError: true,
      ),
    );
    state = await AsyncValue.guard(() => _loadInitial(arg));
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || _isRequestInFlight) return;
    if (current.isLoading || current.isLoadingMore) return;
    if (current.nextPageUrl == null) return;
    if (_loadedPageUrls.contains(current.nextPageUrl)) return;

    state = AsyncData(
      current.copyWith(isLoadingMore: true, clearLoadMoreError: true),
    );

    _isRequestInFlight = true;
    try {
      final repo = ref.read(budgetRepositoryProvider);
      final page = await repo.getExpenses(
        arg.planId,
        filter: arg.filter,
        nextPageUrl: current.nextPageUrl,
      );
      final existingIds = current.items.map((item) => item.id).toSet();
      final appended = page.items
          .where((item) => !existingIds.contains(item.id))
          .toList();
      _loadedPageUrls.add(current.nextPageUrl!);
      state = AsyncData(
        current.copyWith(
          items: [...current.items, ...appended],
          isLoadingMore: false,
          hasMore: page.hasMore,
          nextPageUrl: page.nextPageUrl,
          clearLoadMoreError: true,
        ),
      );
    } catch (error) {
      state = AsyncData(
        current.copyWith(isLoadingMore: false, loadMoreError: error),
      );
    } finally {
      _isRequestInFlight = false;
    }
  }
}

final budgetProvider =
    AsyncNotifierProvider.family<BudgetNotifier, BudgetModel, String>(
      BudgetNotifier.new,
    );

final expensesProvider =
    AsyncNotifierProvider.family<
      ExpensesNotifier,
      ExpenseFeedState,
      ExpenseListQuery
    >(ExpensesNotifier.new);
