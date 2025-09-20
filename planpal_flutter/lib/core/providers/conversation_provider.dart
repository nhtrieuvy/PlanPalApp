import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import '../repositories/conversation_repository.dart';
import '../dtos/conversation.dart';
import '../dtos/chat_message.dart';
import '../services/apis.dart';

/// State management for conversations and messaging
class ConversationProvider extends ChangeNotifier {
  final ConversationRepository _repository;

  ConversationProvider(String? token)
    : _repository = (() {
        final api = ApiClient(token: token);
        return ConversationRepository(api);
      })();

  // State variables
  List<Conversation> _conversations = [];
  final Map<String, List<ChatMessage>> _messages = {};
  final Map<String, bool> _loadingStates = {};
  String? _error;
  bool _isLoading = false;

  // Typing indicators for conversations
  final Map<String, Set<String>> _typingUsers = {};
  final Map<String, Timer?> _typingTimers = {};

  // Pagination cursors for messages
  final Map<String, String?> _nextCursors = {};
  final Map<String, bool> _hasMoreMessages = {};

  // Getters
  List<Conversation> get conversations => List.unmodifiable(_conversations);
  String? get error => _error;
  bool get isLoading => _isLoading;

  /// Get messages for a specific conversation
  List<ChatMessage> getMessages(String conversationId) {
    return List.unmodifiable(_messages[conversationId] ?? []);
  }

  /// Check if conversation is loading
  bool isConversationLoading(String conversationId) {
    return _loadingStates[conversationId] ?? false;
  }

  /// Get typing users for a conversation
  Set<String> getTypingUsers(String conversationId) {
    return Set.unmodifiable(_typingUsers[conversationId] ?? {});
  }

  /// Check if there are more messages to load
  bool hasMoreMessages(String conversationId) {
    return _hasMoreMessages[conversationId] ?? false;
  }

  /// Get conversation by ID
  Conversation? getConversation(String conversationId) {
    try {
      return _conversations.firstWhere((c) => c.id == conversationId);
    } catch (e) {
      return null;
    }
  }

