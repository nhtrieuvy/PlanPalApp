import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/dtos/plan_summary.dart';
import '../../../core/repositories/plan_repository.dart';
import '../../../core/providers/auth_provider.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/error_widget.dart';
import 'plan_schedule_page.dart';

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
    with SingleTickerProviderStateMixin {
  late final PlanRepository _planRepo;

  List<PlanSummary> plans = [];
  bool isLoading = true;
  String? error;

  late TabController _tabController;
  List<PlanSummary> allPlans = [];
  List<PlanSummary> personalPlans = [];
  List<PlanSummary> groupPlans = [];

  @override
  void initState() {
    super.initState();
    _planRepo = PlanRepository(context.read<AuthProvider>());
    _tabController = TabController(
      length: widget.showGroupPlansOnly ? 1 : 3,
      vsync: this,
    );
    _loadPlans();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPlans() async {
    try {
      setState(() {
        isLoading = true;
        error = null;
      });

      if (widget.showGroupPlansOnly && widget.groupId != null) {
        // Load group plans only
        allPlans = await _planRepo.getPlans();
        plans = allPlans
            .where((p) => p.planType == 'group' && p.groupId == widget.groupId)
            .toList();
      } else {
        // Load all user's plans
        allPlans = await _planRepo.getPlans();
        personalPlans = allPlans
            .where((p) => p.planType == 'personal')
            .toList();
        groupPlans = allPlans.where((p) => p.planType == 'group').toList();
        plans = allPlans;
      }

      setState(() {
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        isLoading = false;
      });
    }
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
        actions: [
          IconButton(
            onPressed: _loadPlans,
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới',
          ),
        ],
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
    if (isLoading) {
      return const LoadingWidget(message: 'Đang tải kế hoạch...');
    }

    if (error != null) {
      return CustomErrorWidget(message: error!, onRetry: _loadPlans);
    }

    if (plans.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadPlans,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: plans.length,
        itemBuilder: (context, index) {
          final plan = plans[index];
          return _buildPlanCard(plan);
        },
      ),
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
                : 'Tạo kế hoạch đầu tiên của bạn',
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

  Widget _buildPlanCard(PlanSummary plan) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: InkWell(
        onTap: () => _openPlanSchedule(plan),
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
              // Removed description since PlanSummary doesn't have it
              const SizedBox(height: 12),

              // Date range
              if (plan.startDate != null && plan.endDate != null) ...[
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${DateFormat('dd/MM/yyyy').format(plan.startDate!)} - ${DateFormat('dd/MM/yyyy').format(plan.endDate!)}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                    const SizedBox(width: 16),
                    Icon(Icons.timer, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      '${plan.activitiesCount} hoạt động', // Using activitiesCount instead of durationDisplay
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
                    '${plan.activitiesCount} hoạt động',
                    Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  // Removed budget info since PlanSummary doesn't have budget
                ],
              ),

              if (plan.planType == 'group') ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.group, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      'Kế hoạch nhóm', // Since we don't have groupName, just show generic text
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
                  // Removed creator name since PlanSummary doesn't have creatorName
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
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

  void _onTabChanged(int index) {
    setState(() {
      switch (index) {
        case 0:
          plans = allPlans;
          break;
        case 1:
          plans = personalPlans;
          break;
        case 2:
          plans = groupPlans;
          break;
      }
    });
  }

  void _openPlanSchedule(PlanSummary plan) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            PlanSchedulePage(planId: plan.id, planTitle: plan.title),
      ),
    );
  }

  void _showCreatePlanDialog() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chức năng tạo kế hoạch sẽ được cập nhật'),
        ),
      );
    }
  }
}
