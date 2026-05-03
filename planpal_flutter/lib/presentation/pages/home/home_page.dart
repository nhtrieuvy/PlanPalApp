import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:getwidget/getwidget.dart';
import 'package:planpal_flutter/core/dtos/group_summary.dart';
import 'package:planpal_flutter/core/dtos/plan_summary.dart';
import 'package:planpal_flutter/core/localization/app_locale.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/providers.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:planpal_flutter/presentation/pages/chat/conversation_list_page.dart';
import 'package:planpal_flutter/presentation/pages/friends/friend_search_page.dart';
import 'package:planpal_flutter/presentation/pages/location/current_location_map_page.dart';
import 'package:planpal_flutter/presentation/pages/notifications/notification_list_page.dart';
import 'package:planpal_flutter/presentation/pages/users/group_details_page.dart';
import 'package:planpal_flutter/presentation/pages/users/plan_details_page.dart';
import 'package:planpal_flutter/presentation/pages/users/plan_form_page.dart';
import 'package:planpal_flutter/presentation/widgets/common/refreshable_page_wrapper.dart';
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
    final l10n = context.l10n;

    final isLoading = plansAsync.isLoading || groupsAsync.isLoading;
    final error = plansAsync.error ?? groupsAsync.error;
    final recentPlans = (plansAsync.valueOrNull?.items ?? []).take(5).toList();
    final activeGroups = (groupsAsync.valueOrNull ?? []).take(5).toList();

    return Scaffold(
      drawer: _buildDrawer(context),
      body: RefreshablePageWrapper(
        onRefresh: onRefresh,
        child: CustomScrollView(
          slivers: [
            _buildSliverAppBar(context),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: isLoading && recentPlans.isEmpty && activeGroups.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.only(top: 24, bottom: 80),
                        child: AppSkeleton.list(itemCount: 4),
                      )
                    : error != null && recentPlans.isEmpty
                    ? AppError(
                        message: 'Error: $error',
                        onRetry: () async => onRefresh(),
                        retryLabel: l10n.t('common.retry'),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildGreetingSection(context),
                          const SizedBox(height: 24),
                          _buildQuickActions(context),
                          const SizedBox(height: 24),
                          _buildRecentPlans(context, recentPlans),
                          const SizedBox(height: 24),
                          _buildActiveGroups(context, activeGroups),
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

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDrawerHeader(context),
            _buildDrawerMenuItems(context),
            const Spacer(),
            _buildDrawerFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 200,
      floating: false,
      pinned: true,
      leading: Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
      ),
      actions: [
        Consumer(
          builder: (context, ref, child) {
            final unreadCount = ref.watch(unreadCountProvider).valueOrNull ?? 0;
            return IconButton(
              icon: _buildNotificationBadge(
                child: const Icon(
                  Icons.notifications_none,
                  color: Colors.white,
                ),
                count: unreadCount,
                badgeColor: AppColors.error,
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const NotificationListPage(),
                ),
              ),
            );
          },
        ),
        Consumer(
          builder: (context, ref, child) {
            final isDark = ref.watch(isDarkModeProvider);
            return IconButton(
              icon: Icon(
                isDark ? Icons.light_mode : Icons.dark_mode,
                color: Colors.white,
              ),
              onPressed: () =>
                  ref.read(themeNotifierProvider.notifier).toggleTheme(),
            );
          },
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          context.l10n.t('common.app_name'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppColors.primaryGradient,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: 60,
                right: -50,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
              ),
              Positioned(
                bottom: -30,
                left: -30,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerHeader(BuildContext context) {
    final user = ref.read(authNotifierProvider).user;
    final l10n = context.l10n;
    return DrawerHeader(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: AppColors.primaryGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: ClipOval(
              child: user != null && user.avatarUrl != null
                  ? CachedNetworkImage(
                      imageUrl: user.avatarUrl!,
                      width: 64,
                      height: 64,
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
                      errorWidget: (c, u, e) => Container(
                        color: Colors.grey[100],
                        child: Center(
                          child: Text(
                            user.initials.isNotEmpty ? user.initials : '?',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    )
                  : Container(
                      color: Colors.grey[100],
                      child: Center(
                        child: Text(
                          user?.initials ?? '?',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            user?.fullName ?? l10n.t('common.not_logged_in'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (user != null && user.email != null && user.email!.isNotEmpty)
            Text(
              user.email!,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
        ],
      ),
    );
  }

  Widget _buildDrawerMenuItems(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        Consumer(
          builder: (context, ref, child) {
            final unreadCount = ref.watch(unreadCountProvider).valueOrNull ?? 0;

            return ListTile(
              leading: _buildNotificationBadge(
                child: const Icon(Icons.notifications_outlined),
                count: unreadCount,
                badgeColor: AppColors.primary,
              ),
              title: Text(l10n.t('home.notifications')),
              onTap: () async {
                Navigator.of(context).pop();
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const NotificationListPage(),
                  ),
                );
                if (!mounted) return;
                ref.invalidate(unreadCountProvider);
              },
            );
          },
        ),
        Consumer(
          builder: (context, ref, child) {
            final unreadCount = ref.watch(totalUnreadCountProvider);

            return ListTile(
              leading: _buildNotificationBadge(
                child: const Icon(Icons.chat_bubble),
                count: unreadCount,
              ),
              title: Text(l10n.t('home.conversations')),
              onTap: () async {
                Navigator.of(context).pop();
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const ConversationListPage(),
                  ),
                );
                if (!mounted) return;
                ref.invalidate(conversationListProvider);
              },
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.groups),
          title: Text(l10n.t('home.groups')),
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).pushNamed('/group');
          },
        ),
        ListTile(
          leading: const Icon(Icons.event_note),
          title: Text(l10n.t('home.plans')),
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).pushNamed('/plan');
          },
        ),
        if ((ref.read(authNotifierProvider).user?.isStaff ?? false))
          ListTile(
            leading: const Icon(Icons.insights),
            title: Text(l10n.t('home.analytics')),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed('/analytics');
            },
          ),
        ListTile(
          leading: const Icon(Icons.language_rounded),
          title: Text(l10n.t('common.language')),
          subtitle: Text(
            l10n.languageName(ref.watch(currentAppLanguageProvider).code),
          ),
          onTap: () => _showLanguageSheet(context),
        ),
        ListTile(
          leading: const Icon(Icons.person),
          title: Text(l10n.t('home.profile')),
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).pushNamed('/profile');
          },
        ),
      ],
    );
  }

  Widget _buildDrawerFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        context.l10n.t('home.copyright'),
        style: const TextStyle(color: Colors.grey, fontSize: 12),
        textAlign: TextAlign.center,
      ),
    );
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

    return GFCard(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(0),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(greetingIcon, color: AppColors.primary, size: 28),
              const SizedBox(width: 12),
              Text(
                greeting,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.t('home.ready_for_trip'),
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.t('home.quick_actions'),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _handleQuickCreatePlan,
                child: _buildQuickActionCard(
                  color: AppColors.primary,
                  icon: Icons.add_location_alt,
                  label: l10n.t('home.create_plan'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pushNamed('/group'),
                child: _buildQuickActionCard(
                  color: AppColors.secondary,
                  icon: Icons.group_add,
                  label: l10n.t('home.join_group'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const FriendSearchPage(),
                    ),
                  );
                },
                child: _buildQuickActionCard(
                  color: AppColors.success,
                  icon: Icons.person_search,
                  label: l10n.t('home.find_friends'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CurrentLocationMapPage(),
                    ),
                  );
                },
                child: _buildQuickActionCard(
                  color: AppColors.warning,
                  icon: Icons.map,
                  label: l10n.t('home.map'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActionCard({
    required Color color,
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
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
              onPressed: () => Navigator.of(context).pushNamed('/plan'),
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
                return GestureDetector(
                  onTap: () async {
                    final id = plan.id;
                    if (id.isEmpty) return;

                    final result = await Navigator.of(context)
                        .push<Map<String, dynamic>>(
                          MaterialPageRoute(
                            builder: (_) => PlanDetailsPage(id: id),
                          ),
                        );
                    if (!mounted) return;

                    if (result != null) {
                      if (result['action'] == 'delete' && result['id'] == id) {
                        ref.read(plansNotifierProvider.notifier).removePlan(id);
                      }

                      if ((result['action'] == 'updated' ||
                              result['action'] == 'edit') &&
                          result['plan'] is Map) {
                        try {
                          final updated = PlanSummary.fromJson(
                            Map<String, dynamic>.from(result['plan'] as Map),
                          );
                          ref
                              .read(plansNotifierProvider.notifier)
                              .updatePlan(updated);
                        } catch (_) {
                          // Ignore malformed return payload.
                        }
                      }
                    }
                  },
                  child: _buildPlanCardItem(
                    context,
                    index,
                    plan,
                    totalCount: recentPlans.length,
                  ),
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
              onPressed: () => Navigator.of(context).pushNamed('/group'),
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
              return GestureDetector(
                onTap: () {
                  final id = group.id;
                  if (id.isNotEmpty) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GroupDetailsPage(id: id),
                      ),
                    );
                  }
                },
                child: _buildGroupCardItem(context, index, group),
              );
            },
          ),
      ],
    );
  }

  Widget _buildPlanCardItem(
    BuildContext context,
    int index,
    PlanSummary plan, {
    required int totalCount,
  }) {
    final colors = AppColors.cardColors;
    final color = colors[index % colors.length];
    final name = plan.title.isNotEmpty
        ? plan.title
        : context.l10n.t('home.plans');

    return Container(
      width: 280,
      margin: EdgeInsets.only(right: index == totalCount - 1 ? 0 : 16),
      child: GFCard(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.all(0),
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
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
                  child: Icon(Icons.event, color: color, size: 20),
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
                          plan.dateRange,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
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
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.event_note, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  plan.activitiesCountText,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
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
    GroupSummary group,
  ) {
    final colors = AppColors.cardColors;
    final color = colors[index % colors.length];
    final name = group.name.isNotEmpty
        ? group.name
        : context.l10n.t('home.groups');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: GFCard(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.all(0),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
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
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
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

  Future<void> _showLanguageSheet(BuildContext context) async {
    final l10n = context.l10n;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return Consumer(
          builder: (context, ref, child) {
            final currentLanguage = ref.watch(currentAppLanguageProvider);
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text(
                      l10n.t('home.language_sheet_title'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _LanguageTile(
                    label: l10n.t('common.language_vietnamese'),
                    selected: currentLanguage == AppLanguage.vietnamese,
                    onTap: () async {
                      await ref
                          .read(localeNotifierProvider.notifier)
                          .setLanguage(AppLanguage.vietnamese);
                      if (!sheetContext.mounted) return;
                      Navigator.of(sheetContext).pop();
                    },
                  ),
                  _LanguageTile(
                    label: l10n.t('common.language_english'),
                    selected: currentLanguage == AppLanguage.english,
                    onTap: () async {
                      await ref
                          .read(localeNotifierProvider.notifier)
                          .setLanguage(AppLanguage.english);
                      if (!sheetContext.mounted) return;
                      Navigator.of(sheetContext).pop();
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
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

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      title: Text(
        label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      trailing: AnimatedOpacity(
        opacity: selected ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: const Icon(Icons.check_rounded, color: AppColors.primary),
      ),
    );
  }
}
