import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/dtos/analytics_model.dart';
import 'package:planpal_flutter/core/riverpod/auth_notifier.dart';
import 'package:planpal_flutter/core/riverpod/analytics_providers.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:planpal_flutter/presentation/widgets/analytics/analytics_kpi_card.dart';
import 'package:planpal_flutter/presentation/widgets/analytics/analytics_time_series_chart.dart';
import 'package:planpal_flutter/presentation/widgets/analytics/analytics_top_entities_card.dart';
import 'package:planpal_flutter/presentation/widgets/common/refreshable_page_wrapper.dart';
import 'package:planpal_flutter/shared/ui_states/ui_states.dart';

class AnalyticsDashboardPage extends ConsumerStatefulWidget {
  const AnalyticsDashboardPage({super.key});

  @override
  ConsumerState<AnalyticsDashboardPage> createState() =>
      _AnalyticsDashboardPageState();
}

class _AnalyticsDashboardPageState
    extends ConsumerState<AnalyticsDashboardPage> {
  Future<void> _refresh() async {
    await Future.wait([
      ref.read(analyticsSummaryProvider.notifier).refresh(),
      ref.read(analyticsTimeSeriesProvider.notifier).refresh(),
      ref.read(analyticsTopEntitiesProvider.notifier).refresh(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authNotifierProvider);
    final currentUser = auth.user;
    if (currentUser == null || !currentUser.isStaff) {
      return Scaffold(
        appBar: AppBar(title: const Text('Analytics Dashboard')),
        body: const Center(
          child: AppEmpty(
            icon: Icons.lock_outline,
            title: 'Analytics unavailable',
            description: 'This dashboard is only available to staff accounts.',
          ),
        ),
      );
    }

    final range = ref.watch(analyticsRangeProvider);
    final selectedMetric = ref.watch(analyticsChartMetricProvider);
    final summaryAsync = ref.watch(analyticsSummaryProvider);
    final timeSeriesAsync = ref.watch(analyticsTimeSeriesProvider);
    final topEntitiesAsync = ref.watch(analyticsTopEntitiesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics Dashboard')),
      body: RefreshablePageWrapper(
        onRefresh: _refresh,
        child: summaryAsync.when(
          loading: () => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: const [
              AppSkeleton.list(itemCount: 5),
            ],
          ),
          error: (error, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              AppError(
                message: ErrorDisplayService.getUserFriendlyMessage(error),
                onRetry: _refresh,
                retryLabel: 'Retry',
              ),
            ],
          ),
          data: (summary) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _buildHero(summary),
              const SizedBox(height: 20),
              _buildRangeSelector(range),
              const SizedBox(height: 20),
              _buildKpiGrid(summary),
              const SizedBox(height: 20),
              _buildTrendSection(selectedMetric, timeSeriesAsync),
              const SizedBox(height: 20),
              _buildTotalsCard(summary),
              const SizedBox(height: 20),
              _buildTopEntitiesSection(topEntitiesAsync),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero(AnalyticsSummary summary) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0F4C81),
            Color(0xFF2B7A78),
            Color(0xFF7EC8E3),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Product Pulse',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Usage and engagement trends',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Latest aggregated day: ${summary.currentDate.month}/${summary.currentDate.day}/${summary.currentDate.year}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRangeSelector(AnalyticsRangeOption selectedRange) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: AnalyticsRangeOption.values.map((range) {
          final isSelected = selectedRange == range;
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: ChoiceChip(
              label: Text(range.label),
              selected: isSelected,
              onSelected: (_) => ref.read(analyticsRangeProvider.notifier).state = range,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildKpiGrid(AnalyticsSummary summary) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      childAspectRatio: 1.0,
      children: [
        AnalyticsKpiCard(metric: summary.dau, accentColor: AppColors.info),
        AnalyticsKpiCard(metric: summary.mau, accentColor: AppColors.secondary),
        AnalyticsKpiCard(
          metric: summary.planCreationRate,
          accentColor: AppColors.success,
          percentage: true,
        ),
        AnalyticsKpiCard(
          metric: summary.planCompletionRate,
          accentColor: AppColors.warning,
          percentage: true,
        ),
        AnalyticsKpiCard(
          metric: summary.groupJoinRate,
          accentColor: AppColors.primary,
          percentage: true,
        ),
        AnalyticsKpiCard(
          metric: summary.notificationOpenRate,
          accentColor: AppColors.error,
          percentage: true,
        ),
      ],
    );
  }

  Widget _buildTrendSection(
    AnalyticsMetricKey selectedMetric,
    AsyncValue<AnalyticsTimeSeries> timeSeriesAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Trend View',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: AnalyticsMetricKey.values.map((metric) {
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: ChoiceChip(
                  label: Text(metric.label),
                  selected: selectedMetric == metric,
                  onSelected: (_) =>
                      ref.read(analyticsChartMetricProvider.notifier).state = metric,
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),
        timeSeriesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => AppError(
            message: ErrorDisplayService.getUserFriendlyMessage(error),
            onRetry: () => ref.read(analyticsTimeSeriesProvider.notifier).refresh(),
            retryLabel: 'Retry',
          ),
          data: (series) {
            if (series.points.isEmpty) {
              return const AppEmpty(
                icon: Icons.show_chart,
                title: 'No analytics data',
                description: 'No trend data is available for this metric yet.',
              );
            }
            return AnalyticsTimeSeriesChart(
              title: selectedMetric.label,
              series: series,
              color: _metricColor(selectedMetric),
              percentage: selectedMetric.isPercentage,
            );
          },
        ),
      ],
    );
  }

  Widget _buildTotalsCard(AnalyticsSummary summary) {
    final rows = [
      ('Plans created', '${summary.totals.plansCreated}'),
      ('Plans completed', '${summary.totals.plansCompleted}'),
      ('Group joins', '${summary.totals.groupJoins}'),
      ('Notifications sent', '${summary.totals.notificationsSent}'),
      ('Notifications opened', '${summary.totals.notificationsOpened}'),
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Range Totals',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 14),
          for (var index = 0; index < rows.length; index += 1)
            Padding(
              padding: EdgeInsets.only(bottom: index == rows.length - 1 ? 0 : 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      rows[index].$1,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  Text(
                    rows[index].$2,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopEntitiesSection(AsyncValue<AnalyticsTopEntities> topEntitiesAsync) {
    return topEntitiesAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => AppError(
        message: ErrorDisplayService.getUserFriendlyMessage(error),
        onRetry: () => ref.read(analyticsTopEntitiesProvider.notifier).refresh(),
        retryLabel: 'Retry',
      ),
      data: (snapshot) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Top Entities',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 14),
          AnalyticsTopEntitiesCard(
            title: 'Top Plans',
            entities: snapshot.plans,
            accentColor: AppColors.primary,
          ),
          const SizedBox(height: 16),
          AnalyticsTopEntitiesCard(
            title: 'Top Groups',
            entities: snapshot.groups,
            accentColor: AppColors.secondary,
          ),
        ],
      ),
    );
  }

  Color _metricColor(AnalyticsMetricKey metric) {
    switch (metric) {
      case AnalyticsMetricKey.dau:
        return AppColors.primary;
      case AnalyticsMetricKey.mau:
        return AppColors.secondary;
      case AnalyticsMetricKey.planCreationRate:
        return AppColors.success;
      case AnalyticsMetricKey.planCompletionRate:
        return AppColors.warning;
      case AnalyticsMetricKey.groupJoinRate:
        return AppColors.primary;
      case AnalyticsMetricKey.notificationOpenRate:
        return AppColors.error;
    }
  }
}
