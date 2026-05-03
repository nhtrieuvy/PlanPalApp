import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:planpal_flutter/core/dtos/notification_model.dart';
import 'package:planpal_flutter/core/services/apis.dart';
import 'package:planpal_flutter/core/utils/server_datetime.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:web_socket_channel/web_socket_channel.dart';

enum NotificationSocketEventType {
  created('notification.created'),
  read('notification.read'),
  readAll('notification.read_all'),
  userOnline('user.online'),
  userOffline('user.offline'),
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
  final String? userId;
  final String? username;
  final bool? isOnline;
  final DateTime? lastSeen;

  const NotificationSocketEvent({
    required this.type,
    this.notification,
    this.notificationId,
    this.unreadCount,
    this.userId,
    this.username,
    this.isOnline,
    this.lastSeen,
  });

  factory NotificationSocketEvent.fromJson(Map<String, dynamic> json) {
    final rawType =
        json['type']?.toString() ?? json['event_type']?.toString() ?? 'unknown';
    final rawData = json['data'];
    final data = rawData is Map<String, dynamic>
        ? rawData
        : (rawData is Map ? Map<String, dynamic>.from(rawData) : json);
    final notificationJson = json['notification'] ?? data['notification'];
    final type = NotificationSocketEventType.fromString(rawType);

    return NotificationSocketEvent(
      type: type,
      notification: notificationJson is Map<String, dynamic>
          ? NotificationModel.fromJson(notificationJson)
          : (notificationJson is Map
                ? NotificationModel.fromJson(
                    Map<String, dynamic>.from(notificationJson),
                  )
                : null),
      notificationId: (json['notification_id'] ?? data['notification_id'])
          ?.toString(),
      unreadCount: (json['unread_count'] ?? data['unread_count']) as int?,
      userId: (data['user_id'] ?? json['user_id'])?.toString(),
      username: data['username']?.toString(),
      isOnline: data['is_online'] is bool
          ? data['is_online'] as bool
          : (type == NotificationSocketEventType.userOnline
                ? true
                : type == NotificationSocketEventType.userOffline
                ? false
                : null),
      lastSeen: parseServerDateTime(data['last_seen'] ?? json['last_seen']),
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
  static const Duration _baseReconnectDelay = Duration(seconds: 2);
  static const Duration _maxReconnectDelay = Duration(seconds: 30);
  final Random _reconnectJitter = Random();

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
    final delay = _nextReconnectDelay();
    _reconnectTimer = Timer(delay, _connect);
  }

  Duration _nextReconnectDelay() {
    final exponent = (_reconnectAttempts - 1).clamp(0, 4).toInt();
    final baseMs = _baseReconnectDelay.inMilliseconds * (1 << exponent);
    final cappedMs = min(baseMs, _maxReconnectDelay.inMilliseconds);
    return Duration(milliseconds: cappedMs + _reconnectJitter.nextInt(500));
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
