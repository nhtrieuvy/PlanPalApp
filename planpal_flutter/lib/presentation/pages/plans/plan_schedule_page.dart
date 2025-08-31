import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/dtos/plan_detail.dart';
import '../../../core/repositories/plan_repository.dart';
import '../../../core/providers/auth_provider.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/error_widget.dart';

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

  Map<String, List<ActivityItem>>? scheduleByDate;
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

      // Parse schedule by date correctly
      final rawScheduleByDate =
          scheduleData['schedule_by_date'] as Map<String, dynamic>? ?? {};
      final Map<String, List<ActivityItem>> parsedSchedule = {};

      for (final entry in rawScheduleByDate.entries) {
        final dateKey = entry.key;
        final activitiesList = entry.value as List<dynamic>? ?? [];

        parsedSchedule[dateKey] = activitiesList
            .whereType<Map<String, dynamic>>()
            .map((item) {
              try {
                return ActivityItem.fromJson(Map<String, dynamic>.from(item));
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
        _tabController = TabController(length: dates.length, vsync: this);

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
    _tabController.dispose();
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

  Widget _buildDaySchedule(String date, List<ActivityItem> activities) {
    if (activities.isEmpty) {
      return Center(
        child: Column(
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
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: activities.length,
      itemBuilder: (context, index) {
        final activity = activities[index];
        return _buildActivityCard(activity, index);
      },
    );
  }

  Widget _buildActivityCard(ActivityItem activity, int index) {
    final startTime = activity.startTime;
    final endTime = activity.endTime;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation:
          2, // Removed isCompleted check since ActivityItem doesn't have it
      child: InkWell(
        onTap: () => _showActivityDetails(activity),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _getActivityTypeColor(
                activity.type,
              ).withValues(alpha: 0.3),
              width: 2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _getActivityTypeColor(
                          activity.type,
                        ).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _getActivityTypeName(activity.type),
                        style: TextStyle(
                          fontSize: 12,
                          color: _getActivityTypeColor(activity.type),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Removed completion status since ActivityItem doesn't have isCompleted
                    // IconButton for completion toggle would need backend support
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  activity.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    // Removed decoration and color since no completion status
                  ),
                ),
                // Removed description since ActivityItem doesn't have it
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (startTime != null) ...[
                      Icon(
                        Icons.access_time,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${DateFormat('HH:mm').format(startTime)}${endTime != null ? ' - ${DateFormat('HH:mm').format(endTime)}' : ''}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      ),
                      // Calculate and show duration if both times are available
                      if (endTime != null) ...[
                        const SizedBox(width: 16),
                        Icon(Icons.timer, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          _calculateDuration(startTime, endTime),
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
                // Removed location info since ActivityItem doesn't have it
                // Removed cost info since ActivityItem doesn't have it
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _calculateDuration(DateTime start, DateTime end) {
    final duration = end.difference(start);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
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

  void _showActivityDetails(ActivityItem activity) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(activity.title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Only show basic info available from ActivityItem
              Text('Loại:', style: Theme.of(context).textTheme.titleSmall),
              Text(_getActivityTypeName(activity.type)),
              const SizedBox(height: 8),
              if (activity.startTime != null) ...[
                Text(
                  'Thời gian:',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  '${DateFormat('dd/MM/yyyy HH:mm').format(activity.startTime!)}${activity.endTime != null ? ' - ${DateFormat('HH:mm').format(activity.endTime!)}' : ''}',
                ),
                const SizedBox(height: 8),
              ],
              // Removed other fields since ActivityItem doesn't have them
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Đóng'),
          ),
          if (permissions?['can_edit'] == true)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showEditActivityDialog(activity);
              },
              child: const Text('Chỉnh sửa'),
            ),
        ],
      ),
    );
  }

  void _showAddActivityDialog() {
    // TODO: Implement add activity dialog
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chức năng thêm hoạt động sẽ được cập nhật'),
        ),
      );
    }
  }

  void _showEditActivityDialog(ActivityItem activity) {
    // TODO: Implement edit activity dialog
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chức năng chỉnh sửa hoạt động sẽ được cập nhật'),
        ),
      );
    }
  }
}
