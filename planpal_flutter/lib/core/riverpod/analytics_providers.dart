import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/dtos/analytics_model.dart';
import 'package:planpal_flutter/core/repositories/analytics_repository.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';


final analyticsRangeProvider = StateProvider.autoDispose<AnalyticsRangeOption>(
  (ref) => AnalyticsRangeOption.last30Days,
);

final analyticsChartMetricProvider = StateProvider.autoDispose<AnalyticsMetricKey>(
  (ref) => AnalyticsMetricKey.dau,
);

class AnalyticsSummaryNotifier extends AutoDisposeAsyncNotifier<AnalyticsSummary> {
  late AnalyticsRepository _repo;

  @override
  Future<AnalyticsSummary> build() async {
    _repo = ref.watch(analyticsRepositoryProvider);
    final range = ref.watch(analyticsRangeProvider);
    return _repo.getDashboardSummary(range: range.apiValue);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

class AnalyticsTimeSeriesNotifier
    extends AutoDisposeAsyncNotifier<AnalyticsTimeSeries> {
  late AnalyticsRepository _repo;

  @override
  Future<AnalyticsTimeSeries> build() async {
    _repo = ref.watch(analyticsRepositoryProvider);
    final range = ref.watch(analyticsRangeProvider);
    final metric = ref.watch(analyticsChartMetricProvider);

    return _repo.getTimeSeries(
      metric: metric.apiValue,
      range: range.apiValue,
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

class AnalyticsTopEntitiesNotifier
    extends AutoDisposeAsyncNotifier<AnalyticsTopEntities> {
  late AnalyticsRepository _repo;

  @override
  Future<AnalyticsTopEntities> build() async {
    _repo = ref.watch(analyticsRepositoryProvider);
    final range = ref.watch(analyticsRangeProvider);
    return _repo.getTopEntities(range: range.apiValue, limit: 5);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

final analyticsSummaryProvider =
    AsyncNotifierProvider.autoDispose<AnalyticsSummaryNotifier, AnalyticsSummary>(
      AnalyticsSummaryNotifier.new,
    );

final analyticsTimeSeriesProvider = AsyncNotifierProvider.autoDispose<
  AnalyticsTimeSeriesNotifier,
  AnalyticsTimeSeries
>(AnalyticsTimeSeriesNotifier.new);

final analyticsTopEntitiesProvider = AsyncNotifierProvider.autoDispose<
  AnalyticsTopEntitiesNotifier,
  AnalyticsTopEntities
>(AnalyticsTopEntitiesNotifier.new);
