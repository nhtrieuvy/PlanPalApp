import 'dart:io';
import 'package:dio/dio.dart';
import '../services/apis.dart';
import '../dtos/conversation.dart';
import '../dtos/chat_message.dart';
import '../providers/auth_provider.dart';

/// Repository for conversation and messaging operations
class ConversationRepository {
  final AuthProvider auth;

  ConversationRepository(this.auth);

  /// Get all conversations for current user
  /// If [query] is provided, backend will perform search server-side and
  /// return matching conversations using query parameters to improve
  /// performance over local filtering.
  Future<ConversationsResponse> getConversations({String? query}) async {
    try {
      final Response res = await auth.requestWithAutoRefresh((c) {
        final params = <String, dynamic>{};
        if (query != null && query.isNotEmpty) params['q'] = query;
        return c.dio.get(Endpoints.conversations, queryParameters: params);
      });

      final data = res.data;
      // Normalize different possible response shapes
      if (data is Map<String, dynamic>) {
        if (data.containsKey('conversations')) {
          return ConversationsResponse.fromJson(
            Map<String, dynamic>.from(data),
          );
        }
        if (data.containsKey('results')) {
          // Some endpoints return 'results' key
          return ConversationsResponse.fromJson({
            'conversations': data['results'],
          });
        }
        // Fallback: wrap whole map as single conversation list if possible
        if (data['conversations'] is List) {
          return ConversationsResponse.fromJson(
            Map<String, dynamic>.from(data),
          );
        }
      } else if (data is List) {
        return ConversationsResponse.fromJson({
          'conversations': List<dynamic>.from(data),
        });
      }

      // If none matched, attempt direct parsing (may throw)
      return ConversationsResponse.fromJson(
        Map<String, dynamic>.from(res.data as Map),
      );
    } on DioException catch (e) {
      throw _handleDioException(e);
    }
  }

