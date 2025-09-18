import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/dtos/plan_activity.dart';
import '../../../core/repositories/plan_repository.dart';
import '../../../core/providers/auth_provider.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/error_widget.dart';
import '../../widgets/activities/activity_details_dialog.dart';
import '../../../core/theme/app_colors.dart';

class PlanSchedulePage extends StatefulWidget {
  final String planId;
  final String planTitle;

  const PlanSchedulePage({
    super.key,
    required this.planId,
    required this.planTitle,
  });

  @override
  State<PlanSchedulePage> createState() => _PlanSchedulePageState();
}

class _PlanSchedulePageState extends State<PlanSchedulePage>
    with SingleTickerProviderStateMixin {
  late final PlanRepository _planRepo;

  Map<String, List<PlanActivity>>? scheduleByDate;
  Map<String, dynamic>? statistics;
  Map<String, dynamic>? permissions;
  bool isLoading = true;
  String? error;

  late TabController _tabController;
  List<String> dates = [];

  @override
  void initState() {
    super.initState();
    _planRepo = PlanRepository(context.read<AuthProvider>());
    _loadScheduleData();
  }

  Future<void> _loadScheduleData() async {
    try {
      setState(() {
        isLoading = true;
        error = null;
      });

      final scheduleData = await _planRepo.getPlanSchedule(widget.planId);

      final rawScheduleByDate =
          scheduleData['schedule_by_date'] as Map<String, dynamic>? ?? {};
      final Map<String, List<PlanActivity>> parsedSchedule = {};

      for (final entry in rawScheduleByDate.entries) {
        final dateKey = entry.key;
        final dateData = entry.value as Map<String, dynamic>? ?? {};
        final activitiesList = dateData['activities'] as List<dynamic>? ?? [];

        parsedSchedule[dateKey] = activitiesList
            .whereType<Map<String, dynamic>>()
            .map((item) {
              try {
                return PlanActivity.fromJson(Map<String, dynamic>.from(item));
              } catch (e) {
                rethrow;
              }
            })
            .toList();
      }

      setState(() {
        scheduleByDate = parsedSchedule;
        statistics = scheduleData['statistics'];
        permissions = scheduleData['permissions'];

        // Sort dates
        dates = scheduleByDate!.keys.toList()..sort();

        // Initialize tab controller
        if (dates.isNotEmpty) {
          _tabController = TabController(length: dates.length, vsync: this);
        }

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
  void dispose() {
    if (dates.isNotEmpty) {
      _tabController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.planTitle),
            const Text(
              'Lịch trình chi tiết',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        bottom: isLoading || error != null || dates.isEmpty
            ? null
            : TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: dates.map((date) {
                  final dateTime = DateTime.parse(date);
                  final dayName = DateFormat('EEE').format(dateTime);
                  final dayMonth = DateFormat('dd/MM').format(dateTime);
                  return Tab(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(dayName, style: const TextStyle(fontSize: 12)),
                        Text(
                          dayMonth,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
      ),
      body: _buildBody(),
      floatingActionButton: permissions?['can_add_activity'] == true
          ? FloatingActionButton(
              onPressed: () => _showAddActivityDialog(),
              tooltip: 'Thêm hoạt động',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return const LoadingWidget();
    }

    if (error != null) {
      return CustomErrorWidget(message: error!, onRetry: _loadScheduleData);
    }

    if (dates.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_note, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Chưa có hoạt động nào',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Thêm hoạt động đầu tiên cho kế hoạch của bạn',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildStatisticsCard(),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: dates.map((date) {
              final activities = scheduleByDate![date]!;
              return _buildDaySchedule(date, activities);
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildStatisticsCard() {
    if (statistics == null) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Thống kê kế hoạch',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Tổng hoạt động',
                    '${statistics!['total_activities']}',
                    Icons.event,
                    Colors.blue,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Đã hoàn thành',
                    '${statistics!['completed_activities']}',
                    Icons.check_circle,
                    Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Tỷ lệ hoàn thành',
                    '${statistics!['completion_rate'].toStringAsFixed(1)}%',
                    Icons.pie_chart,
                    Colors.orange,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Tổng thời gian',
                    statistics!['total_duration_display'],
                    Icons.access_time,
                    Colors.purple,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildDaySchedule(String date, List<PlanActivity> activities) {
    if (activities.isEmpty) {
      return Center(child: _buildEmptyState(date));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: activities.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final activity = activities[index];
        return _ActivityCard(
          activity: activity,
          onTap: () => _showActivityDetails(activity),
        );
      },
    );
  }

  Widget _buildEmptyState(String date) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.event_available, size: 48, color: Colors.grey[400]),
        const SizedBox(height: 16),
        Text(
          'Không có hoạt động',
          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
        ),
        Text(
          'trong ngày ${DateFormat('dd/MM/yyyy').format(DateTime.parse(date))}',
          style: TextStyle(color: Colors.grey[500]),
        ),
        if (permissions?['can_add_activity'] == true) ...[
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _showAddActivityDialog,
            icon: const Icon(Icons.add),
            label: const Text('Thêm hoạt động'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ],
    );
  }

  void _showActivityDetails(PlanActivity activity) async {
    // Show loading dialog first
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Load full activity details from API
      final detailData = await _planRepo.getActivityDetail(activity.id);
      final fullActivity = PlanActivity.fromJson(detailData);

      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog

        // Show full details dialog
        showDialog(
          context: context,
          builder: (context) => ActivityDetailsDialog(
            activity: fullActivity,
            canEdit: permissions?['can_edit'] == true,
            onEdit: () => _showEditActivityDialog(fullActivity),
            onDelete: () => _deleteActivity(fullActivity),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog

        // Show error and fallback to summary data
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể tải chi tiết: ${e.toString()}'),
            backgroundColor: Colors.orange,
          ),
        );

        // Show dialog with summary data as fallback
        showDialog(
          context: context,
          builder: (context) => ActivityDetailsDialog(
            activity: activity,
            canEdit: permissions?['can_edit'] == true,
            onEdit: () => _showEditActivityDialog(activity),
            onDelete: () => _deleteActivity(activity),
          ),
        );
      }
    }
  }

  void _showAddActivityDialog() {
    Navigator.pushNamed(
      context,
      '/activity-form',
      arguments: {'planId': widget.planId, 'isEdit': false},
    ).then((result) {
      // Refresh data if activity was created
      if (result == true) {
        _loadScheduleData();
      }
    });
  }

  void _showEditActivityDialog(PlanActivity activity) {
    Navigator.pushNamed(
      context,
      '/activity-form',
      arguments: {
        'planId': widget.planId,
        'activityId': activity.id,
        'isEdit': true,
        'activity': activity,
      },
    ).then((result) {
      // Refresh data if activity was updated
      if (result == true) {
        _loadScheduleData();
      }
    });
  }

  Future<void> _deleteActivity(PlanActivity activity) async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      await _planRepo.deleteActivity(activity.id);

      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã xóa hoạt động "${activity.title}"'),
            backgroundColor: Colors.green,
          ),
        );

        // Refresh data
        await _loadScheduleData();
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog

        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể xóa hoạt động: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

// Separate widget for better performance with const constructor
class _ActivityCard extends StatelessWidget {
  final PlanActivity activity;
  final VoidCallback onTap;

  const _ActivityCard({required this.activity, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _getActivityTypeColor(
                activity.activityType,
              ).withValues(alpha: 0.3),
              width: 2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 8),
                _buildTitle(),
                if (activity.description != null &&
                    activity.description!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildDescription(),
                ],
                const SizedBox(height: 8),
                _buildInfoRow(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _getActivityTypeColor(
              activity.activityType,
            ).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            activity.activityTypeDisplay.isNotEmpty
                ? activity.activityTypeDisplay
                : _getActivityTypeName(activity.activityType),
            style: TextStyle(
              fontSize: 12,
              color: _getActivityTypeColor(activity.activityType),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const Spacer(),
        if (activity.isCompleted)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 16,
            ),
          ),
      ],
    );
  }

  Widget _buildTitle() {
    return Text(
      activity.title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        decoration: activity.isCompleted ? TextDecoration.lineThrough : null,
        color: activity.isCompleted ? Colors.grey[600] : null,
      ),
    );
  }

  Widget _buildDescription() {
    return Text(
      activity.description!,
      style: TextStyle(color: Colors.grey[700], fontSize: 14),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildInfoRow() {
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        if (activity.startTime != null)
          _buildInfoChip(Icons.access_time, activity.timeRange),
        if (activity.hasLocation && activity.locationName != null)
          _buildInfoChip(Icons.location_on, activity.locationName!),
        if (activity.estimatedCost != null && activity.estimatedCost! > 0)
          _buildInfoChip(Icons.attach_money, activity.costDisplay),
        if (activity.durationMinutes != null && activity.durationMinutes! > 0)
          _buildInfoChip(
            Icons.timer,
            activity.durationDisplay.isNotEmpty
                ? activity.durationDisplay
                : '${activity.durationMinutes}m',
          ),
      ],
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Color _getActivityTypeColor(String activityType) {
    switch (activityType) {
      case 'eating':
        return Colors.orange;
      case 'resting':
        return Colors.blue;
      case 'moving':
        return Colors.purple;
      case 'sightseeing':
        return Colors.green;
      case 'shopping':
        return Colors.pink;
      case 'entertainment':
        return Colors.red;
      case 'event':
        return Colors.indigo;
      case 'sport':
        return Colors.teal;
      case 'study':
        return Colors.brown;
      case 'work':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _getActivityTypeName(String activityType) {
    switch (activityType) {
      case 'eating':
        return 'Ăn uống';
      case 'resting':
        return 'Nghỉ ngơi';
      case 'moving':
        return 'Di chuyển';
      case 'sightseeing':
        return 'Tham quan';
      case 'shopping':
        return 'Mua sắm';
      case 'entertainment':
        return 'Giải trí';
      case 'event':
        return 'Sự kiện';
      case 'sport':
        return 'Thể thao';
      case 'study':
        return 'Học tập';
      case 'work':
        return 'Công việc';
      default:
        return 'Khác';
    }
  }
}
