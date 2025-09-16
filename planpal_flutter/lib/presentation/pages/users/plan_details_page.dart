import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:getwidget/getwidget.dart';
import 'package:planpal_flutter/core/providers/auth_provider.dart';
import 'package:planpal_flutter/core/repositories/plan_repository.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import '../../../core/dtos/plan_model.dart';
import '../../../core/dtos/plan_activity.dart';
import '../plans/activity_form_page.dart';
import '../plans/plan_schedule_page.dart';

class PlanDetailsPage extends StatefulWidget {
  final String id;
  const PlanDetailsPage({super.key, required this.id});

  @override
  State<PlanDetailsPage> createState() => _PlanDetailsPageState();
}

class _PlanDetailsPageState extends State<PlanDetailsPage> {
  late final PlanRepository _repo;
  PlanModel? _detail;
  Object? _error;
  bool _loading = true;
  final _df = DateFormat('dd/MM/yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    _repo = PlanRepository(context.read<AuthProvider>());
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (refresh) _repo.clearCacheEntry(widget.id);
      final d = await _repo.getPlanDetail(widget.id);
      if (!mounted) return;
      setState(() {
        _detail = d;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Chi tiết kế hoạch'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _detail == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Chi tiết kế hoạch'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              onPressed: () => _load(refresh: true),
              icon: const Icon(Icons.refresh),
            ),
          ],
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
                Text('Lỗi: $_error', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }

    final p = _detail!;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: NestedScrollView(
        headerSliverBuilder: (context, inner) => [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                p.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              background: Container(
                decoration: const BoxDecoration(
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
                    Navigator.of(context).pop({
                      'action': 'edit',
                      'plan': {'id': p.id, 'title': p.title},
                    });
                  } else if (value == 'delete') {
                    Navigator.of(context).pop({'action': 'delete', 'id': p.id});
                  } else if (value == 'refresh') {
                    _load(refresh: true);
                  }
                },
                itemBuilder: (c) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 20),
                        SizedBox(width: 8),
                        Text('Sửa'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 20),
                        SizedBox(width: 8),
                        Text('Xoá'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'refresh',
                    child: Row(
                      children: [
                        Icon(Icons.refresh, size: 20),
                        SizedBox(width: 8),
                        Text('Làm mới'),
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
              _buildCreatorCard(
                p.creator.avatarForDisplay,
                (p.creator.fullName.isNotEmpty
                    ? p.creator.fullName
                    : p.creator.username),
              ),
              const SizedBox(height: 16),
              _buildMetaCard(
                theme: theme,
                statusCode: p.status,
                statusLabel: p.statusDisplay.isNotEmpty
                    ? p.statusDisplay
                    : p.status,
                planType: p.planType,
                isPublic: p.isPublic,
                durationDisplay: p.durationDisplay,
                activitiesCount: p.activitiesCount,
                totalEstimatedCost: p.totalEstimatedCost,
                groupName: p.groupName ?? '',
              ),
              if (p.description != null && p.description!.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildInfoCard(
                  icon: Icons.description,
                  title: 'Mô tả',
                  subtitle: p.description!,
                  color: AppColors.primary,
                  theme: theme,
                ),
              ],
              if (p.startDate != null || p.endDate != null) ...[
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
                              child: const Icon(
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
                        if (p.startDate != null)
                          _buildDateRow(
                            icon: Icons.play_arrow,
                            label: 'Bắt đầu',
                            date: _df.format(p.startDate!),
                            theme: theme,
                          ),
                        if (p.startDate != null && p.endDate != null)
                          const SizedBox(height: 12),
                        if (p.endDate != null)
                          _buildDateRow(
                            icon: Icons.stop,
                            label: 'Kết thúc',
                            date: _df.format(p.endDate!),
                            theme: theme,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              if (p.activities.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildActivitiesCard(
                  theme: theme,
                  activities: p.activities,
                  df: _df,
                ),
              ],
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).pop({
                        'action': 'edit',
                        'plan': {'id': p.id, 'title': p.title},
                      }),
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
                      onPressed: () => Navigator.of(
                        context,
                      ).pop({'action': 'delete', 'id': p.id}),
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
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            onPressed: () => _navigateToSchedule(p.id),
            backgroundColor: AppColors.info,
            foregroundColor: Colors.white,
            heroTag: "schedule",
            tooltip: 'Xem thời khóa biểu',
            child: const Icon(Icons.calendar_view_day),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            onPressed: () => _navigateToCreateActivity(p.id),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            heroTag: "add_activity",
            tooltip: 'Thêm hoạt động',
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  void _navigateToCreateActivity(String planId) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) => ActivityFormPage(
              planId: planId,
              planTitle: _detail?.title ?? 'Kế hoạch',
            ),
          ),
        )
        .then((result) {
          // Refresh plan details if activity was created successfully
          if (result == true) {
            _load(refresh: true);
          }
        });
  }

  void _navigateToSchedule(String planId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PlanSchedulePage(
          planId: planId,
          planTitle: _detail?.title ?? 'Thời khóa biểu',
        ),
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

  Widget _buildStatusChip({
    required String code,
    required String label,
    required ThemeData theme,
  }) {
    Color statusColor;
    IconData statusIcon;
    switch (code.toLowerCase()) {
      case 'upcoming':
        statusColor = AppColors.info;
        statusIcon = Icons.schedule;
        break;
      case 'ongoing':
        statusColor = AppColors.warning;
        statusIcon = Icons.play_circle;
        break;
      case 'completed':
        statusColor = AppColors.success;
        statusIcon = Icons.check_circle;
        break;
      case 'cancelled':
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
            label,
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
                  ? ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: avatarUrl,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        placeholder: (c, u) => Container(
                          color: Colors.grey[200],
                          child: const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                        errorWidget: (c, u, e) => const Icon(
                          Icons.person,
                          color: AppColors.primary,
                          size: 28,
                        ),
                      ),
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
    required String statusCode,
    required String statusLabel,
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
                _buildStatusChip(
                  code: statusCode,
                  label: statusLabel,
                  theme: theme,
                ),
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
    required List<PlanActivity> activities,
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
                final st = a.startTime;
                final et = a.endTime;
                final title = a.title;
                final type = a.activityType;
                String timeRange = '';
                if (st != null) {
                  timeRange = df.format(st);
                  if (et != null) timeRange += ' - ${df.format(et)}';
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
