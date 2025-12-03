import 'package:flutter/material.dart';
// removed color_utils; use withAlpha directly
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/dtos/conversation.dart';

class ConversationListItem extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const ConversationListItem({
    super.key,
    required this.conversation,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _buildAvatar(theme),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(theme),
                  const SizedBox(height: 4),
                  _buildLastMessage(theme),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _buildTrailing(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(ThemeData theme) {
    return Stack(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: conversation.hasUnreadMessages
                  ? theme.colorScheme.primary
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: CircleAvatar(
            radius: 26,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            child: conversation.avatarUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: conversation.avatarUrl,
                    imageBuilder: (context, imageProvider) => Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        image: DecorationImage(
                          image: imageProvider,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    placeholder: (context, url) =>
                        _buildAvatarPlaceholder(theme),
                    errorWidget: (context, url, error) =>
                        _buildAvatarPlaceholder(theme),
                  )
                : _buildAvatarPlaceholder(theme),
          ),
        ),
        // Online indicator for direct conversations
        if (conversation.isDirect && conversation.isOtherUserOnline)
          Positioned(
            right: 2,
            bottom: 2,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.surface, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAvatarPlaceholder(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withAlpha(75),
            theme.colorScheme.secondary.withAlpha(75),
          ],
        ),
      ),
      child: Center(
        child: conversation.isDirect
            ? Icon(
                PhosphorIcons.user(),
                size: 24,
                color: theme.colorScheme.onSurfaceVariant,
              )
            : Icon(
                PhosphorIcons.users(),
                size: 24,
                color: theme.colorScheme.onSurfaceVariant,
              ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: Text(
            conversation.displayName,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: conversation.hasUnreadMessages
                  ? FontWeight.w600
                  : FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (conversation.lastMessageTime != null)
          Text(
            conversation.lastMessageTime!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: conversation.hasUnreadMessages
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: conversation.hasUnreadMessages
                  ? FontWeight.w500
                  : FontWeight.normal,
            ),
          ),
      ],
    );
  }

  Widget _buildLastMessage(ThemeData theme) {
    if (conversation.lastMessage == null) {
      return Text(
        'No messages yet',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    final lastMessage = conversation.lastMessage!;
    final isOwnMessage = false; // TODO: Compare with current user

    return Row(
      children: [
        if (conversation.isGroup && !isOwnMessage) ...[
          Text(
            '${lastMessage.sender}: ',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        Expanded(
          child: Text(
            lastMessage.displayText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: conversation.hasUnreadMessages
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: conversation.hasUnreadMessages
                  ? FontWeight.w500
                  : FontWeight.normal,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildTrailing(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Unread count badge
        if (conversation.hasUnreadMessages)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
            child: Text(
              conversation.unreadCountText,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          )
        else
          const SizedBox(width: 20, height: 20),

        const SizedBox(height: 4),

        // Message status indicators
        _buildMessageStatus(theme),
      ],
    );
  }

  Widget _buildMessageStatus(ThemeData theme) {
    // TODO: Implement message status (sent, delivered, read)
    // For now, just show conversation type indicator
    return Icon(
      conversation.isDirect ? PhosphorIcons.user() : PhosphorIcons.users(),
      size: 14,
      color: theme.colorScheme.surfaceContainerHighest.withAlpha(125),
    );
  }
}
