import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planpal_flutter/core/dtos/group_summary.dart';
import 'package:planpal_flutter/core/dtos/plan_summary.dart';
import 'package:planpal_flutter/core/localization/app_formatters.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/providers.dart';
import 'package:planpal_flutter/core/responsive/app_breakpoints.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:planpal_flutter/core/theme/app_design_tokens.dart';
import 'package:planpal_flutter/presentation/pages/users/plan_form_page.dart';
import 'package:planpal_flutter/presentation/widgets/common/refreshable_page_wrapper.dart';
import 'package:planpal_flutter/presentation/widgets/design_system/journey_ui.dart';
import 'package:planpal_flutter/presentation/widgets/design_system/planpal_brand.dart';
import 'package:planpal_flutter/presentation/widgets/layout/responsive_content.dart';
import 'package:planpal_flutter/shared/ui_states/ui_states.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _HomeContent(key: ValueKey('home_content'));
  }
}

class _HomeContent extends ConsumerStatefulWidget {
  const _HomeContent({super.key});

  @override
  ConsumerState<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends ConsumerState<_HomeContent>
    with RefreshablePage {
  @override
  Future<void> onRefresh() async {
    ref.invalidate(plansNotifierProvider);
    ref.invalidate(groupsNotifierProvider);
    ref.invalidate(conversationListProvider);
    ref.invalidate(unreadCountProvider);
  }

  Future<void> _handleQuickCreatePlan() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const PlanFormPage()),
    );
    if (!mounted) return;
    if (result != null &&
        result['action'] == 'created' &&
        result['plan'] != null) {
      try {
        final map = Map<String, dynamic>.from(result['plan'] as Map);
        final summary = PlanSummary.fromJson(map);
        ref.read(plansNotifierProvider.notifier).addPlan(summary);
      } catch (_) {
        // Ignore malformed return payload.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final plansAsync = ref.watch(plansNotifierProvider);
    final groupsAsync = ref.watch(groupsNotifierProvider);
    final unreadCount = ref.watch(unreadCountProvider).valueOrNull ?? 0;
    final l10n = context.l10n;

    final isLoading = plansAsync.isLoading || groupsAsync.isLoading;
    final error = plansAsync.error ?? groupsAsync.error;
    final recentPlans = (plansAsync.valueOrNull?.items ?? []).take(5).toList();
    final activeGroups = (groupsAsync.valueOrNull ?? []).take(5).toList();
    final nextTrip = _findNextTrip(recentPlans);
    final otherPlans = recentPlans
        .where((plan) => plan.id != nextTrip?.id)
        .toList();

    return Scaffold(
      body: RefreshablePageWrapper(
        onRefresh: onRefresh,
        child: CustomScrollView(
          slivers: [
            _buildSliverAppBar(context),
            SliverToBoxAdapter(
              child: ResponsiveContent(
                expandedMaxWidth: 1240,
                compactPadding: const EdgeInsets.all(16),
                mediumPadding: const EdgeInsets.all(24),
                expandedPadding: const EdgeInsets.all(32),
                child: isLoading && recentPlans.isEmpty && activeGroups.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.only(top: 24, bottom: 80),
                        child: AppSkeleton.list(itemCount: 4),
                      )
                    : error != null && recentPlans.isEmpty
                    ? AppError(
                        message: ErrorDisplayService.getUserFriendlyMessage(
                          error,
                        ),
                        onRetry: () async => onRefresh(),
                        retryLabel: l10n.t('common.retry'),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildGreetingSection(context),
                          const _OfflineSyncStatus(),
                          const SizedBox(height: 24),
                          if (AppBreakpoints.isExpanded(context) &&
                              nextTrip != null)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: _buildNextAdventure(context, nextTrip),
                                ),
                                if (unreadCount > 0) ...[
                                  const SizedBox(width: AppSpacing.lg),
                                  Expanded(
                                    child: _buildAttentionCard(
                                      context,
                                      unreadCount,
                                    ),
                                  ),
                                ],
                              ],
                            )
                          else ...[
                            if (nextTrip != null)
                              _buildNextAdventure(context, nextTrip),
                            if (unreadCount > 0) ...[
                              const SizedBox(height: AppSpacing.lg),
                              _buildAttentionCard(context, unreadCount),
                            ],
                          ],
                          const SizedBox(height: 24),
                          if (AppBreakpoints.isExpanded(context))
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _buildRecentPlans(context, otherPlans),
                                ),
                                const SizedBox(width: 24),
                                Expanded(
                                  child: _buildActiveGroups(
                                    context,
                                    activeGroups,
                                  ),
                                ),
                              ],
                            )
                          else ...[
                            _buildRecentPlans(context, otherPlans),
                            const SizedBox(height: 24),
                            _buildActiveGroups(context, activeGroups),
                          ],
                          const SizedBox(height: 100),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      automaticallyImplyLeading: false,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      title: PlanPalLogo(
        height: 38,
        onTap: () => context.go(kIsWeb ? '/' : '/welcome'),
      ),
      actions: [
        if (AppBreakpoints.isCompact(context))
          IconButton(
            tooltip: context.l10n.t('home.conversations'),
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            onPressed: () => context.push('/conversations'),
          ),
        IconButton(
          tooltip: context.l10n.t('search.title'),
          icon: const Icon(Icons.search),
          onPressed: () => context.push('/explore'),
        ),
        Consumer(
          builder: (context, ref, child) {
            final unreadCount = ref.watch(unreadCountProvider).valueOrNull ?? 0;
            return IconButton(
              icon: _buildNotificationBadge(
                child: const Icon(Icons.notifications_none),
                count: unreadCount,
                badgeColor: AppColors.error,
              ),
              onPressed: () => context.push('/notifications'),
            );
          },
        ),
      ],
    );
  }

  PlanSummary? _findNextTrip(List<PlanSummary> plans) {
    for (final plan in plans) {
      if (plan.isOngoing || plan.isUpcoming) return plan;
    }
    return plans.isEmpty ? null : plans.first;
  }

  Widget _buildAttentionCard(BuildContext context, int unreadCount) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        JourneySectionHeader(
          title: context.l10n.t('home.needs_attention'),
          icon: Icons.notifications_active_outlined,
        ),
        const SizedBox(height: AppSpacing.sm),
        JourneySurface(
          semanticLabel: context.l10n.t('home.review_updates'),
          onTap: () => context.push('/notifications'),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.tertiaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: Icon(
                  Icons.mark_email_unread_outlined,
                  color: colors.onTertiaryContainer,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.t(
                        'home.unread_updates',
                        params: {'count': unreadCount.toString()},
                      ),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      context.l10n.t('home.review_updates'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNextAdventure(BuildContext context, PlanSummary plan) {
    final theme = Theme.of(context);
    // Keep the trip hero readable independently from the dynamic scheme's
    // primary/onPrimary pair. In particular, light themes must not render a
    // pale primary surface with white trip details.
    final heroBackground = theme.brightness == Brightness.dark
        ? AppColors.oceanTeal
        : AppColors.primaryDark;
    const heroForeground = Colors.white;
    final heroMutedForeground = heroForeground.withValues(alpha: .82);
    final now = DateTime.now();
    final departure = plan.startDate;
    final daysUntilDeparture = departure == null
        ? null
        : DateTime(
            departure.year,
            departure.month,
            departure.day,
          ).difference(DateTime(now.year, now.month, now.day)).inDays;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        JourneySectionHeader(
          title: context.l10n.t('home.next_adventure'),
          icon: Icons.explore_outlined,
        ),
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          button: true,
          label: plan.title,
          child: Material(
            color: heroBackground,
            borderRadius: BorderRadius.circular(AppRadius.sheet),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => context.push('/plans/${plan.id}'),
              child: JourneyPathBackdrop(
                color: heroForeground,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  plan.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(
                                        color: heroForeground,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                if (plan.groupName?.isNotEmpty == true) ...[
                                  const SizedBox(height: AppSpacing.xxs),
                                  Text(
                                    plan.groupName!,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: heroMutedForeground,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (daysUntilDeparture != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xs,
                              ),
                              decoration: BoxDecoration(
                                color: heroForeground.withValues(alpha: .16),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.control,
                                ),
                              ),
                              child: Text(
                                daysUntilDeparture <= 0
                                    ? context.l10n.t('home.departure_today')
                                    : context.l10n.t(
                                        'home.days_to_go',
                                        params: {
                                          'count': daysUntilDeparture
                                              .toString(),
                                        },
                                      ),
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: heroForeground,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_month_outlined,
                            size: 18,
                            color: heroForeground,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              _tripDateLabel(context, plan),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: heroForeground,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            context.l10n.t(
                              'home.activity_progress',
                              params: {
                                'count': plan.activitiesCount.toString(),
                              },
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: heroMutedForeground,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 17,
                            backgroundColor: heroForeground,
                            foregroundColor: heroBackground,
                            backgroundImage:
                                plan.creator.avatarUrl?.isNotEmpty == true
                                ? CachedNetworkImageProvider(
                                    plan.creator.avatarUrl!,
                                  )
                                : null,
                            child: plan.creator.avatarUrl?.isNotEmpty == true
                                ? null
                                : Text(plan.creator.initials),
                          ),
                          const Spacer(),
                          Text(
                            context.l10n.t('home.continue_planning'),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: heroForeground,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                            color: heroForeground,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _tripDateLabel(BuildContext context, PlanSummary plan) {
    if (plan.startDate == null) return context.l10n.t('plan.no_date');
    final start = AppFormatters.shortDate(context, plan.startDate!);
    if (plan.endDate == null) return start;
    return '$start - ${AppFormatters.shortDate(context, plan.endDate!)}';
  }

  Widget _buildGreetingSection(BuildContext context) {
    final hour = DateTime.now().hour;
    final l10n = context.l10n;
    late final String greeting;
    late final IconData greetingIcon;

    if (hour < 12) {
      greeting = l10n.t('home.greeting_morning');
      greetingIcon = Icons.wb_sunny;
    } else if (hour < 17) {
      greeting = l10n.t('home.greeting_afternoon');
      greetingIcon = Icons.wb_sunny_outlined;
    } else {
      greeting = l10n.t('home.greeting_evening');
      greetingIcon = Icons.nights_stay;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Icon(
            greetingIcon,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                l10n.t('home.ready_for_trip'),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecentPlans(
    BuildContext context,
    List<PlanSummary> recentPlans,
  ) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.t('home.recent_plans'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () => context.push('/plans'),
              child: Text(l10n.t('common.view_all')),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (recentPlans.isEmpty)
          AppEmpty(
            icon: Icons.event_busy,
            title: l10n.t('home.no_plans_title'),
            description: l10n.t('home.no_plans_description'),
            actionLabel: l10n.t('home.create_plan'),
            onAction: _handleQuickCreatePlan,
          )
        else
          SizedBox(
            height: 180,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: recentPlans.length,
              itemBuilder: (context, index) {
                final plan = recentPlans[index];
                return _buildPlanCardItem(
                  context,
                  index,
                  plan,
                  totalCount: recentPlans.length,
                  onTap: () => _openRecentPlan(plan),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildActiveGroups(
    BuildContext context,
    List<GroupSummary> activeGroups,
  ) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.t('home.active_groups'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () => context.push('/groups'),
              child: Text(l10n.t('common.view_all')),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (activeGroups.isEmpty)
          AppEmpty(
            icon: Icons.groups_outlined,
            title: l10n.t('home.no_groups_title'),
            description: l10n.t('home.no_groups_description'),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: activeGroups.length,
            itemBuilder: (context, index) {
              final group = activeGroups[index];
              return _buildGroupCardItem(
                context,
                index,
                group,
                onTap: () {
                  if (group.id.isNotEmpty) context.push('/groups/${group.id}');
                },
              );
            },
          ),
      ],
    );
  }

  Future<void> _openRecentPlan(PlanSummary plan) async {
    final id = plan.id;
    if (id.isEmpty) return;

    final result = await context.push<Map<String, dynamic>>('/plans/$id');
    if (!mounted || result == null) return;

    if (result['action'] == 'delete' && result['id'] == id) {
      ref.read(plansNotifierProvider.notifier).removePlan(id);
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
        // Ignore malformed return payload.
      }
    }
  }

  Widget _buildPlanCardItem(
    BuildContext context,
    int index,
    PlanSummary plan, {
    required int totalCount,
    VoidCallback? onTap,
  }) {
    final colors = AppColors.cardColors;
    final color = colors[index % colors.length];
    final name = plan.title.isNotEmpty
        ? plan.title
        : context.l10n.t('home.plans');

    return Container(
      width: 280,
      margin: EdgeInsets.only(right: index == totalCount - 1 ? 0 : 16),
      child: JourneySurface(
        onTap: onTap,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.near_me_outlined, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (plan.startDate != null || plan.endDate != null)
                        Text(
                          _tripDateLabel(context, plan),
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
              ],
            ),
            const SizedBox(height: 12),
            if (plan.groupName != null && plan.groupName!.isNotEmpty)
              Text(
                context.l10n.t(
                  'home.group_prefix',
                  params: {'group': plan.groupName!},
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const Spacer(),
            JourneyRouteProgress(
              completedStops: plan.isCompleted
                  ? 3
                  : plan.isOngoing
                  ? 2
                  : plan.isUpcoming
                  ? 1
                  : 0,
              color: color,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.route_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  context.l10n.t(
                    'home.activity_progress',
                    params: {'count': plan.activitiesCount.toString()},
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: plan.isUpcoming
                        ? AppColors.warning.withValues(alpha: 0.1)
                        : plan.isOngoing
                        ? AppColors.success.withValues(alpha: 0.1)
                        : AppColors.info.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    plan.statusDisplay,
                    style: TextStyle(
                      color: plan.isUpcoming
                          ? AppColors.warning
                          : plan.isOngoing
                          ? AppColors.success
                          : AppColors.info,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupCardItem(
    BuildContext context,
    int index,
    GroupSummary group, {
    VoidCallback? onTap,
  }) {
    final colors = AppColors.cardColors;
    final color = colors[index % colors.length];
    final name = group.name.isNotEmpty
        ? group.name
        : context.l10n.t('home.groups');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: JourneySurface(
        onTap: onTap,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: group.avatarForDisplay.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: group.avatarForDisplay,
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            Icon(Icons.group, color: color, size: 24),
                        errorWidget: (context, url, error) =>
                            Icon(Icons.group, color: color, size: 24),
                      ),
                    )
                  : Center(
                      child: Text(
                        group.initials,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    group.memberCountText,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const _ActiveDot(),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationBadge({
    required Widget child,
    required int count,
    Color badgeColor = AppColors.error,
  }) {
    return Stack(
      children: [
        child,
        if (count > 0)
          Positioned(
            right: 0,
            top: 0,
            child: AnimatedScale(
              scale: 1,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: badgeColor.withAlpha(75),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  count > 99 ? '99+' : count.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _OfflineSyncStatus extends ConsumerWidget {
  const _OfflineSyncStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingCount = ref.watch(
      offlineSyncProvider.select((service) => service.pendingCount),
    );
    final isSyncing = ref.watch(
      offlineSyncProvider.select((service) => service.isSyncing),
    );
    if (pendingCount == 0) return const SizedBox.shrink();
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: ListTile(
          leading: isSyncing
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cloud_off_outlined),
          title: Text(
            l10n.t(
              'offline.pending_title',
              params: {'count': pendingCount.toString()},
            ),
          ),
          subtitle: Text(l10n.t('offline.pending_hint')),
          trailing: IconButton(
            tooltip: l10n.t('common.retry'),
            onPressed: isSyncing ? null : ref.read(offlineSyncProvider).flush,
            icon: const Icon(Icons.sync),
          ),
        ),
      ),
    );
  }
}

class _ActiveDot extends StatelessWidget {
  const _ActiveDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: AppColors.success,
        shape: BoxShape.circle,
      ),
    );
  }
}
