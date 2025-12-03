import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:flutter/foundation.dart';

/// WebSocket events that can be received
enum WebSocketEventType {
  chatMessage('chat_message'),
  typingStart('typing_start'),
  typingStop('typing_stop'),
  messageRead('message_read'),
  userJoined('user_joined'),
  userLeft('user_left'),
  error('error');

  const WebSocketEventType(this.value);
  final String value;

  static WebSocketEventType fromString(String value) {
    return WebSocketEventType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => WebSocketEventType.error,
    );
  }
}

/// WebSocket event data
class WebSocketEvent {
  final WebSocketEventType type;
  final Map<String, dynamic> data;

  const WebSocketEvent({required this.type, required this.data});

  factory WebSocketEvent.fromJson(Map<String, dynamic> json) {
    return WebSocketEvent(
      type: WebSocketEventType.fromString(json['type'] as String),
      data: json['data'] as Map<String, dynamic>? ?? {},
    );
  }
}

/// Connection state for WebSocket
enum ConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  failed,
}

/// WebSocket service for realtime chat
class ChatWebSocketService {
  // Production WebSocket on Fly.io
  static const String baseWsUrl = 'wss://planpal-backend.fly.dev';
  // Local development: 'ws://10.0.2.2:8000'

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  ConnectionState _connectionState = ConnectionState.disconnected;
  String? _conversationId;
  String? _token;

  // Event streams
  final StreamController<WebSocketEvent> _eventController =
      StreamController<WebSocketEvent>.broadcast();
  final StreamController<ConnectionState> _connectionController =
      StreamController<ConnectionState>.broadcast();

  // Reconnection
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 5;
  static const Duration reconnectDelay = Duration(seconds: 2);

  // Typing indicator
  Timer? _typingTimer;
  bool _isTyping = false;

  // Getters
  ConnectionState get connectionState => _connectionState;
  Stream<WebSocketEvent> get eventStream => _eventController.stream;
  Stream<ConnectionState> get connectionStream => _connectionController.stream;
  bool get isConnected => _connectionState == ConnectionState.connected;

  /// Connect to a conversation's WebSocket
  Future<void> connect(String conversationId, String token) async {
    if (_connectionState == ConnectionState.connecting ||
        (_connectionState == ConnectionState.connected &&
            _conversationId == conversationId)) {
      return;
    }

    await disconnect();

    _conversationId = conversationId;
    _token = token;
    _reconnectAttempts = 0;

    await _connect();
  }

  /// Disconnect from WebSocket
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _typingTimer?.cancel();

    await _channel?.sink.close(status.goingAway);
    await _subscription?.cancel();

    _channel = null;
    _subscription = null;
    _conversationId = null;
    _token = null;
    _isTyping = false;

