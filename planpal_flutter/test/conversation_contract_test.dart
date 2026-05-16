import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planpal_flutter/core/dtos/chat_message.dart';
import 'package:planpal_flutter/core/dtos/conversation.dart';
import 'package:planpal_flutter/core/dtos/user_summary.dart';
import 'package:planpal_flutter/core/services/api_error.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/presentation/widgets/chat/message_bubble.dart';
import 'test_app.dart';

void main() {
  final sender = UserSummary(
    id: 'user-1',
    username: 'alice',
    firstName: 'Alice',
    lastName: 'Nguyen',
    isOnline: true,
    onlineStatus: 'online',
    hasAvatar: false,
    dateJoined: DateTime(2026, 4, 1),
    fullName: 'Alice Nguyen',
    initials: 'AN',
  );

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

    expect(error.toString(), 'Không tìm thấy dữ liệu yêu cầu.');
  });

  test('buildApiException maps duplicate username to friendly message', () {
    final error = buildApiException(
      Response(
        requestOptions: RequestOptions(path: '/api/v1/users/'),
        statusCode: 400,
        data: {
          'error_code': 'username_exists',
          'message': 'Username already exists.',
        },
      ),
    );

    expect(error.errorCode, 'username_exists');
    expect(
      error.toString(),
      'Tên đăng nhập đã tồn tại. Vui lòng chọn tên khác.',
    );
  });

  test(
    'buildApiException maps field validation without leaking raw payload',
    () {
      final error = buildApiException(
        Response(
          requestOptions: RequestOptions(path: '/api/v1/users/'),
          statusCode: 400,
          data: {
            'message': 'Bad Request',
            'details': {
              'fields': {
                'email': ['This field must be unique.'],
              },
            },
          },
        ),
      );

      expect(error.fieldErrors['email'], isNotEmpty);
      expect(
        error.toString(),
        'Email này đã được sử dụng. Vui lòng dùng email khác.',
      );
    },
  );

  test('ErrorDisplayService hides technical Dio errors', () {
    final message = ErrorDisplayService.getUserFriendlyMessage(
      DioException(
        requestOptions: RequestOptions(path: '/api/v1/users/'),
        type: DioExceptionType.connectionError,
        error: 'SocketException: OS Error',
      ),
    );

    expect(message, 'Không thể kết nối đến máy chủ. Vui lòng kiểm tra mạng.');
  });

  testWidgets('MessageBubble renders file metadata clearly', (tester) async {
    final message = ChatMessage(
      id: 'msg-file',
      sender: sender,
      messageType: MessageType.file,
      content: '',
      attachmentName: 'proposal.pdf',
      attachmentSize: 4096,
      isEdited: false,
      isDeleted: false,
      canEdit: false,
      canDelete: true,
      createdAt: DateTime(2026, 4, 1, 10),
      updatedAt: DateTime(2026, 4, 1, 10),
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        Scaffold(body: MessageBubble(message: message, isCurrentUser: false)),
      ),
    );

    expect(find.text('proposal.pdf'), findsOneWidget);
    expect(find.text('4.0 KB'), findsOneWidget);
    expect(find.text('Tap to open file'), findsOneWidget);
  });

  testWidgets('MessageBubble renders location call-to-action clearly', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 'msg-location',
      sender: sender,
      messageType: MessageType.location,
      content: 'Da Nang, Viet Nam',
      locationName: 'Da Nang',
      latitude: 16.0544,
      longitude: 108.2022,
      isEdited: false,
      isDeleted: false,
      canEdit: false,
      canDelete: true,
      createdAt: DateTime(2026, 4, 1, 10),
      updatedAt: DateTime(2026, 4, 1, 10),
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        Scaffold(body: MessageBubble(message: message, isCurrentUser: true)),
      ),
    );

    expect(find.text('Da Nang'), findsOneWidget);
    expect(find.text('Da Nang, Viet Nam'), findsOneWidget);
    expect(find.text('Tap to open map'), findsOneWidget);
  });
}
