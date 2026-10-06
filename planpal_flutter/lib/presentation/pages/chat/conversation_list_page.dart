import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/riverpod/auth_notifier.dart';
import '../../../core/riverpod/conversation_providers.dart';
import '../../../core/dtos/conversation.dart';
import '../../../core/responsive/app_breakpoints.dart';
import '../../../core/services/error_display_service.dart';
import '../../../core/services/notification_websocket_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../widgets/common/custom_search_bar.dart';
import '../../widgets/common/refreshable_page_wrapper.dart';
import '../../widgets/layout/responsive_content.dart';
import '../friends/friend_search_page.dart';
import 'chat_page.dart';
import '../../../shared/ui_states/ui_states.dart';

class ConversationListPage extends ConsumerStatefulWidget {
  const ConversationListPage({super.key});

  @override
  ConsumerState<ConversationListPage> createState() =>
      _ConversationListPageState();
}

class _ConversationListPageState extends ConsumerState<ConversationListPage>
    with WidgetsBindingObserver, RefreshablePage {
  final TextEditingController _searchController = TextEditingController();
  final NotificationWebSocketService _presenceSocket =
      NotificationWebSocketService();
  StreamSubscription<NotificationSocketEvent>? _presenceSubscription;
  Timer? _presenceRefreshTimer;
  String _searchQuery = '';
  bool _showOnlineOnly = false;
  Conversation? _selectedConversation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupPresenceUpdates();
    _startPresenceRefreshTimer();
  }

  @override
  Future<void> onRefresh() async {
    await ref.read(conversationListProvider.notifier).refresh(silent: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceRefreshTimer?.cancel();
    unawaited(_presenceSubscription?.cancel() ?? Future<void>.value());
    _presenceSocket.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _connectPresenceSocket();
    unawaited(
      ref.read(conversationListProvider.notifier).refresh(silent: true),
    );
  }

  void _setupPresenceUpdates() {
    _connectPresenceSocket();
    _presenceSubscription = _presenceSocket.eventStream.listen(
      _handlePresenceEvent,
    );
  }

  void _startPresenceRefreshTimer() {
    _presenceRefreshTimer?.cancel();
    _presenceRefreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted || _presenceSocket.isConnected) return;
      _connectPresenceSocket();
      unawaited(
        ref.read(conversationListProvider.notifier).refresh(silent: true),
      );
    });
  }

  void _connectPresenceSocket() {
    final token = ref.read(authNotifierProvider).token;
    if (token == null || token.isEmpty) return;
    unawaited(_presenceSocket.connect(token));
  }

  void _handlePresenceEvent(NotificationSocketEvent event) {
    if (!mounted) return;
    if (event.type != NotificationSocketEventType.userOnline &&
        event.type != NotificationSocketEventType.userOffline) {
      return;
    }

    final userId = event.userId;
    final isOnline = event.isOnline;
    if (userId == null || isOnline == null) return;

    ref
        .read(conversationListProvider.notifier)
        .updateUserPresence(
          userId: userId,
          isOnline: isOnline,
          lastSeen: event.lastSeen,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conversationsAsync = ref.watch(conversationListProvider);
    final isDesktop = AppBreakpoints.isExpanded(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: _buildAppBar(theme),
      body: isDesktop
          ? _buildDesktopBody(theme, conversationsAsync)
          : RefreshablePageWrapper(
              onRefresh: onRefresh,
              child: ResponsiveContent(
                mediumMaxWidth: 820,
                expandedMaxWidth: 960,
                child: Column(
                  children: [
                    _buildSearchSection(theme),
                    Expanded(
                      child: _buildConversationsList(theme, conversationsAsync),
                    ),
                  ],
                ),
              ),
            ),
      floatingActionButton: isDesktop
          ? null
          : _buildFloatingActionButton(theme),
    );
  }

  Widget _buildDesktopBody(
    ThemeData theme,
    AsyncValue<List<Conversation>> conversationsAsync,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 380,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                right: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Column(
              children: [
                _buildSearchSection(theme),
                Expanded(
                  child: RefreshablePageWrapper(
                    onRefresh: onRefresh,
                    child: _buildConversationsList(theme, conversationsAsync),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _selectedConversation == null
                ? _buildConversationPlaceholder(theme)
                : ChatPage(
                    key: ValueKey(_selectedConversation!.id),
                    conversation: _selectedConversation!,
                    showBackButton: false,
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildConversationPlaceholder(ThemeData theme) {
    return Center(
      key: const ValueKey('conversation-placeholder'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.forum_outlined,
                size: 48,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                context.l10n.t('chat.select_conversation_title'),
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.t('chat.select_conversation_description'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme) {
    final unreadCount = ref.watch(totalUnreadCountProvider);

    return AppBar(
      title: Row(
        children: [
          Text(
            context.l10n.t('chat.title'),
            style: GoogleFonts.manrope(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          if (unreadCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                unreadCount > 99 ? '99+' : unreadCount.toString(),
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (AppBreakpoints.isExpanded(context))
          IconButton(
            tooltip: context.l10n.t('chat.find_friends'),
            onPressed: _navigateToFriends,
            icon: Icon(
              PhosphorIcons.userPlus(),
              color: theme.colorScheme.onSurface,
            ),
          ),
        IconButton(
          onPressed: () => _showFilterOptions(theme),
          icon: Icon(
            PhosphorIcons.funnel(),
            color: theme.colorScheme.onSurface,
          ),
        ),
        // Remove manual refresh button since we have pull-to-refresh
      ],
      elevation: 0,
      backgroundColor: theme.colorScheme.surface,
    );
  }

  Widget _buildSearchSection(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withAlpha(26),
            width: 1,
          ),
        ),
      ),
      child: CustomSearchBar(
        controller: _searchController,
        hintText: context.l10n.t('chat.search_hint'),
        onChanged: (query) {
          setState(() {
            _searchQuery = query;
          });
        },
        prefixIcon: PhosphorIcons.magnifyingGlass(),
      ),
    );
  }

  Widget _buildConversationsList(
    ThemeData theme,
    AsyncValue<List<Conversation>> conversationsAsync,
  ) {
    // If searching, use the search family provider
    if (_searchQuery.isNotEmpty) {
      final searchAsync = ref.watch(conversationSearchProvider(_searchQuery));
      return searchAsync.when(
        loading: () => const AppSkeleton.list(itemCount: 5),
        error: (error, _) => _buildErrorState(theme, _formatError(error)),
        data: (results) {
          var filtered = results;
          if (_showOnlineOnly) {
            filtered = filtered
                .where((c) => c.isDirect ? c.isOtherUserOnline : true)
                .toList();
          }
          if (filtered.isEmpty) return _buildEmptyState();
          return _buildList(theme, filtered);
        },
      );
    }

    return conversationsAsync.when(
      loading: () => const AppSkeleton.list(itemCount: 6),
      error: (error, _) => _buildErrorState(theme, _formatError(error)),
      data: (conversations) {
        var filtered = conversations;
        if (_showOnlineOnly) {
          filtered = filtered
              .where((c) => c.isDirect ? c.isOtherUserOnline : true)
              .toList();
        }
        if (filtered.isEmpty) return _buildEmptyState();
        return _buildList(theme, filtered);
      },
    );
  }

  Widget _buildList(ThemeData theme, List<Conversation> conversations) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: conversations.length,
      separatorBuilder: (context, index) =>
          Divider(height: 1, color: theme.colorScheme.outline.withAlpha(26)),
      itemBuilder: (context, index) {
        final conversation = conversations[index];
        return _buildConversationTile(theme, conversation);
      },
    );
  }

  Widget _buildConversationTile(ThemeData theme, Conversation conversation) {
    return Material(
      color: _selectedConversation?.id == conversation.id
          ? theme.colorScheme.primaryContainer.withValues(alpha: .36)
          : Colors.transparent,
      child: InkWell(
        onTap: () => _navigateToChat(conversation),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _buildAvatar(theme, conversation),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.displayName,
                            style: GoogleFonts.manrope(
                              fontSize: 16,
                              fontWeight: conversation.hasUnreadMessages
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: theme.colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (conversation.lastMessageTime != null) ...[
                          Text(
                            conversation.lastMessageTime!,
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: conversation.hasUnreadMessages
                                  ? AppColors.primary
                                  : theme.colorScheme.onSurface.withAlpha(153),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(child: _buildLastMessage(theme, conversation)),
                        if (conversation.hasUnreadMessages) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              conversation.unreadCountText,
                              style: GoogleFonts.manrope(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(ThemeData theme, Conversation conversation) {
    final palette = AppColors.avatarPalette(
      conversation.id.isNotEmpty ? conversation.id : conversation.displayName,
      theme.brightness,
    );
    return Stack(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette.background,
          ),
          child: conversation.avatarUrl.isNotEmpty
              ? ClipOval(
                  child: Image.network(
                    conversation.avatarUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _buildAvatarPlaceholder(conversation, palette),
                  ),
                )
              : _buildAvatarPlaceholder(conversation, palette),
        ),
        if (conversation.isDirect && conversation.isOtherUserOnline)
          Positioned(
            bottom: 2,
            right: 2,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.surface, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAvatarPlaceholder(
    Conversation conversation,
    AvatarPalette palette,
  ) {
    final displayName = conversation.displayName;
    final avatarText = displayName.isNotEmpty
        ? displayName.substring(0, 1).toUpperCase()
        : (conversation.isGroup ? 'G' : 'U');

    return Center(
      child: Text(
        avatarText,
        style: GoogleFonts.manrope(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: palette.foreground,
        ),
      ),
    );
  }

  Widget _buildLastMessage(ThemeData theme, Conversation conversation) {
    if (conversation.lastMessagePreview == null) {
      return Text(
        context.l10n.t('chat.empty_title'),
        style: GoogleFonts.manrope(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: theme.colorScheme.onSurface.withAlpha(153),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: [
          if (conversation.lastMessageSender != null &&
              conversation.isGroup) ...[
            TextSpan(
              text: '${conversation.lastMessageSender}: ',
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
          TextSpan(
            text: conversation.lastMessagePreview!,
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: conversation.hasUnreadMessages
                  ? FontWeight.w500
                  : FontWeight.w400,
              color: conversation.hasUnreadMessages
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurface.withAlpha(179),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme, String errorMessage) {
    return AppError(
      message:
          '${context.l10n.t('chat.load_conversations_failed')}\n$errorMessage',
      onRetry: onRefresh,
      retryLabel: context.l10n.t('common.retry'),
    );
  }

  String _formatError(Object error) {
    return ErrorDisplayService.getUserFriendlyMessage(error);
  }

  Widget _buildEmptyState() {
    return AppEmpty(
      icon: Icons.chat_bubble_outline,
      title: _searchQuery.isNotEmpty
          ? context.l10n.t('chat.no_conversations_found')
          : context.l10n.t('chat.no_conversations_yet'),
      description: _searchQuery.isNotEmpty
          ? context.l10n.t('chat.adjust_search')
          : context.l10n.t('chat.start_conversation'),
      actionLabel: _searchQuery.isEmpty
          ? context.l10n.t('chat.find_friends')
          : null,
      onAction: _searchQuery.isEmpty ? _navigateToFriends : null,
    );
  }

  Widget _buildFloatingActionButton(ThemeData theme) {
    return FloatingActionButton(
      onPressed: _navigateToFriends,
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      child: Icon(PhosphorIcons.plus()),
    );
  }

  void _showFilterOptions(ThemeData theme) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.t('chat.filter_title'),
              style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: Text(
                context.l10n.t('chat.online_only'),
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              value: _showOnlineOnly,
              onChanged: (value) {
                setState(() {
                  _showOnlineOnly = value;
                });
                Navigator.pop(context);
              },
              thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
                return states.contains(WidgetState.selected)
                    ? AppColors.primary
                    : null;
              }),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToChat(Conversation conversation) async {
    if (AppBreakpoints.isExpanded(context)) {
      setState(() => _selectedConversation = conversation);
      return;
    }

    await context.push('/conversations/${conversation.id}');

    // Refresh conversations when returning from ChatPage to update unread counts
    if (mounted) {
      ref.read(conversationListProvider.notifier).refresh();
    }
  }

  void _navigateToFriends() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const FriendSearchPage()),
    );
  }
}
