import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:planpal_flutter/core/providers/auth_provider.dart';
import 'package:planpal_flutter/core/repositories/plan_repository.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:intl/intl.dart';
import 'package:getwidget/getwidget.dart';

class PlanDetailsPage extends StatelessWidget {
  final String id;
  const PlanDetailsPage({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    final repo = PlanRepository(context.read<AuthProvider>());
    final df = DateFormat('dd/MM/yyyy HH:mm');
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: FutureBuilder<Map<String, dynamic>>(
        future: repo.getPlanDetail(id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('Chi tiết kế hoạch'),
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              body: const Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('Chi tiết kế hoạch'),
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.redAccent[200],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Có lỗi xảy ra',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Lỗi: ${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final p = snapshot.data ?? <String, dynamic>{};
          final name = (p['title'] ?? '').toString();
          final dest = (p['description'] ?? '').toString();
          final status = (p['status_display'] ?? p['status'] ?? '').toString();
          final planType = (p['plan_type'] ?? 'personal').toString();
          final isPublic = p['is_public'] == true;
          final groupName = (p['group_name'] ?? p['group']?['name'] ?? '')
              .toString();
          final start = p['start_date']?.toString();
          final end = p['end_date']?.toString();
          final durationDisplay = (p['duration_display'] ?? '').toString();
          final activitiesCount = p['activities_count'] ?? 0;
          final totalEstimatedCost = p['total_estimated_cost'];
          final activities = (p['activities'] is List)
              ? List<Map<String, dynamic>>.from(p['activities'])
              : <Map<String, dynamic>>[];

          DateTime? startDt, endDt;
          try {
            if (start != null) startDt = DateTime.parse(start);
          } catch (_) {}
          try {
            if (end != null) endDt = DateTime.parse(end);
          } catch (_) {}

          final creator = p['creator'] as Map<String, dynamic>? ?? {};
          final creatorName =
              creator['display_name'] ?? creator['username'] ?? 'Không rõ';
          final creatorAvatar = creator['avatar_url'] ?? '';

          return NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverAppBar(
                expandedHeight: 200,
                floating: false,
                pinned: true,
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: AppColors.primaryGradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.event_note,
                        size: 80,
                        color: Colors.white.withAlpha(75),
                      ),
                    ),
                  ),
                ),
                actions: [
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        Navigator.of(
                          context,
                        ).pop({'action': 'edit', 'plan': p});
                      } else if (value == 'delete') {
                        Navigator.of(
                          context,
                        ).pop({'action': 'delete', 'id': p['id']});
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 20),
                            SizedBox(width: 8),
                            Text('Sửa'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 20),
                            SizedBox(width: 8),
                            Text('Xoá'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCreatorCard(creatorAvatar, creatorName),
                  const SizedBox(height: 16),
                  // Meta card (status, type, visibility, duration, counts)
                  _buildMetaCard(
                    theme: theme,
                    status: status,
                    planType: planType,
                    isPublic: isPublic,
                    durationDisplay: durationDisplay,
                    activitiesCount: activitiesCount,
                    totalEstimatedCost: totalEstimatedCost,
                    groupName: groupName,
                  ),

                  // Description Card
                  if (dest.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildInfoCard(
                      icon: Icons.description,
                      title: 'Mô tả',
                      subtitle: dest,
                      color: AppColors.primary,
                      theme: theme,
                    ),
                  ],

                  // Date Information Card
                  if (startDt != null || endDt != null) ...[
                    const SizedBox(height: 16),
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.info.withAlpha(25),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.schedule,
                                    color: AppColors.info,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Thời gian',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            if (startDt != null)
                              _buildDateRow(
                                icon: Icons.play_arrow,
                                label: 'Bắt đầu',
                                date: df.format(startDt),
                                theme: theme,
                              ),
                            if (startDt != null && endDt != null)
                              const SizedBox(height: 12),
                            if (endDt != null)
                              _buildDateRow(
                                icon: Icons.stop,
                                label: 'Kết thúc',
                                date: df.format(endDt),
                                theme: theme,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // Activities Card
                  if (activities.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildActivitiesCard(
                      theme: theme,
                      activities: activities,
                      df: df,
                    ),
                  ],

                  // Action Buttons
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(
                              context,
                            ).pop({'action': 'edit', 'plan': p});
                          },
                          icon: const Icon(Icons.edit),
                          label: const Text('Chỉnh sửa'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(
                              context,
                            ).pop({'action': 'delete', 'id': p['id']});
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Xoá'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required ThemeData theme,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withAlpha(25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle, style: theme.textTheme.bodyLarge),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRow({
    required IconData icon,
    required String label,
    required String date,
    required ThemeData theme,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Text(
          '$label:',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          date,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String status, ThemeData theme) {
    Color statusColor;
    IconData statusIcon;
    String statusText = status;

    switch (status.toLowerCase()) {
      case 'upcoming':
      case 'sắp diễn ra':
        statusColor = AppColors.info;
        statusIcon = Icons.schedule;
        break;
      case 'ongoing':
      case 'đang diễn ra':
        statusColor = AppColors.warning;
        statusIcon = Icons.play_circle;
        break;
      case 'completed':
      case 'hoàn thành':
        statusColor = AppColors.success;
        statusIcon = Icons.check_circle;
        break;
      case 'cancelled':
      case 'đã hủy':
        statusColor = AppColors.error;
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.info;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: statusColor.withAlpha(25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withAlpha(75)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon, size: 16, color: statusColor),
          const SizedBox(width: 6),
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreatorCard(String avatarUrl, String name) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: avatarUrl.isNotEmpty
                  ? CircleAvatar(
                      radius: 24,
                      backgroundImage: NetworkImage(avatarUrl),
                      backgroundColor: Colors.transparent,
                    )
                  : const Icon(
                      Icons.person,
                      color: AppColors.primary,
                      size: 28,
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Người tạo',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaCard({
    required ThemeData theme,
    required String status,
    required String planType,
    required bool isPublic,
    required String durationDisplay,
    required int activitiesCount,
    required dynamic totalEstimatedCost,
    required String groupName,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.info.withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.dashboard_customize,
                    color: AppColors.info,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Tổng quan',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildStatusChip(status, theme),
                _buildChip(
                  label: planType == 'group'
                      ? 'Kế hoạch nhóm'
                      : 'Kế hoạch cá nhân',
                  icon: planType == 'group' ? Icons.group : Icons.person,
                  color: AppColors.secondary,
                ),
                if (groupName.isNotEmpty)
                  _buildChip(
                    label: groupName,
                    icon: Icons.groups_2,
                    color: AppColors.secondary,
                  ),
                _buildChip(
                  label: isPublic ? 'Công khai' : 'Riêng tư',
                  icon: isPublic ? Icons.public : Icons.lock,
                  color: isPublic ? AppColors.success : Colors.grey,
                ),
                if (durationDisplay.isNotEmpty)
                  _buildChip(
                    label: durationDisplay,
                    icon: Icons.timelapse,
                    color: AppColors.info,
                  ),
                _buildChip(
                  label: 'Hoạt động: $activitiesCount',
                  icon: Icons.list_alt,
                  color: AppColors.primary,
                ),
                if (totalEstimatedCost != null)
                  _buildChip(
                    label:
                        'Tổng dự kiến: ${_formatCurrency(totalEstimatedCost)}',
                    icon: Icons.attach_money,
                    color: AppColors.warning,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(75)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivitiesCard({
    required ThemeData theme,
    required List<Map<String, dynamic>> activities,
    required DateFormat df,
  }) {
    final display = activities.take(5).toList();
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.event_note,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Hoạt động',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (display.isEmpty)
              Text('Chưa có hoạt động', style: theme.textTheme.bodyMedium)
            else
              ...display.map((a) {
                DateTime? st, et;
                try {
                  st = DateTime.parse(a['start_time'].toString());
                } catch (_) {}
                try {
                  et = DateTime.parse(a['end_time'].toString());
                } catch (_) {}
                final title = (a['title'] ?? '').toString();
                final type =
                    (a['activity_type_display'] ?? a['activity_type'] ?? '')
                        .toString();
                String timeRange = '';
                if (st != null) {
                  timeRange = df.format(st);
                  if (et != null) {
                    timeRange += ' - ' + df.format(et);
                  }
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (type.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(
                                  type,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                            if (timeRange.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(
                                  timeRange,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            if (activities.length > display.length)
              Align(
                alignment: Alignment.centerLeft,
                child: GFButton(
                  onPressed: () {},
                  size: GFSize.SMALL,
                  type: GFButtonType.outline,
                  shape: GFButtonShape.pills,
                  icon: const Icon(Icons.more_horiz, size: 16),
                  text: 'Xem thêm (${activities.length - display.length})',
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _formatCurrency(dynamic value) {
    if (value == null) return '';
    try {
      final num v = (value is num) ? value : num.parse(value.toString());
      final fmt = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');
      return fmt.format(v);
    } catch (_) {
      return value.toString();
    }
  }
}
