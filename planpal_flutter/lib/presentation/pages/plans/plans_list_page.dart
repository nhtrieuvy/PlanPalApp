import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/dtos/plan_summary.dart';
import 'package:planpal_flutter/core/localization/app_formatters.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/plans_notifier.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/presentation/pages/users/plan_details_page.dart';
import 'package:planpal_flutter/presentation/pages/users/plan_form_page.dart';

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
          child: ListView.builder(
            key: const PageStorageKey<String>('plans_feed_list'),
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: filteredPlans.length + 1,
            itemBuilder: (context, index) {
              if (index == filteredPlans.length) {
                return _buildPaginationFooter(context, plansState);
              }
              return _buildPlanCard(context, filteredPlans[index]);
            },
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
                style: TextStyle(color: Colors.red[600]),
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

  Widget _buildPlanCard(BuildContext context, PlanSummary plan) {
    final l10n = context.l10n;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: InkWell(
        onTap: () async {
          final result = await Navigator.of(context).push<Map<String, dynamic>>(
            MaterialPageRoute(builder: (_) => PlanDetailsPage(id: plan.id)),
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
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      plan.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getPlanTypeColor(plan.planType).withValues(
                        alpha: 0.1,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      l10n.planTypeLabel(plan.planType),
                      style: TextStyle(
                        fontSize: 12,
                        color: _getPlanTypeColor(plan.planType),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_dateRange(context, plan).isNotEmpty) ...[
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _dateRange(context, plan),
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                    const SizedBox(width: 16),
                    Icon(Icons.timer, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      l10n.activityCountLabel(plan.activitiesCount),
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  _buildStatChip(
                    Icons.event,
                    l10n.activityCountLabel(plan.activitiesCount),
                    Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  _buildStatChip(
                    Icons.schedule,
                    context.l10n.durationDaysLabel(plan.durationDays),
                    Colors.green,
                  ),
                ],
              ),
              if (plan.planType == 'group') ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.group, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      l10n.t('plan.group_plan'),
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor(plan.status).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      l10n.planStatusLabel(plan.status),
                      style: TextStyle(
                        fontSize: 12,
                        color: _getStatusColor(plan.status),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ],
          ),
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

  Widget _buildStatChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Color _getPlanTypeColor(String planType) {
    switch (planType) {
      case 'personal':
        return Colors.blue;
      case 'group':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'draft':
        return Colors.grey;
      case 'active':
      case 'ongoing':
        return Colors.green;
      case 'completed':
        return Colors.blue;
      case 'cancelled':
        return Colors.red;
      case 'upcoming':
        return Colors.orange;
      default:
        return Colors.grey;
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