  /// Load all conversations
  Future<void> loadConversations() async {
    if (_isLoading) return;

    _setLoading(true);
    _setError(null);

    try {
      final response = await _repository.getConversations();
      _conversations = response.conversations;
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  /// Refresh a specific conversation's data
  Future<void> refreshConversation(String conversationId) async {
    try {
      final updatedConversation = await _repository.getConversation(
        conversationId,
      );

      final conversationIndex = _conversations.indexWhere(
        (c) => c.id == conversationId,
      );
      if (conversationIndex >= 0) {
        _conversations[conversationIndex] = updatedConversation;
        notifyListeners();
      }
    } catch (e) {
      // Fallback to full refresh if specific conversation update fails
      await loadConversations();
    }
  }

  /// Load messages for a conversation
  Future<void> loadMessages(
    String conversationId, {
    bool refresh = false,
  }) async {
    if (_loadingStates[conversationId] == true) return;

    _setConversationLoading(conversationId, true);
    _setError(null);

    try {
      final beforeId = refresh ? null : _nextCursors[conversationId];
      final response = await _repository.getConversationMessages(
        conversationId,
        beforeId: beforeId,
      );

      if (refresh) {
        _messages[conversationId] = response.messages;
      } else {
        final existingMessages = _messages[conversationId] ?? [];
        _messages[conversationId] = [...existingMessages, ...response.messages];
      }

      _nextCursors[conversationId] = response.nextCursor;
      _hasMoreMessages[conversationId] = response.hasMore;

      notifyListeners();
    } catch (e) {
      _setError(e.toString());
    } finally {
      _setConversationLoading(conversationId, false);
    }
  }

  /// Create or get direct conversation with a user
  Future<String?> createDirectConversation(String userId) async {
    _setLoading(true);
    _setError(null);

    try {
      final response = await _repository.createDirectConversation(userId);

      // Add or update conversation in list
      final existingIndex = _conversations.indexWhere(
        (c) => c.id == response.conversation.id,
      );
      if (existingIndex >= 0) {
        _conversations[existingIndex] = response.conversation;
      } else {
        _conversations.insert(0, response.conversation);
      }

      notifyListeners();
      return response.conversation.id;
    } catch (e) {
      _setError(e.toString());
      return null;
    } finally {
      _setLoading(false);
    }
  }

  /// Send text message
  Future<bool> sendTextMessage(
    String conversationId,
    String content, {
    String? replyToId,
  }) async {
    if (content.trim().isEmpty) return false;

    try {
      final message = await _repository.sendTextMessage(
        conversationId,
        content.trim(),
        replyToId: replyToId,
      );

      // Add message to local state
      _addMessageToConversation(conversationId, message);

      // Update conversation's last message
      _updateConversationLastMessage(conversationId, message);

      return true;
    } catch (e) {
      _setError(e.toString());
      return false;
    }
  }

  /// Send image message
  Future<bool> sendImageMessage(
    String conversationId,
    String imageUrl,
    String fileName, {
    int? fileSize,
    String? replyToId,
  }) async {
    if (imageUrl.trim().isEmpty || fileName.trim().isEmpty) return false;

    try {
      final message = await _repository.sendImageMessage(
        conversationId,
        imageUrl.trim(),
        fileName.trim(),
        fileSize: fileSize,
        replyToId: replyToId,
      );

      // Add message to local state
      _addMessageToConversation(conversationId, message);

      // Update conversation's last message
      _updateConversationLastMessage(conversationId, message);

      return true;
    } catch (e) {
      _setError(e.toString());
      return false;
    }
  }

  /// Send image file (uploads first) - convenience wrapper around repository
  Future<bool> sendImageFile(
    String conversationId,
    File imageFile, {
    String? replyToId,
  }) async {
    try {
      final message = await _repository.sendImageFile(
        conversationId,
        imageFile,
        replyToId: replyToId,
      );

      // Add message to local state
      _addMessageToConversation(conversationId, message);

      // Update conversation's last message
      _updateConversationLastMessage(conversationId, message);

      return true;
    } catch (e) {
      _setError(e.toString());
      return false;
    }
  }

  /// Send file message
  Future<bool> sendFileMessage(
    String conversationId,
    String fileUrl,
    String fileName, {
    String? replyToId,
  }) async {
    if (fileUrl.trim().isEmpty || fileName.trim().isEmpty) return false;

    try {
      final message = await _repository.sendFileMessage(
        conversationId,
        fileUrl.trim(),
        fileName.trim(),
        replyToId: replyToId,
      );

      // Add message to local state
      _addMessageToConversation(conversationId, message);

      // Update conversation's last message
      _updateConversationLastMessage(conversationId, message);

      return true;
    } catch (e) {
      _setError(e.toString());
      return false;
    }
  }

  /// Send file attachment (uploads first) - convenience wrapper around repository
  Future<bool> sendFileAttachment(
    String conversationId,
    File file, {
    String? replyToId,
  }) async {
    try {
      final message = await _repository.sendFileAttachment(
        conversationId,
        file,
        replyToId: replyToId,
      );

      // Add message to local state
      _addMessageToConversation(conversationId, message);

      // Update conversation's last message
      _updateConversationLastMessage(conversationId, message);

      return true;
    } catch (e) {
      _setError(e.toString());
      return false;
    }
  }

  /// Send location message
  Future<bool> sendLocationMessage(
    String conversationId,
    double latitude,
    double longitude,
    String locationName, {
    String? replyToId,
  }) async {
    try {
      final message = await _repository.sendLocationMessage(
        conversationId,
        latitude,
        longitude,
        locationName,
        replyToId: replyToId,
      );

      // Add message to local state
      _addMessageToConversation(conversationId, message);

      // Update conversation's last message
      _updateConversationLastMessage(conversationId, message);

      return true;
    } catch (e) {
      _setError(e.toString());
      return false;
    }
  }

  /// Mark messages as read
  Future<void> markMessagesAsRead(
    String conversationId,
    List<String> messageIds,
  ) async {
    if (messageIds.isEmpty) return;

    try {
      await _repository.markMessagesAsRead(
        conversationId,
        MarkMessagesReadRequest(messageIds: messageIds),
      );

      // Update local unread count more efficiently
      final conversationIndex = _conversations.indexWhere(
        (c) => c.id == conversationId,
      );
      if (conversationIndex >= 0) {
        final currentConversation = _conversations[conversationIndex];
        final newUnreadCount =
            (currentConversation.unreadCount - messageIds.length)
                .clamp(0, double.infinity)
                .toInt();

        final updatedConversation = currentConversation.copyWith(
          unreadCount: newUnreadCount,
        );
        _conversations[conversationIndex] = updatedConversation;
        notifyListeners();
      }
    } catch (e) {
      _setError(e.toString());
    }
  }

  /// Add incoming message from WebSocket
  void addIncomingMessage(ChatMessage message) {
    if (message.conversationId != null) {
      _addMessageToConversation(message.conversationId!, message);
      _updateConversationLastMessage(message.conversationId!, message);
    }
  }

  /// Update typing indicators
  void updateTypingIndicator(
    String conversationId,
    String userId,
    bool isTyping,
  ) {
    if (isTyping) {
      _typingUsers[conversationId] ??= {};
      _typingUsers[conversationId]!.add(userId);

      // Clear typing indicator after 3 seconds
      _typingTimers[conversationId]?.cancel();
      _typingTimers[conversationId] = Timer(const Duration(seconds: 3), () {
        _typingUsers[conversationId]?.remove(userId);
        notifyListeners();
      });
    } else {
      _typingUsers[conversationId]?.remove(userId);
      _typingTimers[conversationId]?.cancel();
    }

    notifyListeners();
  }

  /// Clear error
  void clearError() {
    _setError(null);
  }

  /// Refresh conversations
  Future<void> refresh() async {
    await loadConversations();
  }

  /// Refresh messages for a conversation
  Future<void> refreshMessages(String conversationId) async {
    await loadMessages(conversationId, refresh: true);
  }

  // Private helper methods
  void _addMessageToConversation(String conversationId, ChatMessage message) {
    _messages[conversationId] ??= [];
    _messages[conversationId]!.insert(0, message);
    notifyListeners();
  }

  void _updateConversationLastMessage(
    String conversationId,
    ChatMessage message,
  ) {
    final conversationIndex = _conversations.indexWhere(
      (c) => c.id == conversationId,
    );
    if (conversationIndex >= 0) {
      final lastMessage = LastMessage(
        id: message.id,
        content: message.content,
        messageType: message.messageType,
        sender: message.sender.username,
        createdAt: message.createdAt,
      );

      final updatedConversation = _conversations[conversationIndex].copyWith(
        lastMessage: lastMessage,
        lastMessageAt: message.createdAt,
      );

      // Move conversation to top of list
      _conversations.removeAt(conversationIndex);
      _conversations.insert(0, updatedConversation);

      notifyListeners();
    }
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setConversationLoading(String conversationId, bool loading) {
    _loadingStates[conversationId] = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }

  @override
  void dispose() {
    // Cancel all typing timers
    for (final timer in _typingTimers.values) {
      timer?.cancel();
    }
    _typingTimers.clear();
    super.dispose();
  }
}

/// Extension methods for conversation filtering and searching
extension ConversationProviderExtensions on ConversationProvider {
  /// Search conversations by name or participant
  List<Conversation> searchConversations(String query) {
    if (query.isEmpty) return conversations;

    final lowercaseQuery = query.toLowerCase();
    return conversations.where((conversation) {
      // Search by conversation name
      if (conversation.displayName.toLowerCase().contains(lowercaseQuery)) {
        return true;
      }

      // Search by participant names
      for (final participant in conversation.participants) {
        if (participant.username.toLowerCase().contains(lowercaseQuery) ||
            participant.fullName.toLowerCase().contains(lowercaseQuery)) {
          return true;
        }
      }

      return false;
    }).toList();
  }

  /// Get conversations with unread messages
  List<Conversation> get unreadConversations {
    return conversations.where((c) => c.hasUnreadMessages).toList();
  }

  /// Get total unread count across all conversations
  int get totalUnreadCount {
    return conversations.fold(
      0,
      (sum, conversation) => sum + conversation.unreadCount,
    );
  }

  /// Get direct conversations only
  List<Conversation> get directConversations {
    return conversations.where((c) => c.isDirect).toList();
  }

  /// Get group conversations only
  List<Conversation> get groupConversations {
    return conversations.where((c) => c.isGroup).toList();
  }

  /// Find conversation for a group by group ID
  Future<Conversation?> findOrCreateGroupConversation(String groupId) async {
    // First, load conversations if not loaded
    if (_conversations.isEmpty) {
      await loadConversations();
    }

    // Look for existing group conversation
    for (final conversation in _conversations) {
      if (conversation.conversationType == ConversationType.group &&
          conversation.group?.id == groupId) {
        return conversation;
      }
    }

    // No conversation found for this group
    return null;
  }
}
