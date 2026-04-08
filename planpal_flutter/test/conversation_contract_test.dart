import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planpal_flutter/core/dtos/conversation.dart';
import 'package:planpal_flutter/core/services/api_error.dart';

void main() {
  test('LastMessage.fromJson tolerates nullable ids', () {
    final message = LastMessage.fromJson({
      'id': null,
      'content': 'Hello',
      'message_type': 'text',
      'sender': 'alice',
      'created_at': '2026-04-01T10:00:00Z',
    });

    expect(message.id, isNull);
    expect(message.content, 'Hello');
    expect(message.sender, 'alice');
  });

  test('ConversationsResponse parses backend conversations contract', () {
    final response = ConversationsResponse.fromJson({
      'conversations': [
        {
          'id': 'conv-1',
          'conversation_type': 'direct',
          'avatar_url': '',
          'participants': const [],
          'unread_count': 0,
          'is_active': true,
          'last_message': {
            'id': 'msg-1',
            'content': 'Hi',
            'message_type': 'text',
            'sender': 'bob',
            'created_at': '2026-04-01T10:00:00Z',
          },
          'last_message_at': '2026-04-01T10:00:00Z',
          'created_at': '2026-04-01T10:00:00Z',
          'updated_at': '2026-04-01T10:00:00Z',
        },
      ],
    });

    expect(response.conversations, hasLength(1));
    expect(response.conversations.first.lastMessage?.id, 'msg-1');
  });

  test('buildApiException hides raw html bodies', () {
    final error = buildApiException(
      Response(
        requestOptions: RequestOptions(path: '/api/v1/plans/'),
        statusCode: 404,
        data: '<!DOCTYPE html><html><body>Page not found</body></html>',
      ),
    );

    expect(error.toString(), 'Khong tim thay du lieu yeu cau.');
  });
}
