import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/dtos/plan_summary.dart';
import '../../../core/riverpod/plans_notifier.dart';
import '../../widgets/common/refreshable_page_wrapper.dart';
import 'package:planpal_flutter/presentation/pages/users/plan_details_page.dart';
import 'package:planpal_flutter/presentation/pages/users/plan_form_page.dart';
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

  String _currentFilter = 'all'; // 'all', 'personal', 'group'

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
        // Near-bottom prefetch to improve perceived latency.
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
      return plans.where((p) => p.planType == 'group').toList();
    }
    if (_currentFilter == 'all') return plans;
    return plans.where((p) => p.planType == _currentFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.showGroupPlansOnly && widget.groupName != null
              ? '${widget.groupName} - Kế hoạch'
              : 'Kế hoạch của bạn',
        ),
        bottom: widget.showGroupPlansOnly
            ? null
            : TabBar(
                controller: _tabController,
                onTap: _onTabChanged,
                tabs: const [
                  Tab(icon: Icon(Icons.all_inclusive), text: 'Tất cả'),
                  Tab(icon: Icon(Icons.person), text: 'Cá nhân'),
                  Tab(icon: Icon(Icons.group), text: 'Nhóm'),
                ],
              ),
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreatePlanDialog(),
        tooltip: 'Tạo kế hoạch mới',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    final plansAsync = ref.watch(plansNotifierProvider);

    return plansAsync.when(
      loading: () => const AppSkeleton.list(itemCount: 6),
      error: (error, _) => AppError(
        message: error.toString(),
        onRetry: () => ref.refresh(plansNotifierProvider),
        retryLabel: 'Thử lại',
      ),
      data: (plansState) {
        final filteredPlans = _filterPlans(plansState.items);
        final isFirstPageEmpty = plansState.items.isEmpty;

        if (filteredPlans.isEmpty && isFirstPageEmpty) {
          return _buildEmptyState();
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
                return _buildPaginationFooter(plansState);
              }
              final plan = filteredPlans[index];
              return _buildPlanCard(plan);
            },
          ),
        );
      },
    );
  }

  Widget _buildPaginationFooter(PlansFeedState state) {
    if (state.isLoadingMore) {
      return const AppLoading(
        inline: true,
        message: 'Đang tải thêm',
        padding: EdgeInsets.symmetric(vertical: 20),
      );
    }

    if (state.loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Column(
            children: [
              Text(
                'Không tải được trang tiếp theo',
                style: TextStyle(color: Colors.red[600]),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () =>
                    ref.read(plansNotifierProvider.notifier).loadMore(),
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }

    if (!state.hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: Text('Đã hiển thị tất cả kế hoạch')),
      );
    }

    return const SizedBox(height: 40);
  }

  Widget _buildEmptyState() {
    return AppEmpty(
      icon: Icons.event_note,
      title: 'Chưa có kế hoạch nào',
      description: widget.showGroupPlansOnly
          ? 'Nhóm này chưa có kế hoạch nào'
          : _getEmptyMessage(),
      actionLabel: 'Tạo kế hoạch mới',
      onAction: () => _showCreatePlanDialog(),
    );
  }

  String _getEmptyMessage() {
    switch (_currentFilter) {
      case 'personal':
        return 'Chưa có kế hoạch cá nhân nào';
      case 'group':
        return 'Chưa có kế hoạch nhóm nào';
      default:
        return 'Tạo kế hoạch đầu tiên của bạn';
    }
  }

  Widget _buildPlanCard(PlanSummary plan) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: InkWell(
        onTap: () async {
          // Navigate to plan details page. Details page contains schedule
          // button and edit/delete actions; reflect returned changes in
          // provider (clean separation of concerns).
          // debug: log plan id before navigation
          // ignore: avoid_print
          print('Navigating to PlanDetailsPage with id=${plan.id}');
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
            } catch (_) {
              // ignore malformed return
            }
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
                      color: _getPlanTypeColor(
                        plan.planType,
                      ).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _getPlanTypeName(plan.planType),
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

              // Date range
              if (plan.dateRange.isNotEmpty) ...[
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      plan.dateRange,
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                    const SizedBox(width: 16),
                    Icon(Icons.timer, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      plan.activitiesCountText,
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],

              // Statistics row
              Row(
                children: [
                  _buildStatChip(
                    Icons.event,
                    plan.activitiesCountText,
                    Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  _buildStatChip(
                    Icons.schedule,
                    plan.durationDisplay,
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
                      'Kế hoạch nhóm',
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
                      color: _getStatusColor(
                        plan.status,
                      ).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      plan.statusDisplay,
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

  String _getPlanTypeName(String planType) {
    switch (planType) {
      case 'personal':
        return 'Cá nhân';
      case 'group':
        return 'Nhóm';
      default:
        return 'Khác';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'draft':
        return Colors.grey;
      case 'active':
        return Colors.green;
      case 'completed':
        return Colors.blue;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Future<void> _showCreatePlanDialog() async {
    // Open plan creation form and insert newly created plan into provider
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const PlanFormPage()),
    );

    if (!mounted) return;
    if (result == null) return;
    if (result['action'] == 'created' && result['plan'] is Map) {
      try {
        final summary = PlanSummary.fromJson(
          Map<String, dynamic>.from(result['plan'] as Map),
        );
        ref.read(plansNotifierProvider.notifier).addPlan(summary);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tạo kế hoạch mới thành công')),
        );
      } catch (_) {
        // ignore malformed return
      }
    }
  }
}
