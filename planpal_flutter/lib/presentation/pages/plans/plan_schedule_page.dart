import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/dtos/plan_activity.dart';
import 'package:planpal_flutter/core/localization/app_formatters.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/activity_providers.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/services/activity_websocket_service.dart';
import 'package:planpal_flutter/presentation/pages/plans/activity_form_page.dart';

import '../../widgets/activities/activity_details_dialog.dart';
import '../../widgets/common/refreshable_page_wrapper.dart';
import '../../../shared/ui_states/ui_states.dart';

class PlanSchedulePage extends ConsumerWidget {
  final String planId;
  final String planTitle;

  const PlanSchedulePage({
    super.key,
    required this.planId,
    required this.planTitle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduleAsync = ref.watch(activityProvider(planId));
    final realtime = ref.watch(realtimeActivityProvider(planId));
    final state = scheduleAsync.valueOrNull;
    final dates = state?.orderedDates ?? const <String>[];

    final scaffold = Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(planTitle),
            Text(
              context.l10n.t('plan.schedule_fallback_title'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        bottom: dates.isEmpty
            ? null
            : TabBar(
                isScrollable: true,
                tabs: dates.map((date) {
                  final dateTime = DateTime.parse(date);
                  return Tab(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          AppFormatters.weekdayShort(context, dateTime),
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          AppFormatters.shortMonthDay(context, dateTime),
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
      body: _buildBody(context, ref, scheduleAsync, realtime),
      floatingActionButton: state?.permissions?['can_add_activity'] == true
          ? FloatingActionButton(
              onPressed: () => _openCreateActivity(context, ref),
              tooltip: context.l10n.t('plan.add_activity_tooltip'),
              child: const Icon(Icons.add),
            )
          : null,
    );

    if (dates.isEmpty) {
      return scaffold;
    }
    return DefaultTabController(length: dates.length, child: scaffold);
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<PlanActivitiesState> scheduleAsync,
    ActivityRealtimeState realtime,
  ) {
    if (scheduleAsync.isLoading && scheduleAsync.valueOrNull == null) {
      return const AppSkeleton.list(itemCount: 6);
    }

    if (scheduleAsync.hasError && scheduleAsync.valueOrNull == null) {
      return AppError(
        message: scheduleAsync.error.toString(),
        onRetry: () => ref.read(activityProvider(planId).notifier).refresh(),
        retryLabel: context.l10n.t('common.retry'),
      );
    }

    final state = scheduleAsync.valueOrNull ?? const PlanActivitiesState();
    final dates = state.orderedDates;

    if (dates.isEmpty) {
      return RefreshablePageWrapper(
        onRefresh: () => ref.read(activityProvider(planId).notifier).refresh(),
        child: AppEmpty(
          icon: Icons.event_note,
          title: context.l10n.t('plan.no_activities'),
          description: context.l10n.t('activity_form.submit_create'),
          actionLabel: state.permissions?['can_add_activity'] == true
              ? context.l10n.t('common.add')
              : null,
          onAction: state.permissions?['can_add_activity'] == true
              ? () => _openCreateActivity(context, ref)
              : null,
        ),
      );
    }

    return RefreshablePageWrapper(
      onRefresh: () => ref.read(activityProvider(planId).notifier).refresh(),
      child: Column(
        children: [
          if (realtime.connectionState != ActivitySocketConnectionState.connected)
            _RealtimeBanner(realtime: realtime),
          _StatisticsCard(statistics: state.statistics),
          Expanded(
            child: TabBarView(
              children: dates.map((date) {
                final activities = state.scheduleByDate[date] ?? const <PlanActivity>[];
                return _buildDaySchedule(
                  context,
                  ref,
                  date: date,
                  activities: activities,
                  canEdit: state.permissions?['can_edit'] == true,
                  highlights: realtime.highlights,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDaySchedule(
    BuildContext context,
    WidgetRef ref, {
    required String date,
    required List<PlanActivity> activities,
    required bool canEdit,
    required Map<String, ActivityRealtimeHighlight> highlights,
  }) {
    if (activities.isEmpty) {
      return AppEmpty(
        icon: Icons.event_available,
        title: context.l10n.t('plan.no_activities'),
        description: AppFormatters.shortDate(context, DateTime.parse(date)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: activities.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final activity = activities[index];
        return _ActivityCard(
          activity: activity,
          highlight: highlights[activity.id],
          onTap: () => _showActivityDetails(
            context,
            ref,
            activity,
            canEdit: canEdit,
            highlight: highlights[activity.id],
          ),
        );
      },
    );
  }

  Future<void> _showActivityDetails(
    BuildContext context,
    WidgetRef ref,
    PlanActivity activity, {
    required bool canEdit,
    ActivityRealtimeHighlight? highlight,
  }) async {
    final repo = ref.read(planRepositoryProvider);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AppLoading(message: context.l10n.t('common.loading_session')),
    );

    try {
      final detailData = await repo.getActivityDetail(activity.id);
      final fullActivity = PlanActivity.fromJson(detailData);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      showDialog(
        context: context,
        builder: (_) => ActivityDetailsDialog(
          activity: fullActivity,
          canEdit: canEdit,
          realtimeHighlight: highlight,
          onEdit: canEdit ? () => _openEditActivity(context, ref, fullActivity) : null,
          onDelete: canEdit ? () => _deleteActivity(context, ref, fullActivity) : null,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.t(
              'schedule.load_detail_error',
              params: {'error': error.toString()},
            ),
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _openCreateActivity(BuildContext context, WidgetRef ref) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ActivityFormPage(
          planId: planId,
          planTitle: planTitle,
        ),
      ),
    );
    if (result == true) {
      await ref.read(activityProvider(planId).notifier).refresh();
    }
  }

  Future<void> _openEditActivity(
    BuildContext context,
    WidgetRef ref,
    PlanActivity activity,
  ) async {
    Navigator.of(context).pop();
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ActivityFormPage(
          planId: planId,
          planTitle: planTitle,
          initialActivity: activity,
        ),
      ),
    );
    if (result == true) {
      await ref.read(activityProvider(planId).notifier).refresh();
    }
  }

  Future<void> _deleteActivity(
    BuildContext context,
    WidgetRef ref,
    PlanActivity activity,
  ) async {
    final repo = ref.read(planRepositoryProvider);
    Navigator.of(context).pop();
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            AppLoading(message: context.l10n.t('schedule.delete_loading')),
      );
      await repo.deleteActivity(activity.id);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.t(
              'schedule.delete_success',
              params: {'title': activity.title},
            ),
          ),
          backgroundColor: Colors.green,
        ),
      );
      await ref.read(activityProvider(planId).notifier).refresh();
    } catch (error) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.t(
              'schedule.delete_error',
              params: {'error': error.toString()},
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class _RealtimeBanner extends StatelessWidget {
  final ActivityRealtimeState realtime;

  const _RealtimeBanner({required this.realtime});

  @override
  Widget build(BuildContext context) {
    final isPolling = realtime.isPollingFallback;
    final message = isPolling
        ? context.l10n.t('activity_collab.polling_fallback')
        : context.l10n.t('activity_collab.realtime_connecting');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.amber.shade50,
      child: Row(
        children: [
          Icon(Icons.sync_problem, size: 18, color: Colors.amber.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: Colors.amber.shade900),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatisticsCard extends StatelessWidget {
  final Map<String, dynamic>? statistics;

  const _StatisticsCard({required this.statistics});

  @override
  Widget build(BuildContext context) {
    if (statistics == null || statistics!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.t('schedule.stats_title'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatItem(
                    label: context.l10n.t('plan.activities'),
                    value: '${statistics!['total_activities'] ?? 0}',
                    icon: Icons.event,
                    color: Colors.blue,
                  ),
                ),
                Expanded(
                  child: _StatItem(
                    label: context.l10n.t('activity_details.completed'),
                    value: '${statistics!['completed_activities'] ?? 0}',
                    icon: Icons.check_circle,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _StatItem(
                    label: context.l10n.t('analytics.metric.plan_completion_rate'),
                    value:
                        '${((statistics!['completion_rate'] as num?) ?? 0).toStringAsFixed(1)}%',
                    icon: Icons.pie_chart,
                    color: Colors.orange,
                  ),
                ),
                Expanded(
                  child: _StatItem(
                    label: context.l10n.t('activity_details.time'),
                    value:
                        statistics!['total_duration_display']?.toString() ?? '0m',
                    icon: Icons.access_time,
                    color: Colors.purple,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
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
}

class _ActivityCard extends StatelessWidget {
  final PlanActivity activity;
  final ActivityRealtimeHighlight? highlight;
  final VoidCallback onTap;

  const _ActivityCard({
    required this.activity,
    required this.onTap,
    this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = highlight != null ? Colors.amber : _getActivityTypeColor(activity.activityType);
    return Card(
      margin: EdgeInsets.zero,
      elevation: highlight != null ? 4 : 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: accentColor.withValues(alpha: highlight != null ? 0.8 : 0.3),
              width: highlight != null ? 2.5 : 2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                if (highlight != null) ...[
                  const SizedBox(height: 8),
                  _buildRealtimeNote(context),
                ],
                const SizedBox(height: 8),
                _buildTitle(),
                if (activity.description != null && activity.description!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildDescription(),
                ],
                const SizedBox(height: 8),
                _buildInfoRow(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _getActivityTypeColor(activity.activityType).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            context.l10n.activityTypeLabel(activity.activityType),
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
            child: const Icon(Icons.check_circle, color: Colors.green, size: 16),
          ),
      ],
    );
  }

  Widget _buildRealtimeNote(BuildContext context) {
    final fields = highlight!.updatedFields
        .map((field) => context.l10n.activityFieldLabel(field))
        .join(', ');
    final byUser = highlight!.updatedBy;
    final label = byUser == null || byUser.isEmpty
        ? context.l10n.t(
            'activity_collab.edited_fields',
            params: {'fields': fields.isEmpty ? context.l10n.t('common.edit') : fields},
          )
        : context.l10n.t(
            'activity_collab.edited_by',
            params: {
              'user': byUser,
              'fields': fields.isEmpty ? context.l10n.t('common.edit') : fields,
            },
          );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 16, color: Colors.amber.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.amber.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
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

  Widget _buildInfoRow(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        if (activity.startTime != null) _buildInfoChip(Icons.access_time, activity.timeRange),
        if (activity.hasLocation && activity.locationName != null)
          _buildInfoChip(Icons.location_on, activity.locationName!),
        if (activity.estimatedCost != null && activity.estimatedCost! > 0)
          _buildInfoChip(Icons.attach_money, activity.costDisplay),
        if (activity.durationMinutes != null && activity.durationMinutes! > 0)
          _buildInfoChip(Icons.timer, '${activity.durationMinutes}m'),
        _buildInfoChip(Icons.layers, 'v${activity.version}'),
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
}
