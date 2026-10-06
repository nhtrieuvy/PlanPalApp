import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/dtos/notification_model.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/notifications_provider.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:planpal_flutter/core/theme/app_design_tokens.dart';
import 'package:planpal_flutter/presentation/widgets/common/refreshable_page_wrapper.dart';
import 'package:planpal_flutter/presentation/widgets/notifications/notification_item.dart';
import 'package:planpal_flutter/presentation/pages/notifications/notification_preferences_page.dart';
import 'package:planpal_flutter/shared/ui_states/ui_states.dart';
import 'package:planpal_flutter/presentation/widgets/layout/responsive_content.dart';

class NotificationListPage extends ConsumerStatefulWidget {
  const NotificationListPage({super.key});

  @override
  ConsumerState<NotificationListPage> createState() =>
      _NotificationListPageState();
}

class _NotificationListPageState extends ConsumerState<NotificationListPage>
    with RefreshablePage {
  final ScrollController _scrollController = ScrollController();
  bool? _readFilter;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Future<void> onRefresh() async {
    await Future.wait([
      ref.read(notificationsProvider.notifier).refresh(),
      ref.read(unreadCountProvider.notifier).refresh(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final notificationsAsync = ref.watch(notificationsProvider);
    final unreadCountAsync = ref.watch(unreadCountProvider);
    final feedState = notificationsAsync.valueOrNull;
    final unreadCount =
        feedState?.unreadCount ?? unreadCountAsync.valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(l10n.t('notifications.title')),
            if (unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  unreadCount > 99 ? '99+' : unreadCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            tooltip: l10n.t('notification_settings.title'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const NotificationPreferencesPage(),
              ),
            ),
            icon: const Icon(Icons.tune_rounded),
          ),
          if (unreadCount > 0)
            IconButton(
              tooltip: l10n.t('notifications.mark_all_as_read'),
              onPressed: _markAllAsRead,
              icon: const Icon(Icons.done_all_rounded),
            ),
        ],
      ),
      body: ResponsiveContent(
        mediumMaxWidth: 820,
        expandedMaxWidth: 960,
        child: Column(
          children: [
            _buildFilterBar(context),
            Expanded(
              child: RefreshablePageWrapper(
                onRefresh: onRefresh,
                child: notificationsAsync.when(
                  loading: () => const AppSkeleton.list(itemCount: 6),
                  error: (error, _) => AppError(
                    message: ErrorDisplayService.getUserFriendlyMessage(error),
                    onRetry: () {
                      onRefresh();
                    },
                    retryLabel: l10n.t('common.retry'),
                  ),
                  data: (data) => _buildContent(context, data),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          _buildFilterChip(label: context.l10n.t('common.all'), value: null),
          const SizedBox(width: 8),
          _buildFilterChip(
            label: context.l10n.t('common.unread'),
            value: false,
          ),
          const SizedBox(width: 8),
          _buildFilterChip(label: context.l10n.t('common.read'), value: true),
        ],
      ),
    );
  }

  Widget _buildFilterChip({required String label, required bool? value}) {
    final isSelected = _readFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => _updateFilter(value),
    );
  }

  Widget _buildContent(BuildContext context, NotificationFeedState data) {
    if (data.items.isEmpty) {
      return ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 72),
          AppEmpty(
            icon: Icons.notifications_none_rounded,
            title: context.l10n.t('notifications.empty_title'),
            description: context.l10n.t('notifications.empty_description'),
          ),
        ],
      );
    }

    final today = <NotificationModel>[];
    final earlier = <NotificationModel>[];
    final now = DateTime.now();
    for (final item in data.items) {
      final created = item.createdAt.toLocal();
      if (created.year == now.year &&
          created.month == now.month &&
          created.day == now.day) {
        today.add(item);
      } else {
        earlier.add(item);
      }
    }

    final children = <Widget>[];
    void addSection(String title, List<NotificationModel> items) {
      if (items.isEmpty) return;
      children.add(_buildSectionLabel(context, title));
      children.addAll(
        items.map(
          (notification) => NotificationItem(
            key: ValueKey(notification.id),
            notification: notification,
            onTap: notification.isUnread
                ? () => _markAsRead(notification.id)
                : null,
          ),
        ),
      );
    }

    addSection(context.l10n.t('notifications.today'), today);
    addSection(context.l10n.t('notifications.earlier'), earlier);
    if (data.isLoadingMore) {
      children.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return ListView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      children: children,
    );
  }

  Widget _buildSectionLabel(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }

  Future<void> _updateFilter(bool? isRead) async {
    setState(() {
      _readFilter = isRead;
    });
    await ref
        .read(notificationsProvider.notifier)
        .updateFilter(NotificationFilter(isRead: isRead));
  }

  Future<void> _markAsRead(String notificationId) async {
    try {
      await ref.read(notificationsProvider.notifier).markAsRead(notificationId);
    } catch (error) {
      if (!mounted) return;
      ErrorDisplayService.showErrorSnackbar(
        context,
        ErrorDisplayService.getUserFriendlyMessage(error),
      );
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      await ref.read(notificationsProvider.notifier).markAllAsRead();
    } catch (error) {
      if (!mounted) return;
      ErrorDisplayService.showErrorSnackbar(
        context,
        ErrorDisplayService.getUserFriendlyMessage(error),
      );
    }
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent <= 0) return;

    final threshold = position.maxScrollExtent * 0.8;
    if (position.pixels >= threshold) {
      ref.read(notificationsProvider.notifier).loadMore();
    }
  }
}
