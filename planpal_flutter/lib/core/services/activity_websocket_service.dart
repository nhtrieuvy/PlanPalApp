import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:planpal_flutter/core/services/apis.dart';

enum ActivitySocketConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  failed,
}

enum ActivitySocketEventType {
  activityCreated,
  activityUpdated,
  activityCompleted,
  activityDeleted,
  planUpdated,
  planStatusChanged,
  unknown,
}

class ActivitySocketEvent {
  final ActivitySocketEventType type;
  final String? eventId;
  final String? planId;
  final DateTime? timestamp;
  final Map<String, dynamic> data;

  const ActivitySocketEvent({
    required this.type,
    required this.data,
    this.eventId,
    this.planId,
    this.timestamp,
  });

  factory ActivitySocketEvent.fromJson(Map<String, dynamic> json) {
    final eventType = switch (json['event_type']?.toString()) {
      'activity.created' => ActivitySocketEventType.activityCreated,
      'activity.updated' => ActivitySocketEventType.activityUpdated,
      'activity.completed' => ActivitySocketEventType.activityCompleted,
      'activity.deleted' => ActivitySocketEventType.activityDeleted,
      'plan.updated' => ActivitySocketEventType.planUpdated,
      'plan.status_changed' => ActivitySocketEventType.planStatusChanged,
      _ => ActivitySocketEventType.unknown,
    };

    return ActivitySocketEvent(
      type: eventType,
      eventId: json['event_id']?.toString(),
      planId: json['plan_id']?.toString(),
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? ''),
      data: Map<String, dynamic>.from(
        (json['data'] as Map?) ?? const <String, dynamic>{},
      ),
    );
  }
}

class ActivityWebSocketService {
  ActivityWebSocketService(this.planId);

  final String planId;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  String? _token;

  final StreamController<ActivitySocketEvent> _eventController =
      StreamController<ActivitySocketEvent>.broadcast();
  final StreamController<ActivitySocketConnectionState> _connectionController =
      StreamController<ActivitySocketConnectionState>.broadcast();

  ActivitySocketConnectionState _connectionState =
      ActivitySocketConnectionState.disconnected;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _baseReconnectDelay = Duration(seconds: 2);
  static const Duration _maxReconnectDelay = Duration(seconds: 30);
  final Random _reconnectJitter = Random();

  ActivitySocketConnectionState get connectionState => _connectionState;
  Stream<ActivitySocketEvent> get eventStream => _eventController.stream;
  Stream<ActivitySocketConnectionState> get connectionStream =>
      _connectionController.stream;
  bool get isConnected =>
      _connectionState == ActivitySocketConnectionState.connected;

  Future<void> connect(String token) async {
    if (_connectionState == ActivitySocketConnectionState.connecting ||
        (_connectionState == ActivitySocketConnectionState.connected &&
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
    _setConnectionState(ActivitySocketConnectionState.disconnected);
  }

  Future<void> _connect() async {
    if (_token == null) return;
    try {
      _setConnectionState(
        _reconnectAttempts > 0
            ? ActivitySocketConnectionState.reconnecting
            : ActivitySocketConnectionState.connecting,
      );
      final wsUrl = '$baseWsUrl/ws/plans/$planId/?token=$_token';
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      await _channel!.ready;
      _setConnectionState(ActivitySocketConnectionState.connected);
      _reconnectAttempts = 0;
      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );
    } catch (error) {
      debugPrint('Activity WebSocket connection failed: $error');
      _setConnectionState(ActivitySocketConnectionState.failed);
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic message) {
    try {
      final decoded = jsonDecode(message as String);
      if (decoded is! Map) return;
      _eventController.add(
        ActivitySocketEvent.fromJson(Map<String, dynamic>.from(decoded)),
      );
    } catch (error) {
      debugPrint('Failed to parse activity WebSocket message: $error');
    }
  }

  void _onError(dynamic error) {
    debugPrint('Activity WebSocket error: $error');
    _setConnectionState(ActivitySocketConnectionState.failed);
    _scheduleReconnect();
  }

  void _onDone() {
    if (_connectionState == ActivitySocketConnectionState.disconnected) {
      return;
    }
    _setConnectionState(ActivitySocketConnectionState.failed);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts || _token == null) {
      return;
    }
    _reconnectAttempts += 1;
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

  void _setConnectionState(ActivitySocketConnectionState next) {
    if (_connectionState == next) return;
    _connectionState = next;
    _connectionController.add(next);
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _channel?.sink.close(status.goingAway);
    _subscription?.cancel();
    _channel = null;
    _subscription = null;
    _token = null;
    if (!_connectionController.isClosed) {
      _setConnectionState(ActivitySocketConnectionState.disconnected);
    }
    _eventController.close();
    _connectionController.close();
  }
}
