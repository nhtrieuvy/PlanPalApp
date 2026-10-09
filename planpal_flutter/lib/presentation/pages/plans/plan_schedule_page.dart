import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/dtos/plan_activity.dart';
import 'package:planpal_flutter/core/localization/app_formatters.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/maps/planpal_map.dart';
import 'package:planpal_flutter/core/riverpod/activity_providers.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/services/activity_websocket_service.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:planpal_flutter/core/theme/app_design_tokens.dart';
import 'package:planpal_flutter/presentation/pages/plans/activity_form_page.dart';

import '../../widgets/activities/activity_details_dialog.dart';
import '../../widgets/common/refreshable_page_wrapper.dart';
import '../../widgets/design_system/journey_ui.dart';
import '../../widgets/layout/responsive_content.dart';
import '../../../shared/ui_states/ui_states.dart';

final _selectedScheduleActivityProvider = StateProvider.autoDispose
    .family<String?, String>((ref, planId) => null);
final _scheduleMapVisibleProvider = StateProvider.autoDispose
    .family<bool, String>((ref, planId) => false);

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
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
              ),
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
      body: ResponsiveContent(
        mediumMaxWidth: 900,
        expandedMaxWidth: 1120,
        child: _buildBody(context, ref, scheduleAsync, realtime),
      ),
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
        message: ErrorDisplayService.getUserFriendlyMessage(
          scheduleAsync.error,
        ),
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
          if (realtime.connectionState !=
              ActivitySocketConnectionState.connected)
            _RealtimeBanner(realtime: realtime),
          _StatisticsCard(statistics: state.statistics),
          Expanded(
            child: TabBarView(
              children: dates.map((date) {
                final activities =
                    state.scheduleByDate[date] ?? const <PlanActivity>[];
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

    final selectedId = ref.watch(_selectedScheduleActivityProvider(planId));
    final mapVisible = ref.watch(_scheduleMapVisibleProvider(planId));
    final locatedActivities = activities
        .where(
          (activity) => activity.latitude != null && activity.longitude != null,
        )
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final canShowMap =
            constraints.maxWidth >= 980 && locatedActivities.isNotEmpty;
        final showMap = canShowMap && mapVisible;
        final timeline = _buildActivityTimeline(
          context,
          ref,
          activities: activities,
          canEdit: canEdit,
          highlights: highlights,
          selectedId: selectedId,
        );
        return Column(
          children: [
            if (canShowMap)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        ref
                                .read(
                                  _scheduleMapVisibleProvider(planId).notifier,
                                )
                                .state =
                            !mapVisible,
                    icon: Icon(
                      showMap ? Icons.view_agenda_outlined : Icons.map_outlined,
                    ),
                    label: Text(
                      showMap
                          ? context.l10n.t('plan.hide_map')
                          : context.l10n.t('plan.show_map'),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: showMap
                  ? Row(
                      children: [
                        Expanded(flex: 6, child: timeline),
                        VerticalDivider(
                          width: 1,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        Expanded(
                          flex: 5,
                          child: _ScheduleMapPane(
                            activities: locatedActivities,
                            selectedId: selectedId,
                            onSelect: (activityId) =>
                                ref
                                        .read(
                                          _selectedScheduleActivityProvider(
                                            planId,
                                          ).notifier,
                                        )
                                        .state =
                                    activityId,
                          ),
                        ),
                      ],
                    )
                  : timeline,
            ),
          ],
        );
      },
    );
  }

  Widget _buildActivityTimeline(
    BuildContext context,
    WidgetRef ref, {
    required List<PlanActivity> activities,
    required bool canEdit,
    required Map<String, ActivityRealtimeHighlight> highlights,
    required String? selectedId,
  }) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        96,
      ),
      itemCount: activities.length,
      itemBuilder: (context, index) {
        final activity = activities[index];
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              JourneyRouteMarker(
                icon: _activityTypeIcon(activity.activityType),
                isFirst: index == 0,
                isLast: index == activities.length - 1,
                completed: activity.isCompleted,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: MouseRegion(
                    onEnter: (_) =>
                        ref
                                .read(
                                  _selectedScheduleActivityProvider(
                                    planId,
                                  ).notifier,
                                )
                                .state =
                            activity.id,
                    child: _ActivityCard(
                      activity: activity,
                      selected: selectedId == activity.id,
                      highlight: highlights[activity.id],
                      onTap: () {
                        ref
                                .read(
                                  _selectedScheduleActivityProvider(
                                    planId,
                                  ).notifier,
                                )
                                .state =
                            activity.id;
                        _showActivityDetails(
                          context,
                          ref,
                          activity,
                          canEdit: canEdit,
                          highlight: highlights[activity.id],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _activityTypeIcon(String activityType) {
    switch (activityType) {
      case 'eating':
        return Icons.restaurant_rounded;
      case 'resting':
        return Icons.hotel_rounded;
      case 'moving':
        return Icons.directions_transit_rounded;
      case 'sightseeing':
        return Icons.photo_camera_rounded;
      case 'shopping':
        return Icons.shopping_bag_rounded;
      case 'entertainment':
        return Icons.local_activity_rounded;
      case 'event':
        return Icons.event_rounded;
      case 'sport':
        return Icons.sports_rounded;
      case 'study':
        return Icons.school_rounded;
      case 'work':
        return Icons.work_outline_rounded;
      default:
        return Icons.place_rounded;
    }
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
      builder: (_) =>
          AppLoading(message: context.l10n.t('common.loading_session')),
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
          onEdit: canEdit
              ? () => _openEditActivity(context, ref, fullActivity)
              : null,
          onDelete: canEdit
              ? () => _deleteActivity(context, ref, fullActivity)
              : null,
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
              params: {
                'error': ErrorDisplayService.getUserFriendlyMessage(error),
              },
            ),
          ),
          backgroundColor: AppColors.warning,
        ),
      );
    }
  }

  Future<void> _openCreateActivity(BuildContext context, WidgetRef ref) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ActivityFormPage(planId: planId, planTitle: planTitle),
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
          backgroundColor: AppColors.success,
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
              params: {
                'error': ErrorDisplayService.getUserFriendlyMessage(error),
              },
            ),
          ),
          backgroundColor: AppColors.error,
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JourneySectionHeader(
            title: context.l10n.t('schedule.stats_title'),
            icon: Icons.route_rounded,
          ),
          const SizedBox(height: AppSpacing.sm),
          JourneyMetricStrip(
            metrics: [
              JourneyMetricData(
                label: context.l10n.t('plan.activities'),
                value: '${statistics!['total_activities'] ?? 0}',
                icon: Icons.event_note_rounded,
              ),
              JourneyMetricData(
                label: context.l10n.t('activity_details.completed'),
                value: '${statistics!['completed_activities'] ?? 0}',
                icon: Icons.check_circle_outline_rounded,
                emphasis: true,
              ),
              JourneyMetricData(
                label: context.l10n.t('analytics.metric.plan_completion_rate'),
                value:
                    '${((statistics!['completion_rate'] as num?) ?? 0).toStringAsFixed(1)}%',
                icon: Icons.donut_large_rounded,
              ),
              JourneyMetricData(
                label: context.l10n.t('activity_details.time'),
                value:
                    statistics!['total_duration_display']?.toString() ?? '0m',
                icon: Icons.schedule_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScheduleMapPane extends StatefulWidget {
  const _ScheduleMapPane({
    required this.activities,
    required this.selectedId,
    required this.onSelect,
  });

  final List<PlanActivity> activities;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  State<_ScheduleMapPane> createState() => _ScheduleMapPaneState();
}

class _ScheduleMapPaneState extends State<_ScheduleMapPane> {
  PlanPalMapController? _controller;

  PlanActivity get _selected {
    for (final activity in widget.activities) {
      if (activity.id == widget.selectedId) return activity;
    }
    return widget.activities.first;
  }

  @override
  void didUpdateWidget(covariant _ScheduleMapPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedId != widget.selectedId) _focusSelected();
  }

  Future<void> _focusSelected() async {
    final activity = _selected;
    final latitude = activity.latitude;
    final longitude = activity.longitude;
    if (latitude == null || longitude == null) return;
    await _controller?.animateCamera(
      MapCameraUpdate.newCoordinateZoom(
        MapCoordinate(latitude, longitude),
        14.5,
      ),
    );
  }

  void _move(int delta) {
    final current = widget.activities.indexWhere(
      (activity) => activity.id == _selected.id,
    );
    final target = (current + delta)
        .clamp(0, widget.activities.length - 1)
        .toInt();
    widget.onSelect(widget.activities[target].id);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final pins = widget.activities
        .map(
          (activity) => MapPin(
            id: activity.id,
            position: MapCoordinate(activity.latitude!, activity.longitude!),
            title: activity.title,
            subtitle: activity.locationName,
          ),
        )
        .toSet();
    return Stack(
      children: [
        Positioned.fill(
          child: PlanPalMap(
            initialCameraPosition: MapCameraPosition(
              target: MapCoordinate(selected.latitude!, selected.longitude!),
              zoom: 13.5,
            ),
            pins: pins,
            onMapCreated: (controller) {
              _controller = controller;
              _focusSelected();
            },
          ),
        ),
        Positioned(
          top: AppSpacing.md,
          left: AppSpacing.md,
          right: AppSpacing.md,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: .94),
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.map_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      context.l10n.t('plan.itinerary_map'),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    context.l10n.t(
                      'plan.mapped_places',
                      params: {'count': '${widget.activities.length}'},
                    ),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: AppSpacing.md,
          right: AppSpacing.md,
          bottom: AppSpacing.md,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: .96),
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(
                    context,
                  ).colorScheme.shadow.withValues(alpha: .12),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                children: [
                  IconButton(
                    tooltip: context.l10n.t('plan.previous_place'),
                    onPressed: widget.activities.first.id == selected.id
                        ? null
                        : () => _move(-1),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selected.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          selected.locationName ??
                              selected.locationAddress ??
                              '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.t('plan.next_place'),
                    onPressed: widget.activities.last.id == selected.id
                        ? null
                        : () => _move(1),
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final PlanActivity activity;
  final ActivityRealtimeHighlight? highlight;
  final VoidCallback onTap;
  final bool selected;

  const _ActivityCard({
    required this.activity,
    required this.onTap,
    this.selected = false,
    this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    return JourneySurface(
      onTap: onTap,
      selected: selected || highlight != null,
      semanticLabel: activity.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          if (highlight != null) ...[
            const SizedBox(height: AppSpacing.xs),
            _buildRealtimeNote(context),
          ],
          const SizedBox(height: AppSpacing.xs),
          _buildTitle(context),
          if (activity.description != null &&
              activity.description!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            _buildDescription(context),
          ],
          const SizedBox(height: AppSpacing.sm),
          _buildInfoRow(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
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
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.check_circle,
              color: AppColors.success,
              size: 16,
            ),
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
            params: {
              'fields': fields.isEmpty ? context.l10n.t('common.edit') : fields,
            },
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

  Widget _buildTitle(BuildContext context) {
    return Text(
      activity.title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w800,
        decoration: activity.isCompleted ? TextDecoration.lineThrough : null,
        color: activity.isCompleted
            ? Theme.of(context).colorScheme.onSurfaceVariant
            : null,
      ),
    );
  }

  Widget _buildDescription(BuildContext context) {
    return Text(
      activity.description!,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildInfoRow(BuildContext context) {
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
          _buildInfoChip(Icons.timer, '${activity.durationMinutes}m'),
      ],
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Color _getActivityTypeColor(String activityType) {
    switch (activityType) {
      case 'eating':
        return AppColors.accent;
      case 'resting':
        return AppColors.info;
      case 'moving':
        return AppColors.secondary;
      case 'sightseeing':
        return AppColors.success;
      case 'shopping':
        return AppColors.warning;
      case 'entertainment':
        return AppColors.accentDark;
      case 'event':
        return AppColors.primary;
      case 'sport':
        return AppColors.secondaryDark;
      case 'study':
        return AppColors.warning;
      case 'work':
        return AppColors.neutral600;
      default:
        return AppColors.neutral600;
    }
  }
}
