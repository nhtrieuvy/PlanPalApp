import 'package:flutter_test/flutter_test.dart';
import 'package:planpal_flutter/core/services/chat_websocket_service.dart';

void main() {
  group('WebSocket Service Tests', () {
    late ChatWebSocketService webSocketService;

    setUp(() {
      webSocketService = ChatWebSocketService();
    });

    tearDown(() {
      webSocketService.dispose();
    });

    test('should have correct initial state', () {
      expect(webSocketService.connectionState, ConnectionState.disconnected);
      expect(webSocketService.isConnected, false);
    });

    test('should handle WebSocket events correctly', () {
      // Test event parsing
      const eventJson = {
        'type': 'chat_message',
        'data': {
          'message': 'Hello World',
          'user_id': '123',
          'timestamp': '2025-01-20T00:00:00Z',
        },
      };

      final event = WebSocketEvent.fromJson(eventJson);
      expect(event.type, WebSocketEventType.chatMessage);
      expect(event.data['message'], 'Hello World');
    });

    test('should parse event types correctly', () {
      expect(
        WebSocketEventType.fromString('chat_message'),
        WebSocketEventType.chatMessage,
      );
      expect(
        WebSocketEventType.fromString('typing_start'),
        WebSocketEventType.typingStart,
      );
      expect(
        WebSocketEventType.fromString('invalid_type'),
        WebSocketEventType.error,
      );
    });
  });
}
