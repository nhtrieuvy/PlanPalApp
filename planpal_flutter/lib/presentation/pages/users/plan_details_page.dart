import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';
// ignore_for_file: use_build_context_synchronously
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:planpal_flutter/core/localization/app_formatters.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/theme/app_design_tokens.dart';
import '../../../core/dtos/plan_model.dart';
import '../../../core/dtos/plan_activity.dart';
import '../../../core/services/error_display_service.dart';
import '../../widgets/common/refreshable_page_wrapper.dart';
import '../../widgets/audit/audit_log_list.dart';
import '../../widgets/layout/responsive_content.dart';
import '../../widgets/design_system/journey_ui.dart';
import '../../../shared/ui_states/ui_states.dart';
import '../../../shared/widgets/widgets.dart';
import '../plans/activity_form_page.dart';
import '../plans/plan_schedule_page.dart';
import '../budget/budget_overview_page.dart';
import 'package:planpal_flutter/presentation/pages/users/plan_form_page.dart';
import 'package:planpal_flutter/core/riverpod/collaboration_providers.dart';
import 'package:planpal_flutter/presentation/pages/collaboration/plan_collaboration_page.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:planpal_flutter/core/files/safe_file_name.dart';

class PlanDetailsPage extends ConsumerStatefulWidget {
  final String id;
  const PlanDetailsPage({super.key, required this.id});

  @override
  ConsumerState<PlanDetailsPage> createState() => _PlanDetailsPageState();
}

enum _TripDetailSection { overview, itinerary, decisions, more }

class _TripDetailSectionBar extends StatelessWidget {
  const _TripDetailSectionBar({
    required this.selected,
    required this.onSelected,
  });

  final _TripDetailSection selected;
  final ValueChanged<_TripDetailSection> onSelected;

  @override
  Widget build(BuildContext context) {
    final items = <(_TripDetailSection, IconData, String)>[
      (
        _TripDetailSection.overview,
        Icons.explore_outlined,
        context.l10n.t('plan.section_overview'),
      ),
      (
        _TripDetailSection.itinerary,
        Icons.route_outlined,
        context.l10n.t('plan.section_itinerary'),
      ),
      (
        _TripDetailSection.decisions,
        Icons.how_to_vote_outlined,
        context.l10n.t('plan.section_decisions'),
      ),
      (
        _TripDetailSection.more,
        Icons.more_horiz_rounded,
        context.l10n.t('plan.section_more'),
      ),
    ];

    return Semantics(
      label: context.l10n.t('plan.trip_sections'),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<_TripDetailSection>(
          showSelectedIcon: false,
          segments: [
            for (final item in items)
              ButtonSegment<_TripDetailSection>(
                value: item.$1,
                icon: Icon(item.$2, size: 18),
                label: Text(item.$3),
              ),
          ],
          selected: {selected},
          onSelectionChanged: (value) => onSelected(value.first),
        ),
      ),
    );
  }
}

