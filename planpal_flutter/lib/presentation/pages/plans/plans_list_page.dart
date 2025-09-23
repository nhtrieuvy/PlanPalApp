import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/dtos/plan_summary.dart';
import '../../../core/repositories/plan_repository.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/plan_provider.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/error_widget.dart';
import '../../widgets/common/loading_state.dart';
import '../../widgets/common/refreshable_page_wrapper.dart';
import 'package:planpal_flutter/presentation/pages/users/plan_details_page.dart';
import 'package:planpal_flutter/presentation/pages/users/plan_form_page.dart';

class PlansListPage extends StatefulWidget {
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
  State<PlansListPage> createState() => _PlansListPageState();
}

class _PlansListPageState extends State<PlansListPage>
    with SingleTickerProviderStateMixin, RefreshablePage<PlansListPage> {
  late final PlanProvider _planProvider;
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();

  bool _isLoadingMore = false;
  String _currentFilter = 'all'; // 'all', 'personal', 'group'

  @override
  void initState() {
    super.initState();
    _planProvider = PlanProvider(PlanRepository(context.read<AuthProvider>()));
    _tabController = TabController(
      length: widget.showGroupPlansOnly ? 1 : 3,
      vsync: this,
    );
    _setupScrollListener();
    _loadInitialPlans();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Future<void> onRefresh() async {
    await _planProvider.loadPlans(refresh: true);
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        _loadMorePlans();
      }
    });
  }

  Future<void> _loadInitialPlans() async {
    await _planProvider.loadPlans(refresh: true);
  }

  void _loadMorePlans() {
    if (_isLoadingMore || !_planProvider.hasMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    _planProvider.loadPlans().then((_) {
      setState(() {
        _isLoadingMore = false;
      });
    });
  }

  void _onTabChanged(int index) {
    setState(() {
      _currentFilter = ['all', 'personal', 'group'][index];
    });
  }

  List<PlanSummary> _getFilteredPlans() {
    if (widget.showGroupPlansOnly) {
      return _planProvider.getPlansByType('group');
    }
    return _planProvider.getPlansByType(_currentFilter);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _planProvider,
      child: Scaffold(
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
      ),
    );
  }

  Widget _buildBody() {
    return Consumer<PlanProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading && provider.plans.isEmpty) {
          return const LoadingWidget(message: 'Đang tải kế hoạch...');
        }

        if (provider.error != null && provider.plans.isEmpty) {
          return CustomErrorWidget(
            message: provider.error!,
            onRetry: () => provider.loadPlans(refresh: true),
          );
        }

        final filteredPlans = _getFilteredPlans();

        if (filteredPlans.isEmpty && !provider.isLoading) {
          return _buildEmptyState();
        }

        return RefreshablePageWrapper(
          onRefresh: onRefresh,
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: filteredPlans.length + (_isLoadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (_isLoadingMore && index == filteredPlans.length) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: LoadingState(showMessage: false, size: 20),
                );
              }

              final plan = filteredPlans[index];
              return _buildPlanCard(plan);
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_note, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Chưa có kế hoạch nào',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.showGroupPlansOnly
                ? 'Nhóm này chưa có kế hoạch nào'
                : _getEmptyMessage(),
            style: TextStyle(color: Colors.grey[500], fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _showCreatePlanDialog(),
            icon: const Icon(Icons.add),
            label: const Text('Tạo kế hoạch mới'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
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
            _planProvider.removePlan(plan.id);
            return;
          }

          if ((result['action'] == 'updated' || result['action'] == 'edit') &&
              result['plan'] is Map) {
            try {
              final updated = PlanSummary.fromJson(
                Map<String, dynamic>.from(result['plan'] as Map),
              );
              _planProvider.updatePlan(updated);
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
        _planProvider.addPlan(summary);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tạo kế hoạch mới thành công')),
        );
      } catch (_) {
        // ignore malformed return
      }
    }
  }
}
