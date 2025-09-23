import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'dart:async';
import 'dart:io';
import '../../../core/providers/conversation_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/dtos/conversation.dart';
import '../../../core/dtos/chat_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/chat_websocket_service.dart' as ws;
import '../../widgets/common/loading_state.dart';
import '../../widgets/chat/message_bubble.dart';
import '../../widgets/chat/message_input.dart';
import '../../widgets/chat/typing_indicator.dart';
import '../../widgets/common/refreshable_page_wrapper.dart';

class ChatPage extends StatefulWidget {
  final Conversation conversation;

  const ChatPage({super.key, required this.conversation});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage>
    with WidgetsBindingObserver, RefreshablePage {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();

  // WebSocket service for realtime messaging
  late ws.ChatWebSocketService _webSocketService;
  StreamSubscription? _eventSubscription;
  StreamSubscription? _connectionSubscription;

  bool _isLoadingMore = false;
  bool _hasReachedTop = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeChat();
    _setupScrollListener();
  }

  @override
  Future<void> onRefresh() async {
    final conversationProvider = context.read<ConversationProvider>();
    await conversationProvider.loadMessages(
      widget.conversation.id,
      refresh: true,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _scrollController.dispose();
    _eventSubscription?.cancel();
    _connectionSubscription?.cancel();

    // Disconnect WebSocket when leaving chat
    _webSocketService.disconnect();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _connectWebSocket();
    } else if (state == AppLifecycleState.paused) {
      // Disconnect WebSocket when app goes to background
      _webSocketService.disconnect();
    }
  }

  void _initializeChat() {
    final conversationProvider = context.read<ConversationProvider>();

    // Load initial messages
    conversationProvider.loadMessages(widget.conversation.id, refresh: true);

    // Setup WebSocket for realtime messaging
    _webSocketService = ws.ChatWebSocketService();
    _connectWebSocket();
    _setupWebSocketListeners();
  }

  void _connectWebSocket() {
    // Connect WebSocket with authentication
    final authProvider = context.read<AuthProvider>();
    if (authProvider.token != null) {
      _webSocketService.connect(widget.conversation.id, authProvider.token!);
    }
  }

