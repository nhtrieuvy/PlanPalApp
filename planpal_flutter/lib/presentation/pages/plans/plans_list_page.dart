import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planpal_flutter/core/dtos/plan_summary.dart';
import 'package:planpal_flutter/core/localization/app_formatters.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/plans_notifier.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:planpal_flutter/core/theme/app_design_tokens.dart';
import 'package:planpal_flutter/presentation/pages/users/plan_form_page.dart';
import 'package:planpal_flutter/presentation/widgets/design_system/journey_ui.dart';
import 'package:planpal_flutter/presentation/widgets/layout/responsive_content.dart';

import '../../widgets/common/refreshable_page_wrapper.dart';
import '../../../shared/ui_states/ui_states.dart';

class PlansListPage extends ConsumerStatefulWidget {
  final String? groupId;
  final String? groupName;
  final bool showGroupPlansOnly;

  const PlansListPage({
    super.key,
    this.groupId,
    this.groupName,
    this.showGroupPlansOnly = false,
  });

  @override
  ConsumerState<PlansListPage> createState() => _PlansListPageState();
}

class _PlansListPageState extends ConsumerState<PlansListPage>
    with SingleTickerProviderStateMixin, RefreshablePage<PlansListPage> {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  static const double _prefetchThreshold = 0.7;

  String _currentFilter = 'all';
  String? _selectedPlanId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: widget.showGroupPlansOnly ? 1 : 3,
      vsync: this,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final savedOffset = ref.read(plansFeedScrollOffsetProvider);
      final maxScroll = _scrollController.position.maxScrollExtent;
      final target = savedOffset.clamp(0.0, maxScroll);
      _scrollController.jumpTo(target);
    });
    _setupScrollListener();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Future<void> onRefresh() async {
    await ref.read(plansNotifierProvider.notifier).refresh();
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      ref.read(plansFeedScrollOffsetProvider.notifier).state = position.pixels;

      if (position.maxScrollExtent <= 0) return;
      final ratio = position.pixels / position.maxScrollExtent;
      if (ratio >= _prefetchThreshold) {
        ref.read(plansNotifierProvider.notifier).prefetchNextPage();
      }
    });
  }

  void _onTabChanged(int index) {
    setState(() {
      _currentFilter = ['all', 'personal', 'group'][index];
    });
  }

  List<PlanSummary> _filterPlans(List<PlanSummary> plans) {
    if (widget.showGroupPlansOnly) {
      return plans.where((plan) => plan.planType == 'group').toList();
    }
    if (_currentFilter == 'all') {
      return plans;
    }
    return plans.where((plan) => plan.planType == _currentFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.showGroupPlansOnly && widget.groupName != null
              ? l10n.t(
                  'plans.group_title',
                  params: {'group': widget.groupName!},
                )
              : l10n.t('plans.title'),
        ),
        bottom: widget.showGroupPlansOnly
            ? null
            : TabBar(
                controller: _tabController,
                onTap: _onTabChanged,
                tabs: [
                  Tab(
                    icon: const Icon(Icons.all_inclusive),
                    text: l10n.t('common.all'),
                  ),
                  Tab(
                    icon: const Icon(Icons.person),
                    text: l10n.t('plan.personal_plan'),
                  ),
                  Tab(
                    icon: const Icon(Icons.group),
                    text: l10n.t('plan.group_plan'),
                  ),
                ],
              ),
      ),
      body: _buildBody(context),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreatePlanDialog,
        tooltip: l10n.t('plans.create_tooltip'),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l10n = context.l10n;
    final plansAsync = ref.watch(plansNotifierProvider);

    return plansAsync.when(
      loading: () => const AppSkeleton.list(itemCount: 6),
      error: (error, _) => AppError(
        message: ErrorDisplayService.getUserFriendlyMessage(error),
        onRetry: () => ref.refresh(plansNotifierProvider),
        retryLabel: l10n.t('common.retry'),
      ),
      data: (plansState) {
        final filteredPlans = _filterPlans(plansState.items);
        final isFirstPageEmpty = plansState.items.isEmpty;

        if (filteredPlans.isEmpty && isFirstPageEmpty) {
          return _buildEmptyState(context);
        }

        return RefreshablePageWrapper(
          onRefresh: onRefresh,
          child: ResponsiveContent(
            mediumMaxWidth: 820,
            expandedMaxWidth: 1280,
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 960 && filteredPlans.isNotEmpty) {
                  return _buildDesktopLayout(
                    context,
                    filteredPlans,
                    plansState,
                  );
                }
                return ListView.builder(
                  key: const PageStorageKey<String>('plans_feed_list'),
                  controller: _scrollController,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: filteredPlans.length + 1,
                  itemBuilder: (context, index) {
                    if (index == filteredPlans.length) {
                      return _buildPaginationFooter(context, plansState);
                    }
                    return _buildPlanCard(context, filteredPlans[index]);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildPaginationFooter(BuildContext context, PlansFeedState state) {
    final l10n = context.l10n;

    if (state.isLoadingMore) {
      return AppLoading(
        inline: true,
        message: l10n.t('plans.loading_more'),
        padding: const EdgeInsets.symmetric(vertical: 20),
      );
    }

    if (state.loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Column(
            children: [
              Text(
                l10n.t('plans.load_more_error'),
                style: const TextStyle(color: AppColors.error),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () =>
                    ref.read(plansNotifierProvider.notifier).loadMore(),
                child: Text(l10n.t('common.retry')),
              ),
            ],
          ),
        ),
      );
    }

    if (!state.hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(child: Text(l10n.t('plans.all_loaded'))),
      );
    }

    return const SizedBox(height: 40);
  }

  Widget _buildEmptyState(BuildContext context) {
    final l10n = context.l10n;
    return AppEmpty(
      icon: Icons.event_note,
      title: l10n.t('plans.empty_title'),
      description: widget.showGroupPlansOnly
          ? l10n.t('plans.empty_group_description')
          : _emptyMessage(context),
      actionLabel: l10n.t('plans.create_tooltip'),
      onAction: _showCreatePlanDialog,
    );
  }

  String _emptyMessage(BuildContext context) {
    final l10n = context.l10n;
    switch (_currentFilter) {
      case 'personal':
        return l10n.t('plans.empty_personal');
      case 'group':
        return l10n.t('plans.empty_group');
      default:
        return l10n.t('plans.empty_default');
    }
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    List<PlanSummary> plans,
    PlansFeedState state,
  ) {
    final selected = plans.firstWhere(
      (plan) => plan.id == _selectedPlanId,
      orElse: () => plans.first,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 360,
          child: ListView.builder(
            key: const PageStorageKey<String>('plans_feed_desktop_list'),
            controller: _scrollController,
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: plans.length + 1,
            itemBuilder: (context, index) {
              if (index == plans.length) {
                return _buildPaginationFooter(context, state);
              }
              final plan = plans[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: JourneySurface(
                  selected: selected.id == plan.id,
                  onTap: () => setState(() => _selectedPlanId = plan.id),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _dateRange(context, plan).isEmpty
                            ? context.l10n.t('plan.no_date')
                            : _dateRange(context, plan),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      JourneyRouteProgress(
                        completedStops: _journeyStage(plan),
                        color: _getStatusColor(plan.status),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        VerticalDivider(
          width: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: _buildTripPreview(context, selected),
          ),
        ),
      ],
    );
  }

  Widget _buildTripPreview(BuildContext context, PlanSummary plan) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final statusColor = _getStatusColor(plan.status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sheet),
          child: ColoredBox(
            color: colors.primary,
            child: JourneyPathBackdrop(
              color: colors.onPrimary,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.planTypeLabel(plan.planType).toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onPrimary.withValues(alpha: .75),
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      plan.title,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: colors.onPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (plan.groupName?.isNotEmpty == true) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        plan.groupName!,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colors.onPrimary.withValues(alpha: .82),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xxl),
                    JourneyRouteProgress(
                      completedStops: _journeyStage(plan),
                      color: colors.onPrimary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: _PreviewMetric(
                icon: Icons.calendar_month_outlined,
                label: _dateRange(context, plan).isEmpty
                    ? context.l10n.t('plan.no_date')
                    : _dateRange(context, plan),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _PreviewMetric(
                icon: Icons.route_outlined,
                label: context.l10n.activityCountLabel(plan.activitiesCount),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _PreviewMetric(
                icon: Icons.schedule_outlined,
                label: context.l10n.durationDaysLabel(plan.durationDays),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              context.l10n.planStatusLabel(plan.status),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => _openPlan(plan),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(context.l10n.t('home.continue_planning')),
            ),
          ],
        ),
      ],
    );
  }

  int _journeyStage(PlanSummary plan) {
    if (plan.isCompleted) return 3;
    if (plan.isOngoing) return 2;
    if (plan.isUpcoming) return 1;
    return 0;
  }

  Future<void> _openPlan(PlanSummary plan) async {
    final result = await context.push<Map<String, dynamic>>(
      '/plans/${plan.id}',
    );
    if (result == null) return;
    if (result['action'] == 'delete' && result['id'] == plan.id) {
      ref.read(plansNotifierProvider.notifier).removePlan(plan.id);
      return;
    }
    if ((result['action'] == 'updated' || result['action'] == 'edit') &&
        result['plan'] is Map) {
      try {
        final updated = PlanSummary.fromJson(
          Map<String, dynamic>.from(result['plan'] as Map),
        );
        ref.read(plansNotifierProvider.notifier).updatePlan(updated);
      } catch (_) {}
    }
  }

  Widget _buildPlanCard(BuildContext context, PlanSummary plan) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final statusColor = _getStatusColor(plan.status);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: JourneySurface(
        onTap: () => _openPlan(plan),
        semanticLabel: plan.title,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        plan.groupName?.isNotEmpty == true
                            ? plan.groupName!
                            : l10n.planTypeLabel(plan.planType),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(AppRadius.small),
                  ),
                  child: Text(
                    l10n.planStatusLabel(plan.status),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            JourneyRouteProgress(
              completedStops: _journeyStage(plan),
              color: statusColor,
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: [
                _TripMetadata(
                  icon: Icons.calendar_month_outlined,
                  label: _dateRange(context, plan).isEmpty
                      ? l10n.t('plan.no_date')
                      : _dateRange(context, plan),
                ),
                _TripMetadata(
                  icon: Icons.route_outlined,
                  label: l10n.activityCountLabel(plan.activitiesCount),
                ),
                _TripMetadata(
                  icon: Icons.schedule_outlined,
                  label: l10n.durationDaysLabel(plan.durationDays),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _dateRange(BuildContext context, PlanSummary plan) {
    if (plan.startDate != null && plan.endDate != null) {
      final start = AppFormatters.shortDate(context, plan.startDate!);
      final end = AppFormatters.shortDate(context, plan.endDate!);
      return '$start - $end';
    }
    if (plan.startDate != null) {
      return AppFormatters.shortDate(context, plan.startDate!);
    }
    return '';
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'draft':
        return AppColors.neutral500;
      case 'active':
      case 'ongoing':
        return AppColors.success;
      case 'completed':
        return AppColors.info;
      case 'cancelled':
        return AppColors.error;
      case 'upcoming':
        return AppColors.warning;
      default:
        return AppColors.neutral500;
    }
  }

  Future<void> _showCreatePlanDialog() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const PlanFormPage()),
    );

    if (!mounted || result == null) return;
    if (result['action'] == 'created' && result['plan'] is Map) {
      try {
        final summary = PlanSummary.fromJson(
          Map<String, dynamic>.from(result['plan'] as Map),
        );
        ref.read(plansNotifierProvider.notifier).addPlan(summary);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.t('plans.created_success'))),
        );
      } catch (_) {}
    }
  }
}

class _PreviewMetric extends StatelessWidget {
  const _PreviewMetric({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colors.primary),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _TripMetadata extends StatelessWidget {
  const _TripMetadata({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: colors.onSurfaceVariant),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}
