import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../dtos/conversation.dart';
import '../dtos/chat_message.dart';
import '../repositories/conversation_repository.dart';
import '../services/chat_websocket_service.dart' as ws;
import 'repository_providers.dart';

// ============================================================
// Conversation List
// ============================================================

class ConversationListNotifier extends AsyncNotifier<List<Conversation>> {
  late ConversationRepository _repo;

  @override
  Future<List<Conversation>> build() async {
    _repo = ref.watch(conversationRepositoryProvider);
    final response = await _repo.getConversations();
    return response.conversations;
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final response = await _repo.getConversations();
      return response.conversations;
    });
  }

  void markConversationRead(String conversationId) {
    final current = state.valueOrNull;
    if (current == null) return;

    state = AsyncData([
      for (final conversation in current)
        if (conversation.id == conversationId)
          conversation.copyWith(unreadCount: 0)
        else
          conversation,
    ]);
  }
}

final conversationListProvider =
    AsyncNotifierProvider<ConversationListNotifier, List<Conversation>>(
      ConversationListNotifier.new,
    );

/// Total unread count across all conversations
final totalUnreadCountProvider = Provider<int>((ref) {
  final conversations = ref.watch(conversationListProvider).valueOrNull ?? [];
  return conversations.fold(0, (sum, c) => sum + c.unreadCount);
});

/// Server-side conversation search (family keyed by query string)
final conversationSearchProvider =
    FutureProvider.family<List<Conversation>, String>((ref, query) async {
      if (query.isEmpty) return [];
      final repo = ref.watch(conversationRepositoryProvider);
      final response = await repo.getConversations(query: query);
      return response.conversations;
    });

// ============================================================
// Messages per conversation (family provider)
// ============================================================

class MessagesState {
  final List<ChatMessage> messages;
  final bool hasMore;
  final String? nextCursor;
  final bool isLoadingMore;

  const MessagesState({
    this.messages = const [],
    this.hasMore = true,
    this.nextCursor,
    this.isLoadingMore = false,
  });

  MessagesState copyWith({
    List<ChatMessage>? messages,
    bool? hasMore,
    String? nextCursor,
    bool? isLoadingMore,
  }) {
    return MessagesState(
      messages: messages ?? this.messages,
      hasMore: hasMore ?? this.hasMore,
      nextCursor: nextCursor,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

class MessagesNotifier extends FamilyAsyncNotifier<MessagesState, String> {
  late ConversationRepository _repo;
  late String _conversationId;

  @override
  Future<MessagesState> build(String arg) async {
    _conversationId = arg;
    _repo = ref.watch(conversationRepositoryProvider);
    final response = await _repo.getConversationMessages(_conversationId);
    _scheduleMarkMessagesAsRead(response.messages);
    return MessagesState(
      messages: response.messages,
      hasMore: response.hasMore,
      nextCursor: response.nextCursor,
    );
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.isLoadingMore) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final response = await _repo.getConversationMessages(
        _conversationId,
        beforeId: current.nextCursor,
      );
      state = AsyncData(
        current.copyWith(
          messages: [...current.messages, ...response.messages],
          hasMore: response.hasMore,
          nextCursor: response.nextCursor,
          isLoadingMore: false,
        ),
      );
      _scheduleMarkMessagesAsRead(response.messages);
    } catch (e) {
      state = AsyncData(current.copyWith(isLoadingMore: false));
    }
  }

  /// Add a message at the top (newest first)
  void addMessage(ChatMessage message) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(messages: [message, ...current.messages]),
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final response = await _repo.getConversationMessages(_conversationId);
      _scheduleMarkMessagesAsRead(response.messages);
      return MessagesState(
        messages: response.messages,
        hasMore: response.hasMore,
        nextCursor: response.nextCursor,
      );
    });
  }

  Future<bool> sendTextMessage(String content) async {
    if (content.trim().isEmpty) return false;
    try {
      final message = await _repo.sendTextMessage(
        _conversationId,
        content.trim(),
      );
      addMessage(message);
      ref.invalidate(conversationListProvider);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sendImageFile(File imageFile) async {
    try {
      final message = await _repo.sendImageFile(_conversationId, imageFile);
      addMessage(message);
      ref.invalidate(conversationListProvider);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sendFileAttachment(File file) async {
    try {
      final message = await _repo.sendFileAttachment(_conversationId, file);
      addMessage(message);
      ref.invalidate(conversationListProvider);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sendLocationMessage(
    double lat,
    double lng,
    String locationName,
  ) async {
    try {
      final message = await _repo.sendLocationMessage(
        _conversationId,
        lat,
        lng,
        locationName,
      );
      addMessage(message);
      ref.invalidate(conversationListProvider);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _scheduleMarkMessagesAsRead(List<ChatMessage> messages) {
    Future.microtask(() async {
      final currentUserId = _repo.currentUserId;
      if (currentUserId == null) return;

      final messageIds = messages
          .where(
            (message) =>
                !message.isDeleted && message.sender.id != currentUserId,
          )
          .map((message) => message.id)
          .toSet()
          .toList();

      if (messageIds.isEmpty) return;

      try {
        await _repo.markMessagesAsRead(
          _conversationId,
          MarkMessagesReadRequest(messageIds: messageIds),
        );
        ref
            .read(conversationListProvider.notifier)
            .markConversationRead(_conversationId);
        ref
            .read(chatWebSocketServiceProvider(_conversationId))
            .sendMessageRead(messageIds);
      } catch (_) {
        // Keep the chat usable even if read receipts fail.
      }
    });
  }
}

final messagesProvider =
    AsyncNotifierProvider.family<MessagesNotifier, MessagesState, String>(
      MessagesNotifier.new,
    );

// ============================================================
// Typing indicators per conversation
// ============================================================

class TypingUsersNotifier extends FamilyNotifier<Set<String>, String> {
  final Map<String, Timer?> _timers = {};

  @override
  Set<String> build(String arg) => {};

  void setTyping(String userId, bool isTyping) {
    _timers[userId]?.cancel();

    if (isTyping) {
      state = {...state, userId};
      // Auto-clear after 3 seconds
      _timers[userId] = Timer(const Duration(seconds: 3), () {
        state = Set.from(state)..remove(userId);
      });
    } else {
      state = Set.from(state)..remove(userId);
    }
  }
}

final typingUsersProvider =
    NotifierProvider.family<TypingUsersNotifier, Set<String>, String>(
      TypingUsersNotifier.new,
    );

// ============================================================
// WebSocket stream providers (chat performance)
// ============================================================

final chatWebSocketServiceProvider =
    Provider.family<ws.ChatWebSocketService, String>((ref, conversationId) {
      final service = ws.ChatWebSocketManager().getService(conversationId);
      ref.onDispose(() {
        service.disconnect();
      });
      return service;
    });

final chatConnectionStateStreamProvider =
    StreamProvider.family<ws.ConnectionState, String>((ref, conversationId) {
      final service = ref.watch(chatWebSocketServiceProvider(conversationId));
      return service.connectionStream;
    });