  void _setupWebSocketListeners() {
    // Listen to WebSocket events
    _eventSubscription = _webSocketService.eventStream.listen(
      (event) => _handleWebSocketEvent(event),
      onError: (error) {
        debugPrint('WebSocket error: $error');
        // Optionally show user-friendly error message
      },
    );

    // For now, we'll just track connection state through events
    // Connection state stream can be added later if needed
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
        // Handle user presence if needed
        debugPrint('User presence changed: ${event.data}');
        break;
      case ws.WebSocketEventType.error:
        debugPrint('WebSocket event error: ${event.data}');
        break;
    }
  }

  void _handleNewMessage(Map<String, dynamic> data) {
    final conversationProvider = context.read<ConversationProvider>();
    final authProvider = context.read<AuthProvider>();

    // Extract sender info from WebSocket data to avoid duplicate messages
    final senderId = data['sender']?['id'] as String?;
    final currentUserId = authProvider.user?.id;

    // If this message is from the current user, they already have it in their local state
    // from the sendTextMessage response, so we don't need to refresh
    if (senderId != null && senderId == currentUserId) {
      debugPrint(
        'Skipping WebSocket message refresh for own message from $senderId',
      );
      return;
    }

    // For messages from other users, refresh to get the new message
    debugPrint('Refreshing messages for new message from $senderId');
    conversationProvider.loadMessages(widget.conversation.id, refresh: true);
  }

  void _handleTypingStart(Map<String, dynamic> data) {
    final username = data['username'] as String?;
    debugPrint('User $username started typing');
    // TODO: Show typing indicator in UI
  }

  void _handleTypingStop(Map<String, dynamic> data) {
    debugPrint('User stopped typing');
    // TODO: Hide typing indicator in UI
  }

  void _handleMessageRead(Map<String, dynamic> data) {
    final messageIds = data['message_ids'] as List<dynamic>?;
    if (messageIds != null) {
      debugPrint('Messages marked as read: $messageIds');
      // TODO: Update message read status in UI
    }
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        _loadMoreMessages();
      }
    });
  }

  void _loadMoreMessages() {
    if (_isLoadingMore || _hasReachedTop) return;

    setState(() {
      _isLoadingMore = true;
    });

    final conversationProvider = context.read<ConversationProvider>();
    conversationProvider.loadMessages(widget.conversation.id).then((_) {
      setState(() {
        _isLoadingMore = false;
        _hasReachedTop = !conversationProvider.hasMoreMessages(
          widget.conversation.id,
        );
      });
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage(String content) {
    if (content.trim().isEmpty) return;

    final conversationProvider = context.read<ConversationProvider>();
    conversationProvider.sendTextMessage(widget.conversation.id, content).then((
      success,
    ) {
      if (success) {
        _scrollToBottom();
      }
    });
  }

  void _sendImage(File imageFile) async {
    try {
      // Upload image first (client-side) and send with valid URL
      final provider = Provider.of<ConversationProvider>(
        context,
        listen: false,
      );
      final success = await provider.sendImageFile(
        widget.conversation.id,
        imageFile,
      );

      if (!success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Không thể gửi ảnh. Vui lòng thử lại.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi gửi ảnh: ${e.toString()}')));
      }
    }
  }

  void _sendLocation(double lat, double lng, String? locationName) async {
    try {
      final provider = Provider.of<ConversationProvider>(
        context,
        listen: false,
      );
      final success = await provider.sendLocationMessage(
        widget.conversation.id,
        lat,
        lng,
        locationName ?? 'Vị trí được chia sẻ',
      );

      if (!success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Không thể chia sẻ vị trí. Vui lòng thử lại.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi chia sẻ vị trí: ${e.toString()}')),
        );
      }
    }
  }

  void _sendFile(File file, String fileName) async {
    try {
      // Upload file first (client-side) and send with valid URL
      final provider = Provider.of<ConversationProvider>(
        context,
        listen: false,
      );
      final success = await provider.sendFileAttachment(
        widget.conversation.id,
        file,
      );

      if (!success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Không thể gửi file. Vui lòng thử lại.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi gửi file: ${e.toString()}')),
        );
      }
    }
  }

  void _onTypingStart() {
    // Send typing indicator via WebSocket
    _webSocketService.sendTypingIndicator(true);
  }

  void _onTypingStop() {
    // Stop typing indicator via WebSocket
    _webSocketService.sendTypingIndicator(false);
  }

  bool _shouldShowAvatar(int index, List<ChatMessage> messages) {
    if (index == messages.length - 1) {
      return true; // Last message always shows avatar
    }

    final currentMessage = messages[index];
    final nextMessage = messages[index + 1];

    // Show avatar if next message is from different sender or there's a time gap
    return currentMessage.sender.id != nextMessage.sender.id ||
        currentMessage.createdAt.difference(nextMessage.createdAt).inMinutes >
            5;
  }

  bool _shouldShowTimestamp(int index, List<ChatMessage> messages) {
    if (index == 0) return true; // First message always shows timestamp

    final currentMessage = messages[index];
    final previousMessage = messages[index - 1];

    // Show timestamp if there's significant time gap or different sender
    return currentMessage.sender.id != previousMessage.sender.id ||
        currentMessage.createdAt
                .difference(previousMessage.createdAt)
                .inMinutes >
            15;
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
            Expanded(child: _buildMessagesList(theme)),
            _buildTypingIndicator(),
            MessageInput(
              onSendMessage: _sendMessage,
              onSendImage: _sendImage,
              onSendLocation: _sendLocation,
              onSendFile: _sendFile,
              onStartTyping: _onTypingStart,
              onStopTyping: _onTypingStop,
              isEnabled: true, // TODO: Use proper connection state
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
        onPressed: () => Navigator.pop(context),
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
            onPressed: () => _showUserProfile(),
            icon: Icon(
              PhosphorIcons.user(),
              color: theme.colorScheme.onSurface,
            ),
          ),
        IconButton(
          onPressed: () => _showConversationOptions(),
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
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
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
                errorBuilder: (context, error, stackTrace) =>
                    _buildAvatarPlaceholder(),
              ),
            )
          : _buildAvatarPlaceholder(),
    );
  }

  Widget _buildAvatarPlaceholder() {
    return Center(
      child: Text(
        widget.conversation.isGroup
            ? widget.conversation.group?.name.substring(0, 1).toUpperCase() ??
                  'G'
            : widget.conversation.otherParticipant?.fullName
                      .substring(0, 1)
                      .toUpperCase() ??
                  'U',
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
    } else {
      final memberCount = widget.conversation.participants.length;
      return Text(
        '$memberCount members',
        style: GoogleFonts.inter(
          fontSize: 12,
          color: theme.colorScheme.onSurface.withAlpha(150),
        ),
      );
    }
  }

  Widget _buildConnectionStatus(ThemeData theme) {
    // TODO: Implement proper connection status when WebSocket is ready
    // For now, don't show any connection status
    return const SizedBox.shrink();
  }

  Widget _buildMessagesList(ThemeData theme) {
    return Consumer<ConversationProvider>(
      builder: (context, provider, child) {
        final messages = provider.getMessages(widget.conversation.id);
        final isLoading = provider.isConversationLoading(
          widget.conversation.id,
        );

        if (isLoading && messages.isEmpty) {
          return const LoadingState(message: 'Loading messages...');
        }

        if (messages.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  PhosphorIcons.chatCircle(),
                  size: 48,
                  color: theme.colorScheme.onSurface.withAlpha(75),
                ),
                const SizedBox(height: 16),
                Text(
                  'No messages yet',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface.withAlpha(175),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Start the conversation!',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: theme.colorScheme.onSurface.withAlpha(125),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          controller: _scrollController,
          reverse: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: messages.length + (_isLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (_isLoadingMore && index == messages.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: LoadingState(showMessage: false, size: 20),
              );
            }

            final message = messages[index];
            final authProvider = context.read<AuthProvider>();
            final currentUserId = authProvider.user?.id ?? '';

            return MessageBubble(
              message: message,
              isCurrentUser: message.sender.id == currentUserId,
              showAvatar: _shouldShowAvatar(index, messages),
              showTimestamp: _shouldShowTimestamp(index, messages),
              status: MessageStatus
                  .sent, // You can implement proper status tracking later
            );
          },
        );
      },
    );
  }

  Widget _buildTypingIndicator() {
    return Consumer<ConversationProvider>(
      builder: (context, provider, child) {
        final typingUsers = provider.getTypingUsers(widget.conversation.id);

        if (typingUsers.isEmpty) {
          return const SizedBox.shrink();
        }

        return TypingIndicator(
          typingUsers: typingUsers.toList(),
          isVisible: typingUsers.isNotEmpty,
        );
      },
    );
  }

  void _showUserProfile() {
    // TODO: Navigate to user profile
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('User profile not implemented yet')),
    );
  }

  void _showConversationOptions() {
    // TODO: Show conversation options (mute, block, etc.)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Conversation options not implemented yet')),
    );
  }
}
