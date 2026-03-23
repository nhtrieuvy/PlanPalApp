import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../dtos/plan_summary.dart';
import '../repositories/plan_repository.dart';
import 'repository_providers.dart';

/// Production feed state for lazy loading and infinite scrolling.
class PlansFeedState {
  final List<PlanSummary> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? nextPageUrl;
  final int totalCount;
  final Object? loadMoreError;

  const PlansFeedState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.nextPageUrl,
    this.totalCount = 0,
    this.loadMoreError,
  });

  PlansFeedState copyWith({
    List<PlanSummary>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? nextPageUrl,
    int? totalCount,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
  }) {
    return PlansFeedState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      nextPageUrl: nextPageUrl ?? this.nextPageUrl,
      totalCount: totalCount ?? this.totalCount,
      loadMoreError: clearLoadMoreError
          ? null
          : (loadMoreError ?? this.loadMoreError),
    );
  }
}

class PlansNotifier extends AsyncNotifier<PlansFeedState> {
  late PlanRepository _repo;
  final Set<String> _loadedPageUrls = <String>{};

  bool _isRequestInFlight = false;

  @override
  Future<PlansFeedState> build() async {
    _repo = ref.watch(planRepositoryProvider);
    return loadInitial();
  }

  Future<PlansFeedState> loadInitial() async {
    if (_isRequestInFlight) {
      return state.valueOrNull ?? const PlansFeedState(isLoading: true);
    }

    _isRequestInFlight = true;
    try {
      final response = await _repo.getPlans(limit: 20);
      _loadedPageUrls
        ..clear()
        ..add('FIRST_PAGE');
      return PlansFeedState(
        items: response.plans,
        isLoading: false,
        isLoadingMore: false,
        hasMore: response.hasMore,
        nextPageUrl: response.nextPageUrl,
        totalCount: response.count,
      );
    } finally {
      _isRequestInFlight = false;
    }
  }

  /// Load next page and append only new items.
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
      final response = await _repo.getPlans(nextPageUrl: current.nextPageUrl);

      final existingIds = current.items.map((p) => p.id).toSet();
      final appended = response.plans
          .where((p) => !existingIds.contains(p.id))
          .toList();

      _loadedPageUrls.add(current.nextPageUrl!);

      final merged = <PlanSummary>[...current.items, ...appended];
      state = AsyncData(
        current.copyWith(
          items: merged,
          isLoadingMore: false,
          hasMore: response.hasMore,
          nextPageUrl: response.nextPageUrl,
          totalCount: response.count,
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

  /// Refresh feed from first page while preserving scroll restoration state.
  Future<void> refresh() async {
    state = AsyncData(
      (state.valueOrNull ?? const PlansFeedState()).copyWith(
        isLoading: true,
        clearLoadMoreError: true,
      ),
    );
    state = await AsyncValue.guard(loadInitial);
  }

  /// Triggered by UI when scroll is near bottom for perceived performance.
  Future<void> prefetchNextPage() async {
    await loadMore();
  }

  void addPlan(PlanSummary plan) {
    final current = state.valueOrNull;
    if (current == null) return;
    final merged = [plan, ...current.items.where((p) => p.id != plan.id)];
    state = AsyncData(
      current.copyWith(items: merged, totalCount: current.totalCount + 1),
    );
  }

  void updatePlan(PlanSummary updatedPlan) {
    final current = state.valueOrNull;
    if (current == null) return;
    final items = current.items.map((p) {
      return p.id == updatedPlan.id ? updatedPlan : p;
    }).toList();
    state = AsyncData(current.copyWith(items: items));
  }

  void removePlan(String planId) {
    final current = state.valueOrNull;
    if (current == null) return;
    final nextItems = current.items.where((p) => p.id != planId).toList();
    state = AsyncData(
      current.copyWith(
        items: nextItems,
        totalCount: current.totalCount > 0
            ? current.totalCount - 1
            : current.totalCount,
      ),
    );
  }
}

final plansNotifierProvider =
    AsyncNotifierProvider<PlansNotifier, PlansFeedState>(PlansNotifier.new);

/// Store and restore plans list scroll position across navigation.
final plansFeedScrollOffsetProvider = StateProvider<double>((ref) => 0.0);

/// Convenience provider for just the plans list
final plansListProvider = Provider<List<PlanSummary>>((ref) {
  return ref.watch(plansNotifierProvider).valueOrNull?.items ?? [];
});

/// Recent plans for the home page (first 5)
final recentPlansProvider = Provider<List<PlanSummary>>((ref) {
  final plans = ref.watch(plansListProvider);
  return plans.take(5).toList();
});
