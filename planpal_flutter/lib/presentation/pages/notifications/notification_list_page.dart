import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/dtos/notification_model.dart';
import 'package:planpal_flutter/core/riverpod/notifications_provider.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:planpal_flutter/presentation/widgets/common/refreshable_page_wrapper.dart';
import 'package:planpal_flutter/presentation/widgets/notifications/notification_item.dart';
import 'package:planpal_flutter/shared/ui_states/ui_states.dart';

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
    final notificationsAsync = ref.watch(notificationsProvider);
    final unreadCountAsync = ref.watch(unreadCountProvider);
    final feedState = notificationsAsync.valueOrNull;
    final unreadCount =
        feedState?.unreadCount ?? unreadCountAsync.valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Notifications'),
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
          if (unreadCount > 0)
            IconButton(
              tooltip: 'Mark all as read',
              onPressed: _markAllAsRead,
              icon: const Icon(Icons.done_all_rounded),
            ),
        ],
      ),
      body: Column(
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
                  retryLabel: 'Retry',
                ),
                data: (data) => _buildContent(context, data),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          _buildFilterChip(label: 'All', value: null),
          const SizedBox(width: 8),
          _buildFilterChip(label: 'Unread', value: false),
          const SizedBox(width: 8),
          _buildFilterChip(label: 'Read', value: true),
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
        children: const [
          SizedBox(height: 120),
          AppEmpty(
            icon: Icons.notifications_none_rounded,
            title: 'No notifications yet',
            description: 'New plan, group, and chat updates will appear here.',
          ),
        ],
      );
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: data.items.length + (data.isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= data.items.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final notification = data.items[index];
        return NotificationItem(
          key: ValueKey(notification.id),
          notification: notification,
          onTap: notification.isUnread
              ? () => _markAsRead(notification.id)
              : null,
        );
      },
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