    _setConnectionState(ConnectionState.disconnected);
  }

  /// Send typing indicator
  void sendTypingIndicator(bool isTyping) {
    if (!isConnected || _isTyping == isTyping) return;

    _isTyping = isTyping;

    if (isTyping) {
      _sendEvent('typing_start', {});

      // Auto-stop typing after 3 seconds
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 3), () {
        sendTypingIndicator(false);
      });
    } else {
      _sendEvent('typing_stop', {});
      _typingTimer?.cancel();
    }
  }

  /// Send message read receipt
  void sendMessageRead(List<String> messageIds) {
    if (!isConnected || messageIds.isEmpty) return;

    _sendEvent('message_read', {'message_ids': messageIds});
  }

  /// Private methods
  Future<void> _connect() async {
    if (_conversationId == null || _token == null) return;

    try {
      _setConnectionState(ConnectionState.connecting);

      final wsUrl = '$baseWsUrl/ws/chat/$_conversationId/?token=$_token';

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // Wait for connection to be established
      await _channel!.ready;

      _setConnectionState(ConnectionState.connected);
      _reconnectAttempts = 0;

      // Listen to messages
      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      debugPrint('WebSocket connected to conversation: $_conversationId');
    } catch (e) {
      debugPrint('WebSocket connection failed: $e');
      _setConnectionState(ConnectionState.failed);
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic message) {
    try {
      final Map<String, dynamic> data = jsonDecode(message as String);
      final event = WebSocketEvent.fromJson(data);

      debugPrint('WebSocket received: ${event.type.value}');
      _eventController.add(event);
    } catch (e) {
      debugPrint('Failed to parse WebSocket message: $e');
    }
  }

  void _onError(dynamic error) {
    debugPrint('WebSocket error: $error');
    _setConnectionState(ConnectionState.failed);
    _scheduleReconnect();
  }

  void _onDone() {
    debugPrint('WebSocket connection closed');
    if (_connectionState != ConnectionState.disconnected) {
      _setConnectionState(ConnectionState.failed);
      _scheduleReconnect();
    }
  }

  void _sendEvent(String type, Map<String, dynamic> data) {
    if (!isConnected) return;

    try {
      final message = jsonEncode({'type': type, 'data': data});

      _channel?.sink.add(message);
      debugPrint('WebSocket sent: $type');
    } catch (e) {
      debugPrint('Failed to send WebSocket message: $e');
    }
  }

  void _setConnectionState(ConnectionState state) {
    if (_connectionState != state) {
      _connectionState = state;
      _connectionController.add(state);
      debugPrint('WebSocket state changed to: $state');
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= maxReconnectAttempts ||
        _conversationId == null ||
        _token == null) {
      debugPrint('Max reconnect attempts reached or no conversation/token');
      return;
    }

    _reconnectAttempts++;
    _setConnectionState(ConnectionState.reconnecting);

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(reconnectDelay, () {
      debugPrint('Attempting to reconnect... (attempt $_reconnectAttempts)');
      _connect();
    });
  }

  /// Dispose resources
  void dispose() {
    disconnect();
    _eventController.close();
    _connectionController.close();
  }
}

/// Singleton service for managing chat WebSocket connections
class ChatWebSocketManager {
  static final ChatWebSocketManager _instance =
      ChatWebSocketManager._internal();
  factory ChatWebSocketManager() => _instance;
  ChatWebSocketManager._internal();

  final Map<String, ChatWebSocketService> _services = {};

  /// Get or create WebSocket service for a conversation
  ChatWebSocketService getService(String conversationId) {
    if (!_services.containsKey(conversationId)) {
      _services[conversationId] = ChatWebSocketService();
    }
    return _services[conversationId]!;
  }

  /// Connect to a conversation
  Future<void> connect(String conversationId, String token) async {
    final service = getService(conversationId);
    await service.connect(conversationId, token);
  }

  /// Disconnect from a conversation
  Future<void> disconnect(String conversationId) async {
    final service = _services[conversationId];
    if (service != null) {
      await service.disconnect();
      _services.remove(conversationId);
    }
  }

  /// Disconnect from all conversations
  Future<void> disconnectAll() async {
    final futures = _services.values.map((service) => service.disconnect());
    await Future.wait(futures);
    _services.clear();
  }

  /// Get connection state for a conversation
  ConnectionState getConnectionState(String conversationId) {
    return _services[conversationId]?.connectionState ??
        ConnectionState.disconnected;
  }

  /// Check if connected to a conversation
  bool isConnected(String conversationId) {
    return _services[conversationId]?.isConnected ?? false;
  }

  /// Get event stream for a conversation
  Stream<WebSocketEvent>? getEventStream(String conversationId) {
    return _services[conversationId]?.eventStream;
  }

  /// Get connection stream for a conversation
  Stream<ConnectionState>? getConnectionStream(String conversationId) {
    return _services[conversationId]?.connectionStream;
  }

  /// Send typing indicator
  void sendTypingIndicator(String conversationId, bool isTyping) {
    _services[conversationId]?.sendTypingIndicator(isTyping);
  }

  /// Send message read receipt
  void sendMessageRead(String conversationId, List<String> messageIds) {
    _services[conversationId]?.sendMessageRead(messageIds);
  }

  /// Dispose all services
  void dispose() {
    for (final service in _services.values) {
      service.dispose();
    }
    _services.clear();
  }
}
