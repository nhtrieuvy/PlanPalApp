import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/riverpod/conversation_providers.dart';
import '../../../core/dtos/conversation.dart';
import '../../../core/services/error_display_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../widgets/common/custom_search_bar.dart';
import '../../widgets/common/refreshable_page_wrapper.dart';
import 'chat_page.dart';
import '../friends/friend_search_page.dart';
import '../../../shared/ui_states/ui_states.dart';

class ConversationListPage extends ConsumerStatefulWidget {
  const ConversationListPage({super.key});

  @override
  ConsumerState<ConversationListPage> createState() =>
      _ConversationListPageState();
}

class _ConversationListPageState extends ConsumerState<ConversationListPage>
    with AutomaticKeepAliveClientMixin, RefreshablePage {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showOnlineOnly = false;

  @override
  bool get wantKeepAlive => true;

  @override
  Future<void> onRefresh() async {
    await ref.read(conversationListProvider.notifier).refresh();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final conversationsAsync = ref.watch(conversationListProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: _buildAppBar(theme),
      body: RefreshablePageWrapper(
        onRefresh: onRefresh,
        child: Column(
          children: [
            _buildSearchSection(theme),
            Expanded(child: _buildConversationsList(theme, conversationsAsync)),
          ],
        ),
      ),
      floatingActionButton: _buildFloatingActionButton(theme),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme) {
    final unreadCount = ref.watch(totalUnreadCountProvider);

    return AppBar(
      title: Row(
        children: [
          Text(
            'Messages',
            style: GoogleFonts.inter(
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
                style: GoogleFonts.inter(
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
        hintText: 'Search conversations...',
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
      color: Colors.transparent,
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
                            style: GoogleFonts.inter(
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
                            style: GoogleFonts.inter(
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
                              style: GoogleFonts.inter(
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
    return Stack(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: AppColors.primaryGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: conversation.avatarUrl.isNotEmpty
              ? ClipOval(
                  child: Image.network(
                    conversation.avatarUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _buildAvatarPlaceholder(conversation),
                  ),
                )
              : _buildAvatarPlaceholder(conversation),
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

  Widget _buildAvatarPlaceholder(Conversation conversation) {
    final displayName = conversation.displayName;
    final avatarText = displayName.isNotEmpty
        ? displayName.substring(0, 1).toUpperCase()
        : (conversation.isGroup ? 'G' : 'U');

    return Center(
      child: Text(
        avatarText,
        style: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildLastMessage(ThemeData theme, Conversation conversation) {
    if (conversation.lastMessagePreview == null) {
      return Text(
        'No messages yet',
        style: GoogleFonts.inter(
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
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
          TextSpan(
            text: conversation.lastMessagePreview!,
            style: GoogleFonts.inter(
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
      message: 'Failed to load conversations\n$errorMessage',
      onRetry: onRefresh,
      retryLabel: 'Retry',
    );
  }

  String _formatError(Object error) {
    return ErrorDisplayService.getUserFriendlyMessage(error);
  }

  Widget _buildEmptyState() {
    return AppEmpty(
      icon: Icons.chat_bubble_outline,
      title: _searchQuery.isNotEmpty
          ? 'No conversations found'
          : 'No conversations yet',
      description: _searchQuery.isNotEmpty
          ? 'Try adjusting your search terms'
          : 'Start a conversation with your friends',
      actionLabel: _searchQuery.isEmpty ? 'Find Friends' : null,
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
              'Filter Conversations',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: Text(
                'Show online friends only',
                style: GoogleFonts.inter(
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
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatPage(conversation: conversation),
      ),
    );

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
