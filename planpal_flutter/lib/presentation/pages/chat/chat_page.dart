import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/dtos/chat_message.dart';
import '../../../core/dtos/conversation.dart';
import '../../../core/riverpod/auth_notifier.dart';
import '../../../core/riverpod/conversation_providers.dart';
import '../../../core/services/chat_websocket_service.dart' as ws;
import '../../../core/theme/app_colors.dart';
import '../../../shared/ui_states/ui_states.dart';
import '../../widgets/chat/message_bubble.dart';
import '../../widgets/chat/message_input.dart';
import '../../widgets/chat/typing_indicator.dart';
import '../../widgets/common/refreshable_page_wrapper.dart';

class ChatPage extends ConsumerStatefulWidget {
  final Conversation conversation;

  const ChatPage({super.key, required this.conversation});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage>
    with WidgetsBindingObserver, RefreshablePage {
  final ScrollController _scrollController = ScrollController();

  late ws.ChatWebSocketService _webSocketService;
  StreamSubscription<ws.WebSocketEvent>? _eventSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeChat();
    _setupScrollListener();
  }

  @override
  Future<void> onRefresh() async {
    await ref.read(messagesProvider(widget.conversation.id).notifier).refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _eventSubscription?.cancel();
    _scrollController.dispose();
    _webSocketService.disconnect();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _connectWebSocket();
    } else if (state == AppLifecycleState.paused) {
      _webSocketService.disconnect();
    }
  }

  void _initializeChat() {
    _webSocketService = ref.read(
      chatWebSocketServiceProvider(widget.conversation.id),
    );
    _connectWebSocket();
    _setupWebSocketListeners();
  }

  void _connectWebSocket() {
    final authState = ref.read(authNotifierProvider);
    final token = authState.token;
    if (token != null && token.isNotEmpty) {
      _webSocketService.connect(widget.conversation.id, token);
    }
  }

  void _setupWebSocketListeners() {
    _eventSubscription = _webSocketService.eventStream.listen(
      _handleWebSocketEvent,
      onError: (error) {
        debugPrint('Chat WebSocket error: $error');
      },
    );
  }

  void _handleWebSocketEvent(ws.WebSocketEvent event) {
    if (!mounted) return;

    switch (event.type) {
      case ws.WebSocketEventType.chatMessage:
        _handleNewMessage(event.data);
        break;
      case ws.WebSocketEventType.typingStart:
        _handleTypingStart(event.data);
        break;
      case ws.WebSocketEventType.typingStop:
        _handleTypingStop(event.data);
        break;
      case ws.WebSocketEventType.messageRead:
        _handleMessageRead(event.data);
        break;
      case ws.WebSocketEventType.userJoined:
      case ws.WebSocketEventType.userLeft:
      case ws.WebSocketEventType.error:
        debugPrint('Chat event ${event.type.value}: ${event.data}');
        break;
    }
  }

  void _handleNewMessage(Map<String, dynamic> data) {
    final currentUserId = ref.read(authNotifierProvider).user?.id;
    final senderId = data['sender'] is Map<String, dynamic>
        ? (data['sender'] as Map<String, dynamic>)['id'] as String?
        : null;

    if (senderId != null && senderId == currentUserId) {
      return;
    }

    ref.read(messagesProvider(widget.conversation.id).notifier).refresh();
    ref.invalidate(conversationListProvider);
  }

  void _handleTypingStart(Map<String, dynamic> data) {
    final username = data['username'] as String?;
    if (username == null || username.isEmpty) return;
    ref
        .read(typingUsersProvider(widget.conversation.id).notifier)
        .setTyping(username, true);
  }

  void _handleTypingStop(Map<String, dynamic> data) {
    final username = data['username'] as String?;
    if (username == null || username.isEmpty) return;
    ref
        .read(typingUsersProvider(widget.conversation.id).notifier)
        .setTyping(username, false);
  }

  void _handleMessageRead(Map<String, dynamic> data) {
    debugPrint('Messages marked as read: ${data['message_ids']}');
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        _loadMoreMessages();
      }
    });
  }

  void _loadMoreMessages() {
    ref.read(messagesProvider(widget.conversation.id).notifier).loadMore();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _sendMessage(String content) async {
    if (content.trim().isEmpty) return;

    final success = await ref
        .read(messagesProvider(widget.conversation.id).notifier)
        .sendTextMessage(content.trim());

    if (success) {
      _scrollToBottom();
    } else {
      _showSnackBar('Khong the gui tin nhan. Vui long thu lai.');
    }
  }

  Future<void> _sendImage(File imageFile) async {
    try {
      final success = await ref
          .read(messagesProvider(widget.conversation.id).notifier)
          .sendImageFile(imageFile);

      if (success) {
        _scrollToBottom();
      } else {
        _showSnackBar('Khong the gui anh. Vui long thu lai.');
      }
    } catch (e) {
      _showSnackBar('Loi gui anh: $e');
    }
  }

  Future<void> _sendLocation(
    double lat,
    double lng,
    String? locationName,
  ) async {
    try {
      final success = await ref
          .read(messagesProvider(widget.conversation.id).notifier)
          .sendLocationMessage(lat, lng, locationName ?? 'Vi tri duoc chia se');

      if (success) {
        _scrollToBottom();
      } else {
        _showSnackBar('Khong the chia se vi tri. Vui long thu lai.');
      }
    } catch (e) {
      _showSnackBar('Loi chia se vi tri: $e');
    }
  }

  Future<void> _sendFile(File file, String _) async {
    try {
      final success = await ref
          .read(messagesProvider(widget.conversation.id).notifier)
          .sendFileAttachment(file);

      if (success) {
        _scrollToBottom();
      } else {
        _showSnackBar('Khong the gui file. Vui long thu lai.');
      }
    } catch (e) {
      _showSnackBar('Loi gui file: $e');
    }
  }

  void _onTypingStart() {
    _webSocketService.sendTypingIndicator(true);
  }

  void _onTypingStop() {
    _webSocketService.sendTypingIndicator(false);
  }

  bool _shouldShowAvatar(int index, List<ChatMessage> messages) {
    if (index == messages.length - 1) {
      return true;
    }

    final current = messages[index];
    final next = messages[index + 1];
    return current.sender.id != next.sender.id ||
        current.createdAt.difference(next.createdAt).inMinutes > 5;
  }

  bool _shouldShowTimestamp(int index, List<ChatMessage> messages) {
    if (index == 0) return true;

    final current = messages[index];
    final previous = messages[index - 1];
    return current.sender.id != previous.sender.id ||
        current.createdAt.difference(previous.createdAt).inMinutes > 15;
  }

  Future<void> _openUrlString(
    String? url, {
    required String failureMessage,
  }) async {
    if (url == null || url.isEmpty) {
      _showSnackBar(failureMessage);
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showSnackBar(failureMessage);
      return;
    }

    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!launched) {
      _showSnackBar(failureMessage);
    }
  }

  Future<void> _handleMessageTap(ChatMessage message) async {
    if (message.isLocationMessage) {
      await _openUrlString(
        message.locationUrl,
        failureMessage: 'Khong the mo vi tri nay.',
      );
      return;
    }

    if (message.isFileMessage) {
      await _openUrlString(
        message.attachmentUrl,
        failureMessage: 'Khong the mo tep dinh kem.',
      );
    }
  }

  Future<void> _showImagePreview(ChatMessage message) async {
    final imageUrl = message.attachmentUrl ?? message.content;
    if (imageUrl.isEmpty || !mounted) return;

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withAlpha(220),
      builder: (dialogContext) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Text(
                          'Khong the tai anh.',
                          style: TextStyle(color: Colors.white),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                top: 24,
                right: 16,
                child: IconButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: _buildAppBar(theme),
      body: RefreshablePageWrapper(
        onRefresh: onRefresh,
        child: Column(
          children: [
            _buildConnectionStatus(theme),
            Expanded(child: _buildMessagesList()),
            _buildTypingIndicator(),
            MessageInput(
              onSendMessage: _sendMessage,
              onSendImage: _sendImage,
              onSendLocation: _sendLocation,
              onSendFile: _sendFile,
              onStartTyping: _onTypingStart,
              onStopTyping: _onTypingStop,
              isEnabled: true,
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme) {
    return AppBar(
      backgroundColor: theme.colorScheme.surface,
      elevation: 0,
      leading: IconButton(
        onPressed: () => Navigator.of(context).pop(),
        icon: Icon(
          PhosphorIcons.arrowLeft(),
          color: theme.colorScheme.onSurface,
        ),
      ),
      title: Row(
        children: [
          _buildConversationAvatar(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.conversation.displayName,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                _buildSubtitle(theme),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (widget.conversation.isDirect)
          IconButton(
            onPressed: _showUserProfile,
            icon: Icon(
              PhosphorIcons.user(),
              color: theme.colorScheme.onSurface,
            ),
          ),
        IconButton(
          onPressed: _showConversationOptions,
          icon: Icon(
            PhosphorIcons.dotsThreeVertical(),
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildConversationAvatar() {
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: AppColors.primaryGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: widget.conversation.avatarUrl.isNotEmpty
          ? ClipOval(
              child: Image.network(
                widget.conversation.avatarUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildAvatarPlaceholder();
                },
              ),
            )
          : _buildAvatarPlaceholder(),
    );
  }

  Widget _buildAvatarPlaceholder() {
    final displayName = widget.conversation.displayName;
    final avatarText = displayName.isNotEmpty
        ? displayName.substring(0, 1).toUpperCase()
        : (widget.conversation.isGroup ? 'G' : 'U');

    return Center(
      child: Text(
        avatarText,
        style: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildSubtitle(ThemeData theme) {
    if (widget.conversation.isDirect) {
      return Text(
        widget.conversation.isOtherUserOnline ? 'Online' : 'Offline',
        style: GoogleFonts.inter(
          fontSize: 12,
          color: widget.conversation.isOtherUserOnline
              ? AppColors.success
              : theme.colorScheme.onSurface.withAlpha(150),
        ),
      );
    }

    final memberCount = widget.conversation.participants.length;
    return Text(
      '$memberCount members',
      style: GoogleFonts.inter(
        fontSize: 12,
        color: theme.colorScheme.onSurface.withAlpha(150),
      ),
    );
  }

  Widget _buildConnectionStatus(ThemeData theme) {
    final connectionStateAsync = ref.watch(
      chatConnectionStateStreamProvider(widget.conversation.id),
    );
    final connectionState = connectionStateAsync.valueOrNull;

    if (connectionState == null ||
        connectionState == ws.ConnectionState.connected ||
        connectionState == ws.ConnectionState.disconnected) {
      return const SizedBox.shrink();
    }

    final isFailed = connectionState == ws.ConnectionState.failed;
    final bg = isFailed
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.tertiaryContainer;
    final fg = isFailed
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onTertiaryContainer;
    final message = isFailed
        ? 'Mat ket noi realtime. Dang thu lai...'
        : 'Dang ket noi realtime...';

    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    final messagesAsync = ref.watch(messagesProvider(widget.conversation.id));

    return messagesAsync.when(
      loading: () => const AppSkeleton.chat(itemCount: 10),
      error: (error, _) => AppError(
        message: 'Error loading messages: $error',
        onRetry: () => ref.refresh(messagesProvider(widget.conversation.id)),
      ),
      data: (msgState) {
        final messages = msgState.messages;

        if (messages.isEmpty) {
          return const AppEmpty(
            icon: Icons.chat_bubble_outline,
            title: 'No messages yet',
            description: 'Start the conversation!',
          );
        }

        final currentUserId = ref.read(authNotifierProvider).user?.id ?? '';

        return ListView.builder(
          controller: _scrollController,
          reverse: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: messages.length + (msgState.isLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (msgState.isLoadingMore && index == messages.length) {
              return const AppLoading(
                inline: true,
                padding: EdgeInsets.all(16),
                size: 20,
              );
            }

            final message = messages[index];

            return MessageBubble(
              message: message,
              isCurrentUser: message.sender.id == currentUserId,
              showAvatar: _shouldShowAvatar(index, messages),
              showTimestamp: _shouldShowTimestamp(index, messages),
              status: MessageStatus.sent,
              onTap: () => _handleMessageTap(message),
              onImageTap: () => _showImagePreview(message),
            );
          },
        );
      },
    );
  }

  Widget _buildTypingIndicator() {
    final typingUsers = ref.watch(typingUsersProvider(widget.conversation.id));
    if (typingUsers.isEmpty) {
      return const SizedBox.shrink();
    }

    return TypingIndicator(
      typingUsers: typingUsers.toList(),
      isVisible: typingUsers.isNotEmpty,
    );
  }

  void _showUserProfile() {
    _showSnackBar('User profile not implemented yet');
  }

  void _showConversationOptions() {
    _showSnackBar('Conversation options not implemented yet');
  }
}