  /// Get conversation details by ID
  Future<Conversation> getConversation(String conversationId) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.get(Endpoints.conversationDetails(conversationId)),
      );
      return Conversation.fromJson(Map<String, dynamic>.from(res.data as Map));
    } on DioException catch (e) {
      throw _handleDioException(e);
    }
  }

  /// Create or get direct conversation with another user
  Future<CreateDirectConversationResponse> createDirectConversation(
    String userId,
  ) async {
    try {
      final request = CreateDirectConversationRequest(userId: userId);
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.post(
          Endpoints.createDirectConversation,
          data: request.toJson(),
        ),
      );
      return CreateDirectConversationResponse.fromJson(
        Map<String, dynamic>.from(res.data as Map),
      );
    } on DioException catch (e) {
      throw _handleDioException(e);
    }
  }

  /// Get messages for a conversation with pagination
  Future<MessagesResponse> getConversationMessages(
    String conversationId, {
    int limit = 50,
    String? beforeId,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'limit': limit,
        if (beforeId != null) 'before_id': beforeId,
      };

      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.get(
          Endpoints.conversationMessages(conversationId),
          queryParameters: queryParams,
        ),
      );
      return MessagesResponse.fromJson(
        Map<String, dynamic>.from(res.data as Map),
      );
    } on DioException catch (e) {
      throw _handleDioException(e);
    }
  }

  /// Send message to conversation
  Future<ChatMessage> sendMessage(
    String conversationId,
    SendMessageRequest request,
  ) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.post(
          Endpoints.sendMessage(conversationId),
          data: request.toJson(),
        ),
      );
      return ChatMessage.fromJson(Map<String, dynamic>.from(res.data as Map));
    } on DioException catch (e) {
      throw _handleDioException(e);
    }
  }

  /// Mark messages as read
  Future<void> markMessagesAsRead(
    String conversationId,
    MarkMessagesReadRequest request,
  ) async {
    try {
      await auth.requestWithAutoRefresh(
        (c) => c.dio.post(
          Endpoints.markRead(conversationId),
          data: request.toJson(),
        ),
      );
    } on DioException catch (e) {
      throw _handleDioException(e);
    }
  }

  /// Send text message (convenience method)
  Future<ChatMessage> sendTextMessage(
    String conversationId,
    String content, {
    String? replyToId,
  }) async {
    final request = SendMessageRequest(
      content: content,
      messageType: MessageType.text,
      replyToId: replyToId,
    );
    return sendMessage(conversationId, request);
  }

  /// Send image file with multipart upload (like user/group avatar)
  Future<ChatMessage> sendImageFile(
    String conversationId,
    File imageFile, {
    String? replyToId,
  }) async {
    try {
      final formData = FormData.fromMap({
        'message_type': MessageType.image.name,
        'attachment': await MultipartFile.fromFile(
          imageFile.path,
          filename: imageFile.path.split(Platform.pathSeparator).last,
        ),
        if (replyToId != null) 'reply_to_id': replyToId,
      });

      final Response res = await auth.requestWithAutoRefresh(
        (c) =>
            c.dio.post(Endpoints.sendMessage(conversationId), data: formData),
      );
      return ChatMessage.fromJson(Map<String, dynamic>.from(res.data as Map));
    } on DioException catch (e) {
      throw _handleDioException(e);
    }
  }

  /// Send file with multipart upload (like user/group avatar)
  Future<ChatMessage> sendFileAttachment(
    String conversationId,
    File file, {
    String? replyToId,
  }) async {
    try {
      final formData = FormData.fromMap({
        'message_type': MessageType.file.name,
        'attachment': await MultipartFile.fromFile(
          file.path,
          filename: file.path.split(Platform.pathSeparator).last,
        ),
        if (replyToId != null) 'reply_to_id': replyToId,
      });

      final Response res = await auth.requestWithAutoRefresh(
        (c) =>
            c.dio.post(Endpoints.sendMessage(conversationId), data: formData),
      );
      return ChatMessage.fromJson(Map<String, dynamic>.from(res.data as Map));
    } on DioException catch (e) {
      throw _handleDioException(e);
    }
  }

  /// Send image message (convenience method)
  Future<ChatMessage> sendImageMessage(
    String conversationId,
    String imageUrl,
    String fileName, {
    int? fileSize,
    String? replyToId,
  }) async {
    final request = SendMessageRequest(
      content: fileName, // Keep filename as content for backward compatibility
      messageType: MessageType.image,
      attachment: imageUrl, // Store image URL in attachment field
      attachmentName: fileName,
      attachmentSize: fileSize,
      replyToId: replyToId,
    );
    return sendMessage(conversationId, request);
  }

  /// Send file message (convenience method)
  Future<ChatMessage> sendFileMessage(
    String conversationId,
    String fileUrl,
    String fileName, {
    int? fileSize,
    String? replyToId,
  }) async {
    final request = SendMessageRequest(
      content: fileName, // Keep filename as content for backward compatibility
      messageType: MessageType.file,
      attachment: fileUrl, // Store file URL in attachment field
      attachmentName: fileName,
      attachmentSize: fileSize,
      replyToId: replyToId,
    );
    return sendMessage(conversationId, request);
  }

  /// Send location message (convenience method)
  Future<ChatMessage> sendLocationMessage(
    String conversationId,
    double latitude,
    double longitude,
    String locationName, {
    String? replyToId,
  }) async {
    final request = SendMessageRequest(
      content: locationName,
      messageType: MessageType.location,
      latitude: latitude,
      longitude: longitude,
      locationName: locationName,
      replyToId: replyToId,
    );
    return sendMessage(conversationId, request);
  }

  /// Handle Dio exceptions and convert to appropriate errors
  Exception _handleDioException(DioException e) {
    if (e.response != null) {
      final statusCode = e.response!.statusCode;
      final data = e.response!.data;

      String errorMessage = 'Unknown error occurred';
      if (data is Map<String, dynamic> && data.containsKey('error')) {
        errorMessage = data['error'] as String;
      } else if (data is Map<String, dynamic> && data.containsKey('detail')) {
        errorMessage = data['detail'] as String;
      }

      switch (statusCode) {
        case 400:
          return BadRequestException(errorMessage);
        case 401:
          return UnauthorizedException(errorMessage);
        case 403:
          return ForbiddenException(errorMessage);
        case 404:
          return NotFoundException(errorMessage);
        case 500:
          return ServerException(errorMessage);
        default:
          return ApiException(errorMessage, statusCode);
      }
    } else {
      // Network error
      return NetworkException('Network error: ${e.message}');
    }
  }
}

/// Custom exceptions for conversation operations
class ConversationException implements Exception {
  final String message;
  const ConversationException(this.message);

  @override
  String toString() => 'ConversationException: $message';
}

class BadRequestException extends ConversationException {
  const BadRequestException(super.message);
}

class UnauthorizedException extends ConversationException {
  const UnauthorizedException(super.message);
}

class ForbiddenException extends ConversationException {
  const ForbiddenException(super.message);
}

class NotFoundException extends ConversationException {
  const NotFoundException(super.message);
}

class ServerException extends ConversationException {
  const ServerException(super.message);
}

class NetworkException extends ConversationException {
  const NetworkException(super.message);
}

class ApiException extends ConversationException {
  final int? statusCode;
  const ApiException(super.message, this.statusCode);

  @override
  String toString() => 'ApiException($statusCode): $message';
}