class _PlanDetailsPageState extends ConsumerState<PlanDetailsPage>
    with RefreshablePage<PlanDetailsPage> {
  PlanModel? _detail;
  Object? _error;
  bool _loading = true;
  _TripDetailSection _selectedSection = _TripDetailSection.overview;

  @override
  void initState() {
    super.initState();
    // If id is empty, avoid calling the list endpoint accidentally and show an error
    if (widget.id.isEmpty) {
      _loading = false;
      _error = 'Plan id is empty';
      return;
    }

    _load();
  }

  @override
  Future<void> onRefresh() async {
    await _load(refresh: true);
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(planRepositoryProvider);
      if (refresh) repo.clearCacheEntry(widget.id);
      final d = await repo.getPlanDetail(widget.id);
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

  Future<void> _confirmCancelPlan(PlanModel plan) async {
    if (!plan.isUpcoming) {
      ErrorDisplayService.showErrorSnackbar(
        context,
        context.l10n.t('plan.cancel_unavailable'),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.t('plan.cancel_title')),
        content: Text(
          context.l10n.t('plan.cancel_confirm', params: {'title': plan.title}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.t('common.cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.t('plan.cancel_plan')),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final updated = await ref
          .read(planRepositoryProvider)
          .cancelPlan(plan.id);
      if (!mounted) return;
      setState(() {
        _detail = updated;
      });
      ErrorDisplayService.showSuccessSnackbar(
        context,
        context.l10n.t('plan.cancelled_success'),
      );
      Navigator.of(
        context,
      ).pop({'action': 'updated', 'plan': updated.toJson()});
    } catch (e) {
      if (!mounted) return;
      ErrorDisplayService.handleError(context, e, showDialog: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.t('plan.details_title')),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        body: const AppSkeleton.card(),
      );
    }
    if (_error != null || _detail == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.t('plan.details_title')),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        body: AppError(
          message: _error == null
              ? context.l10n.t('plan.details_title')
              : ErrorDisplayService.getUserFriendlyMessage(_error),
          onRetry: _load,
          retryLabel: context.l10n.t('common.retry'),
        ),
      );
    }

    final p = _detail!;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: NestedScrollView(
        headerSliverBuilder: (context, inner) => [
          AppSliverHeader(
            title: p.title,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                onPressed: () => _navigateToSchedule(p.id),
                tooltip: context.l10n.t('plan.schedule_tooltip'),
                icon: const Icon(Icons.route_rounded),
              ),
              PopupMenuButton<String>(
                onSelected: (value) => _handlePlanningAction(value, p),
                itemBuilder: (context) => [
                  if (p.canEdit)
                    PopupMenuItem(
                      value: 'clone',
                      child: ListTile(
                        leading: const Icon(Icons.copy_all_outlined),
                        title: Text(context.l10n.t('collaboration.clone_plan')),
                      ),
                    ),
                  if (p.canEdit)
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(
                          Icons.delete_outline_rounded,
                          color: theme.colorScheme.error,
                        ),
                        title: Text(
                          context.l10n.t('plan.delete'),
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ),
                  PopupMenuItem(
                    value: 'ics',
                    child: ListTile(
                      leading: const Icon(Icons.file_download_outlined),
                      title: Text(context.l10n.t('collaboration.export_ics')),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'google',
                    child: ListTile(
                      leading: const Icon(Icons.event_outlined),
                      title: Text(
                        context.l10n.t('collaboration.google_calendar'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            background: JourneyPathBackdrop(
              color: Colors.white,
              child: ColoredBox(
                color: AppColors.primary,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 28, 28, 54),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (p.groupName?.isNotEmpty == true) ...[
                            Text(
                              p.groupName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: Colors.white.withValues(alpha: .82),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                          JourneyRouteProgress(
                            completedStops: _journeyStage(p),
                            color: Colors.white,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            _tripDateLabel(context, p),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: .9),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        body: RefreshablePageWrapper(
          onRefresh: onRefresh,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ResponsiveContent(
              mediumMaxWidth: 820,
              expandedMaxWidth: 1120,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TripDetailSectionBar(
                    selected: _selectedSection,
                    onSelected: (section) =>
                        setState(() => _selectedSection = section),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_selectedSection == _TripDetailSection.overview) ...[
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final creator = _buildCreatorCard(
                          p.creator.avatarForDisplay,
                          (p.creator.fullName.isNotEmpty
                              ? p.creator.fullName
                              : p.creator.username),
                        );
                        final metadata = _buildMetaCard(
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
                        );
                        if (constraints.maxWidth >= 760) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: creator),
                              const SizedBox(width: 16),
                              Expanded(flex: 2, child: metadata),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            creator,
                            const SizedBox(height: 16),
                            metadata,
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.success.withAlpha(20),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.account_balance_wallet_rounded,
                                color: AppColors.success,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.l10n.t('plan.budget_card_title'),
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    context.l10n.t(
                                      'plan.budget_card_description',
                                    ),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton(
                              onPressed: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => BudgetOverviewPage(
                                      planId: p.id,
                                      planTitle: p.title,
                                      canManageBudget: p.canEdit,
                                    ),
                                  ),
                                );
                                if (!mounted) return;
                                await _load(refresh: true);
                              },
                              child: Text(context.l10n.t('common.open')),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (p.description != null && p.description!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildInfoCard(
                        icon: Icons.description,
                        title: context.l10n.t('plan.description'),
                        subtitle: p.description!,
                        color: AppColors.primary,
                        theme: theme,
                      ),
                    ],
                    if (p.startDate != null || p.endDate != null) ...[
                      const SizedBox(height: 16),
                      Card(
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
                                    context.l10n.t('plan.time'),
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              if (p.startDate != null)
                                _buildDateRow(
                                  icon: Icons.play_arrow,
                                  label: context.l10n.t('plan.start'),
                                  date: AppFormatters.fullDateTime(
                                    context,
                                    p.startDate!,
                                  ),
                                  theme: theme,
                                ),
                              if (p.startDate != null && p.endDate != null)
                                const SizedBox(height: 12),
                              if (p.endDate != null)
                                _buildDateRow(
                                  icon: Icons.stop,
                                  label: context.l10n.t('plan.end'),
                                  date: AppFormatters.fullDateTime(
                                    context,
                                    p.endDate!,
                                  ),
                                  theme: theme,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                  if (_selectedSection == _TripDetailSection.itinerary) ...[
                    JourneySectionHeader(
                      title: context.l10n.t('plan.section_itinerary'),
                      subtitle: context.l10n.t('plan.itinerary_hint'),
                      icon: Icons.route_outlined,
                      trailing: TextButton.icon(
                        onPressed: () => _navigateToSchedule(p.id),
                        icon: const Icon(Icons.map_outlined),
                        label: Text(context.l10n.t('plan.open_schedule_map')),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (p.activities.isNotEmpty)
                      _buildActivitiesCard(
                        theme: theme,
                        activities: p.activities,
                      )
                    else
                      AppEmpty(
                        icon: Icons.route_outlined,
                        title: context.l10n.t('plan.no_activities'),
                        description: context.l10n.t(
                          'plan.no_activities_description',
                        ),
                        actionLabel: context.l10n.t(
                          'plan.add_activity_tooltip',
                        ),
                        onAction: () => _navigateToCreateActivity(p.id),
                      ),
                  ],
                  if (_selectedSection == _TripDetailSection.decisions) ...[
                    JourneySectionHeader(
                      title: context.l10n.t('plan.section_decisions'),
                      subtitle: context.l10n.t('collaboration.plan_subtitle'),
                      icon: Icons.how_to_vote_outlined,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    JourneySurface(
                      padding: EdgeInsets.zero,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PlanCollaborationPage(plan: p),
                        ),
                      ),
                      child: ListTile(
                        leading: Icon(
                          Icons.groups_2_outlined,
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(context.l10n.t('collaboration.title')),
                        subtitle: Text(
                          context.l10n.t('plan.decisions_description'),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                      ),
                    ),
                  ],
                  if (_selectedSection == _TripDetailSection.more) ...[
                    JourneySectionHeader(
                      title: context.l10n.t('plan.section_more'),
                      subtitle: context.l10n.t('plan.more_hint'),
                      icon: Icons.tune_rounded,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AuditLogList(
                      title: context.l10n.t('plan.audit_log_title'),
                      resourceType: 'plan',
                      resourceId: p.id,
                    ),
                    if (p.canEdit && p.isUpcoming) ...[
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _confirmCancelPlan(p),
                          icon: const Icon(Icons.cancel_outlined),
                          label: Text(context.l10n.t('plan.cancel_plan')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                            side: BorderSide(color: theme.colorScheme.error),
                          ),
                        ),
                      ),
                    ],
                    if (p.canEdit) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                // Edit button: open edit form and refresh details on success
                                final result = await Navigator.of(context)
                                    .push<Map<String, dynamic>>(
                                      MaterialPageRoute(
                                        builder: (context) => PlanFormPage(
                                          initial: {
                                            'id': p.id,
                                            'title': p.title,
                                            'description': p.description,
                                            'start_date': p.startDate
                                                ?.toIso8601String(),
                                            'end_date': p.endDate
                                                ?.toIso8601String(),
                                            'is_public': p.isPublic,
                                            'plan_type': p.planType,
                                            'group_id': p.group?.id,
                                          },
                                        ),
                                      ),
                                    );
                                if (result != null &&
                                    result['action'] == 'updated') {
                                  // reload details from API and return updated result to caller
                                  await _load(refresh: true);
                                  if (!mounted) return;
                                  ErrorDisplayService.showSuccessSnackbar(
                                    context,
                                    context.l10n.t('plan.updated_success'),
                                  );
                                  Navigator.of(context).pop({
                                    'action': 'updated',
                                    'plan': result['plan'],
                                  });
                                  return;
                                }
                              },
                              icon: const Icon(Icons.edit_outlined),
                              label: Text(context.l10n.t('plan.edit')),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _confirmDeletePlan(p),
                              icon: const Icon(Icons.delete_outline),
                              label: Text(context.l10n.t('plan.delete')),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: theme.colorScheme.error,
                                side: BorderSide(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: _selectedSection == _TripDetailSection.itinerary
          ? FloatingActionButton.extended(
              onPressed: () => _navigateToCreateActivity(p.id),
              heroTag: 'add_activity',
              tooltip: context.l10n.t('plan.add_activity_tooltip'),
              icon: const Icon(Icons.add_rounded),
              label: Text(context.l10n.t('plan.add_activity_tooltip')),
            )
          : null,
    );
  }

  void _navigateToCreateActivity(String planId) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) => ActivityFormPage(
              planId: planId,
              planTitle:
                  _detail?.title ?? context.l10n.t('plan.plan_fallback_title'),
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

  String _tripDateLabel(BuildContext context, PlanModel plan) {
    final start = plan.startDate;
    final end = plan.endDate;
    if (start != null && end != null) {
      return '${AppFormatters.shortDate(context, start)} - '
          '${AppFormatters.shortDate(context, end)}';
    }
    if (start != null) return AppFormatters.shortDate(context, start);
    if (end != null) return AppFormatters.shortDate(context, end);
    return context.l10n.t('plan.no_date');
  }

  int _journeyStage(PlanModel plan) {
    if (plan.status == 'completed') return 3;
    if (plan.status == 'ongoing' || plan.status == 'active') return 2;
    if (plan.status == 'upcoming') return 1;
    return 0;
  }

  void _navigateToSchedule(String planId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PlanSchedulePage(
          planId: planId,
          planTitle:
              _detail?.title ?? context.l10n.t('plan.schedule_fallback_title'),
        ),
      ),
    );
  }

  Future<void> _handlePlanningAction(String action, PlanModel plan) async {
    if (action == 'clone') {
      await _clonePlan(plan);
    } else if (action == 'delete') {
      await _confirmDeletePlan(plan);
    } else if (action == 'ics') {
      await _shareIcs(plan);
    } else if (action == 'google') {
      await _showCalendarLinks(plan);
    }
  }

  Future<void> _confirmDeletePlan(PlanModel plan) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.t('plan.delete_title')),
        content: Text(
          context.l10n.t('plan.delete_confirm', params: {'title': plan.title}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.t('common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.t('plan.delete')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await ref.read(planRepositoryProvider).deletePlan(plan.id);
      if (!mounted) return;
      ErrorDisplayService.showSuccessSnackbar(
        context,
        context.l10n.t('plan.deleted_success'),
      );
      Navigator.of(context).pop({'action': 'delete', 'id': plan.id});
    } catch (error) {
      if (!mounted) return;
      ErrorDisplayService.handleError(context, error, showDialog: true);
    }
  }

  Future<void> _clonePlan(PlanModel plan) async {
    final title = TextEditingController(
      text: '${plan.title} - ${context.l10n.t('collaboration.copy')}',
    );
    DateTime start = (plan.startDate ?? DateTime.now()).add(
      const Duration(days: 7),
    );
    var asTemplate = false;
    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.l10n.t('collaboration.clone_plan')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: InputDecoration(
                    labelText: context.l10n.t('plan.title'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event),
                  title: Text(AppFormatters.fullDateTime(context, start)),
                  onTap: () async {
                    final selected = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 1460)),
                      initialDate: start,
                    );
                    if (selected != null) {
                      setDialogState(
                        () => start = DateTime(
                          selected.year,
                          selected.month,
                          selected.day,
                          start.hour,
                          start.minute,
                        ),
                      );
                    }
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: asTemplate,
                  onChanged: (value) =>
                      setDialogState(() => asTemplate = value),
                  title: Text(context.l10n.t('collaboration.save_as_template')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.l10n.t('common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(context.l10n.t('collaboration.clone')),
            ),
          ],
        ),
      ),
    );
    if (submit != true || title.text.trim().isEmpty || !mounted) {
      title.dispose();
      return;
    }
    try {
      final cloned = await ref
          .read(collaborationRepositoryProvider)
          .clonePlan(
            plan.id,
            title: title.text.trim(),
            startDate: start,
            asTemplate: asTemplate,
          );
      if (!mounted) return;
      ErrorDisplayService.showSuccessSnackbar(
        context,
        context.l10n.t('collaboration.clone_success'),
      );
      await context.push('/plans/${cloned.id}');
    } catch (error) {
      if (mounted) ErrorDisplayService.handleError(context, error);
    } finally {
      title.dispose();
    }
  }

  Future<void> _shareIcs(PlanModel plan) async {
    try {
      final content = await ref
          .read(collaborationRepositoryProvider)
          .exportIcs(plan.id);
      await Share.shareXFiles([
        XFile.fromData(
          Uint8List.fromList(utf8.encode(content)),
          mimeType: 'text/calendar',
          name: '${safeFileName(plan.title, fallback: 'planpal-plan')}.ics',
        ),
      ], subject: plan.title);
    } catch (error) {
      if (mounted) ErrorDisplayService.handleError(context, error);
    }
  }

  Future<void> _showCalendarLinks(PlanModel plan) async {
    try {
      final links = await ref
          .read(collaborationRepositoryProvider)
          .getCalendarLinks(plan.id);
      if (!mounted) return;
      if (links.isEmpty) {
        ErrorDisplayService.showErrorSnackbar(
          context,
          context.l10n.t('collaboration.no_calendar_events'),
        );
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        builder: (sheetContext) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              context.l10n.t('collaboration.google_calendar'),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            for (final link in links)
              ListTile(
                leading: const Icon(Icons.event_available),
                title: Text(link['title']?.toString() ?? ''),
                trailing: const Icon(Icons.open_in_new),
                onTap: () async {
                  final uri = Uri.tryParse(link['url']?.toString() ?? '');
                  if (uri != null) {
                    final launched = await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                    if (!launched && mounted) {
                      ErrorDisplayService.showErrorSnackbar(
                        context,
                        context.l10n.t('common.open_link_failed'),
                      );
                    }
                  }
                },
              ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) ErrorDisplayService.handleError(context, error);
    }
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required ThemeData theme,
  }) {
    return InfoCard(
      icon: icon,
      title: title,
      content: subtitle,
      accentColor: color,
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
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Text(
          '$label:',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.onSurfaceVariant,
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
        statusColor = theme.colorScheme.onSurfaceVariant;
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
    final theme = Theme.of(context);
    return Card(
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
                          color: theme.colorScheme.surfaceContainerHighest,
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
                  Text(
                    context.l10n.t('plan.creator'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
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
                  context.l10n.t('plan.overview'),
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
                      ? context.l10n.t('plan.group_plan')
                      : context.l10n.t('plan.personal_plan'),
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
                  label: isPublic
                      ? context.l10n.t('plan.public')
                      : context.l10n.t('plan.private'),
                  icon: isPublic ? Icons.public : Icons.lock,
                  color: isPublic
                      ? AppColors.success
                      : theme.colorScheme.onSurfaceVariant,
                ),
                if (durationDisplay.isNotEmpty)
                  _buildChip(
                    label: durationDisplay,
                    icon: Icons.timelapse,
                    color: AppColors.info,
                  ),
                _buildChip(
                  label: context.l10n.t(
                    'plan.activities_count',
                    params: {'count': '$activitiesCount'},
                  ),
                  icon: Icons.list_alt,
                  color: AppColors.primary,
                ),
                if (totalEstimatedCost != null)
                  _buildChip(
                    label: context.l10n.t(
                      'plan.total_estimated',
                      params: {
                        'amount': _formatCurrency(context, totalEstimatedCost),
                      },
                    ),
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
  }) {
    final display = activities.take(5).toList();
    return Card(
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
                  context.l10n.t('plan.activities'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (display.isEmpty)
              Text(
                context.l10n.t('plan.no_activities'),
                style: theme.textTheme.bodyMedium,
              )
            else
              ...display.map((a) {
                final st = a.startTime;
                final et = a.endTime;
                final title = a.title;
                final type = a.activityType;
                String timeRange = '';
                if (st != null) {
                  timeRange = AppFormatters.fullDateTime(context, st);
                  if (et != null) {
                    timeRange +=
                        ' - ${AppFormatters.fullDateTime(context, et)}';
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
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            if (timeRange.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(
                                  timeRange,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
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
                child: OutlinedButton.icon(
                  onPressed: () => _navigateToSchedule(widget.id),
                  icon: const Icon(Icons.more_horiz, size: 16),
                  label: Text(
                    context.l10n.t(
                      'plan.view_more',
                      params: {
                        'count': '${activities.length - display.length}',
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _formatCurrency(BuildContext context, dynamic value) {
    if (value == null) return '';
    try {
      final num v = (value is num) ? value : num.parse(value.toString());
      return AppFormatters.currency(
        context,
        amount: v.toDouble(),
        currencyCode: 'VND',
      );
    } catch (_) {
      return value.toString();
    }
  }
}
