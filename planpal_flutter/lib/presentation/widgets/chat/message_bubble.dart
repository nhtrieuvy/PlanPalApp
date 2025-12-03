import 'package:flutter/material.dart';
// removed color_utils; use withAlpha directly
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/dtos/chat_message.dart';

enum MessageStatus { sending, sent, delivered, read, failed }

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isCurrentUser;
  final bool showAvatar;
  final bool showTimestamp;
  final MessageStatus status;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onImageTap;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isCurrentUser,
    this.showAvatar = true,
    this.showTimestamp = true,
    this.status = MessageStatus.sent,
    this.onTap,
    this.onLongPress,
    this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 16),
        child: Row(
          mainAxisAlignment: isCurrentUser
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Avatar for other users
            if (!isCurrentUser && showAvatar) ...[
              _buildAvatar(context),
              const SizedBox(width: 8),
            ],

            // Message bubble
            Flexible(
              child: Column(
                crossAxisAlignment: isCurrentUser
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  // Sender name for group chats
                  if (!isCurrentUser && message.sender.fullName.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 12, bottom: 4),
                      child: Text(
                        message.sender.fullName,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),

                  // Message content
                  Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    decoration: BoxDecoration(
                      color: isCurrentUser
                          ? const Color(0xFF6366F1) // Indigo primary
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(20),
                        topRight: const Radius.circular(20),
                        bottomLeft: Radius.circular(isCurrentUser ? 20 : 4),
                        bottomRight: Radius.circular(isCurrentUser ? 4 : 20),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(13),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _buildMessageContent(context),
                  ),

                  // Timestamp and status
                  if (showTimestamp) _buildMessageInfo(context),
                ],
              ),
            ),

            // Avatar placeholder for current user
            if (isCurrentUser && showAvatar) ...[
              const SizedBox(width: 8),
              _buildAvatar(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            const Color(0xFF6366F1), // Indigo
            const Color(0xFF06B6D4), // Cyan
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: message.sender.avatarUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: CachedNetworkImage(
                imageUrl: message.sender.avatarUrl!,
                fit: BoxFit.cover,
                placeholder: (context, url) => _buildAvatarPlaceholder(),
                errorWidget: (context, url, error) => _buildAvatarPlaceholder(),
              ),
            )
          : _buildAvatarPlaceholder(),
    );
  }

  Widget _buildAvatarPlaceholder() {
    final initials = message.sender.fullName.isNotEmpty
        ? message.sender.initials
        : '?';

    return Center(
      child: Text(
        initials,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildMessageContent(BuildContext context) {
    switch (message.messageType) {
      case MessageType.text:
        return _buildTextMessage(context);
      case MessageType.image:
        return _buildImageMessage(context);
      case MessageType.location:
        return _buildLocationMessage(context);
      case MessageType.file:
        return _buildFileMessage(context);
      case MessageType.system:
        return _buildTextMessage(context); // System messages as text
    }
  }

  Widget _buildTextMessage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        message.content,
        style: GoogleFonts.inter(
          fontSize: 15,
          height: 1.4,
          color: isCurrentUser ? Colors.white : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildImageMessage(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onImageTap,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 250, maxHeight: 300),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              child: CachedNetworkImage(
                // Use attachmentUrl provided by backend DTO when available;
                // fall back to content for backward compatibility.
                imageUrl: message.attachmentUrl ?? message.content,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  height: 150,
                  color: Colors.grey[300],
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (context, url, error) => Container(
                  height: 150,
                  color: Colors.grey[300],
                  child: const Center(child: Icon(Icons.error)),
                ),
              ),
            ),
          ),
        ),
        if (message.content.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              message.content,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: isCurrentUser
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLocationMessage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isCurrentUser
                  ? Colors.white.withAlpha(50)
                  : const Color(0xFF6366F1).withAlpha(25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              PhosphorIcons.mapPin(),
              size: 20,
              color: isCurrentUser ? Colors.white : const Color(0xFF6366F1),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vị trí',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isCurrentUser
                        ? Colors.white
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message.content,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: isCurrentUser
                        ? Colors.white.withAlpha(200)
                        : colorScheme.onSurfaceVariant.withAlpha(175),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileMessage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fileName = message.attachmentName ?? 'File';
    final fileSize = message.attachmentSize != null
        ? _formatFileSize(message.attachmentSize!)
        : '';

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isCurrentUser
                  ? Colors.white.withAlpha(50)
                  : const Color(0xFF6366F1).withAlpha(25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _getFileIcon(fileName),
              size: 20,
              color: isCurrentUser ? Colors.white : const Color(0xFF6366F1),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isCurrentUser
                        ? Colors.white
                        : colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (fileSize.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    fileSize,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: isCurrentUser
                          ? Colors.white.withAlpha(200)
                          : colorScheme.onSurfaceVariant.withAlpha(175),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInfo(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 12, right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            DateFormat('HH:mm').format(message.createdAt),
            style: GoogleFonts.inter(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant.withAlpha(150),
            ),
          ),

          // Message status for current user
          if (isCurrentUser) ...[
            const SizedBox(width: 4),
            Icon(
              _getStatusIcon(),
              size: 12,
              color: _getStatusColor(colorScheme),
            ),
          ],
        ],
      ),
    );
  }

  IconData _getStatusIcon() {
    switch (status) {
      case MessageStatus.sending:
        return PhosphorIcons.clock();
      case MessageStatus.sent:
        return PhosphorIcons.check();
      case MessageStatus.delivered:
        return PhosphorIcons.checks();
      case MessageStatus.read:
        return PhosphorIcons.checks();
      case MessageStatus.failed:
        return PhosphorIcons.warning();
    }
  }

  Color _getStatusColor(ColorScheme colorScheme) {
    switch (status) {
      case MessageStatus.sending:
        return colorScheme.onSurfaceVariant.withAlpha(150);
      case MessageStatus.sent:
        return colorScheme.onSurfaceVariant.withAlpha(150);
      case MessageStatus.delivered:
        return colorScheme.onSurfaceVariant.withAlpha(150);
      case MessageStatus.read:
        return const Color(0xFF06B6D4); // Cyan for read
      case MessageStatus.failed:
        return colorScheme.error;
    }
  }

  IconData _getFileIcon(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();

    switch (extension) {
      case 'pdf':
        return PhosphorIcons.filePdf();
      case 'doc':
      case 'docx':
        return PhosphorIcons.fileDoc();
      case 'xls':
      case 'xlsx':
        return PhosphorIcons.fileXls();
      case 'ppt':
      case 'pptx':
        return PhosphorIcons.filePpt();
      case 'zip':
      case 'rar':
      case '7z':
        return PhosphorIcons.fileZip();
      case 'mp3':
      case 'wav':
      case 'flac':
        return PhosphorIcons.fileAudio();
      case 'mp4':
      case 'avi':
      case 'mov':
        return PhosphorIcons.fileVideo();
      default:
        return PhosphorIcons.file();
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
