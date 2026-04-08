import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:planpal_flutter/core/dtos/notification_model.dart';
import 'package:planpal_flutter/core/services/apis.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:web_socket_channel/web_socket_channel.dart';

enum NotificationSocketEventType {
  created('notification.created'),
  read('notification.read'),
  readAll('notification.read_all'),
  unknown('unknown');

  const NotificationSocketEventType(this.value);
  final String value;

  static NotificationSocketEventType fromString(String value) {
    return NotificationSocketEventType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => NotificationSocketEventType.unknown,
    );
  }
}

class NotificationSocketEvent {
  final NotificationSocketEventType type;
  final NotificationModel? notification;
  final String? notificationId;
  final int? unreadCount;

  const NotificationSocketEvent({
    required this.type,
    this.notification,
    this.notificationId,
    this.unreadCount,
  });

  factory NotificationSocketEvent.fromJson(Map<String, dynamic> json) {
    final rawType = json['type']?.toString() ?? 'unknown';
    final notificationJson = json['notification'];

    return NotificationSocketEvent(
      type: NotificationSocketEventType.fromString(rawType),
      notification: notificationJson is Map<String, dynamic>
          ? NotificationModel.fromJson(notificationJson)
          : (notificationJson is Map
                ? NotificationModel.fromJson(
                    Map<String, dynamic>.from(notificationJson),
                  )
                : null),
      notificationId: json['notification_id']?.toString(),
      unreadCount: json['unread_count'] as int?,
    );
  }
}

enum NotificationConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  failed,
}

class NotificationWebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  NotificationConnectionState _connectionState =
      NotificationConnectionState.disconnected;
  String? _token;
  bool _disposed = false;

  final StreamController<NotificationSocketEvent> _eventController =
      StreamController<NotificationSocketEvent>.broadcast();
  final StreamController<NotificationConnectionState> _connectionController =
      StreamController<NotificationConnectionState>.broadcast();

  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 2);

  NotificationConnectionState get connectionState => _connectionState;
  bool get isConnected =>
      _connectionState == NotificationConnectionState.connected;
  Stream<NotificationSocketEvent> get eventStream => _eventController.stream;
  Stream<NotificationConnectionState> get connectionStream =>
      _connectionController.stream;

  Future<void> connect(String token) async {
    if (_disposed) return;
    if (_connectionState == NotificationConnectionState.connecting ||
        (_connectionState == NotificationConnectionState.connected &&
            _token == token)) {
      return;
    }

    await disconnect();
    _token = token;
    _reconnectAttempts = 0;
    await _connect();
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    await _channel?.sink.close(status.goingAway);
    await _subscription?.cancel();
    _channel = null;
    _subscription = null;
    _token = null;
    _setConnectionState(NotificationConnectionState.disconnected);
  }

  Future<void> _connect() async {
    if (_token == null) return;

    try {
      _setConnectionState(NotificationConnectionState.connecting);
      final wsUrl = '$baseWsUrl/ws/user/?token=$_token';
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      await _channel!.ready;

      _setConnectionState(NotificationConnectionState.connected);
      _reconnectAttempts = 0;

      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );
    } catch (error) {
      debugPrint('Notification WebSocket connection failed: $error');
      _setConnectionState(NotificationConnectionState.failed);
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic message) {
    if (_disposed || _eventController.isClosed) return;
    try {
      final payload = jsonDecode(message as String);
      if (payload is! Map) return;

      final event = NotificationSocketEvent.fromJson(
        Map<String, dynamic>.from(payload),
      );
      if (event.type != NotificationSocketEventType.unknown) {
        _eventController.add(event);
      }
    } catch (error) {
      debugPrint('Failed to parse notification WebSocket payload: $error');
    }
  }

  void _onError(dynamic error) {
    if (_disposed) return;
    debugPrint('Notification WebSocket error: $error');
    _setConnectionState(NotificationConnectionState.failed);
    _scheduleReconnect();
  }

  void _onDone() {
    if (_disposed) return;
    if (_connectionState == NotificationConnectionState.disconnected) {
      return;
    }
    _setConnectionState(NotificationConnectionState.failed);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    if (_reconnectAttempts >= _maxReconnectAttempts || _token == null) {
      return;
    }

    _reconnectAttempts += 1;
    _setConnectionState(NotificationConnectionState.reconnecting);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, _connect);
  }

  void _setConnectionState(NotificationConnectionState state) {
    if (_disposed || _connectionController.isClosed) return;
    if (_connectionState == state) return;
    _connectionState = state;
    _connectionController.add(state);
  }

  void dispose() {
    _disposed = true;
    disconnect();
    _eventController.close();
    _connectionController.close();
  }
}
