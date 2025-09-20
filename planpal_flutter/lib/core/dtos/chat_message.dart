import 'package:equatable/equatable.dart';
import 'user_summary.dart';

/// Message type enum matching backend
enum MessageType {
  text('text'),
  image('image'),
  location('location'),
  file('file'),
  system('system');

  const MessageType(this.value);
  final String value;

  static MessageType fromString(String value) {
    return MessageType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => MessageType.text,
    );
  }
}

/// Reply target information for threaded messages
class ReplyTo extends Equatable {
  final String id;
  final String content;
  final String sender;
  final MessageType messageType;

  const ReplyTo({
    required this.id,
    required this.content,
    required this.sender,
    required this.messageType,
  });

  factory ReplyTo.fromJson(Map<String, dynamic> json) {
    return ReplyTo(
      id: json['id'] as String,
      content: json['content'] as String,
      sender: json['sender'] as String,
      messageType: MessageType.fromString(json['message_type'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'sender': sender,
      'message_type': messageType.value,
    };
  }

  @override
  List<Object?> get props => [id, content, sender, messageType];
}

/// Chat message model matching backend ChatMessageSerializer
class ChatMessage extends Equatable {
  final String id;
  final String? conversationId;
  final UserSummary sender;
  final MessageType messageType;
  final String content;
  final String? attachment;
  final String? attachmentUrl;
  final String? attachmentName;
  final int? attachmentSize;
  final String? attachmentSizeDisplay;
  final double? latitude;
  final double? longitude;
  final String? locationName;
  final String? locationUrl;
  final ReplyTo? replyTo;
  final bool isEdited;
  final bool isDeleted;
  final bool canEdit;
  final bool canDelete;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ChatMessage({
    required this.id,
    this.conversationId,
    required this.sender,
    required this.messageType,
    required this.content,
    this.attachment,
    this.attachmentUrl,
    this.attachmentName,
    this.attachmentSize,
    this.attachmentSizeDisplay,
    this.latitude,
    this.longitude,
    this.locationName,
    this.locationUrl,
    this.replyTo,
    required this.isEdited,
    required this.isDeleted,
    required this.canEdit,
    required this.canDelete,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      conversationId: json['conversation'] as String?,
      sender: UserSummary.fromJson(json['sender'] as Map<String, dynamic>),
      messageType: MessageType.fromString(json['message_type'] as String),
      content: json['content']?.toString() ?? '',
      attachment: json['attachment'] as String?,
      attachmentUrl: json['attachment_url'] as String?,
      attachmentName: json['attachment_name']?.toString() ?? '',
      attachmentSize: json['attachment_size'] as int?,
      attachmentSizeDisplay: json['attachment_size_display'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      locationName: json['location_name']?.toString() ?? '',
      locationUrl: json['location_url'] as String?,
      replyTo: json['reply_to'] != null
          ? ReplyTo.fromJson(json['reply_to'] as Map<String, dynamic>)
          : null,
      isEdited: json['is_edited'] as bool,
      isDeleted: json['is_deleted'] as bool,
      canEdit: json['can_edit'] as bool,
      canDelete: json['can_delete'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversation': conversationId,
      'sender': sender.toJson(),
      'message_type': messageType.value,
      'content': content,
      'attachment': attachment,
      'attachment_url': attachmentUrl,
      'attachment_name': attachmentName,
      'attachment_size': attachmentSize,
      'attachment_size_display': attachmentSizeDisplay,
      'latitude': latitude,
      'longitude': longitude,
      'location_name': locationName,
      'location_url': locationUrl,
      'reply_to': replyTo?.toJson(),
      'is_edited': isEdited,
      'is_deleted': isDeleted,
      'can_edit': canEdit,
      'can_delete': canDelete,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Check if message is a location message
  bool get isLocationMessage => messageType == MessageType.location;

  /// Check if message is an image message
  bool get isImageMessage => messageType == MessageType.image;

  /// Check if message is a file message
  bool get isFileMessage => messageType == MessageType.file;

  /// Check if message is a system message
  bool get isSystemMessage => messageType == MessageType.system;

  /// Check if message has attachment
  bool get hasAttachment => attachmentUrl != null && attachmentUrl!.isNotEmpty;

  /// Check if message has location data
  bool get hasLocation => latitude != null && longitude != null;

  /// Get display text for message based on type
  String get displayText {
    switch (messageType) {
      case MessageType.text:
        return content;
      case MessageType.image:
        return '📷 Image';
      case MessageType.location:
        return '📍 ${locationName ?? 'Location'}';
      case MessageType.file:
        return '📎 ${attachmentName ?? 'File'}';
      case MessageType.system:
        return content;
    }
  }

  /// Create copy with updated fields
  ChatMessage copyWith({
    String? id,
    String? conversationId,
    UserSummary? sender,
    MessageType? messageType,
    String? content,
    String? attachment,
    String? attachmentUrl,
    String? attachmentName,
    int? attachmentSize,
    String? attachmentSizeDisplay,
    double? latitude,
    double? longitude,
    String? locationName,
    String? locationUrl,
    ReplyTo? replyTo,
    bool? isEdited,
    bool? isDeleted,
    bool? canEdit,
    bool? canDelete,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      sender: sender ?? this.sender,
      messageType: messageType ?? this.messageType,
      content: content ?? this.content,
      attachment: attachment ?? this.attachment,
      attachmentUrl: attachmentUrl ?? this.attachmentUrl,
      attachmentName: attachmentName ?? this.attachmentName,
      attachmentSize: attachmentSize ?? this.attachmentSize,
      attachmentSizeDisplay:
          attachmentSizeDisplay ?? this.attachmentSizeDisplay,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationName: locationName ?? this.locationName,
      locationUrl: locationUrl ?? this.locationUrl,
      replyTo: replyTo ?? this.replyTo,
      isEdited: isEdited ?? this.isEdited,
      isDeleted: isDeleted ?? this.isDeleted,
      canEdit: canEdit ?? this.canEdit,
      canDelete: canDelete ?? this.canDelete,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    conversationId,
    sender,
    messageType,
    content,
    attachment,
    attachmentUrl,
    attachmentName,
    attachmentSize,
    attachmentSizeDisplay,
    latitude,
    longitude,
    locationName,
    locationUrl,
    replyTo,
    isEdited,
    isDeleted,
    canEdit,
    canDelete,
    createdAt,
    updatedAt,
  ];
}

/// Create message request for sending new messages
class SendMessageRequest {
  final String content;
  final MessageType messageType;
  final double? latitude;
  final double? longitude;
  final String? locationName;
  final String? replyToId;
  final String? attachment;
  final String? attachmentName;
  final int? attachmentSize;

  const SendMessageRequest({
    required this.content,
    this.messageType = MessageType.text,
    this.latitude,
    this.longitude,
    this.locationName,
    this.replyToId,
    this.attachment,
    this.attachmentName,
    this.attachmentSize,
  });

  Map<String, dynamic> toJson() {
    return {
      'content': content,
      'message_type': messageType.value,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (locationName != null) 'location_name': locationName,
      if (replyToId != null) 'reply_to_id': replyToId,
      if (attachment != null) 'attachment': attachment,
      if (attachmentName != null) 'attachment_name': attachmentName,
      if (attachmentSize != null) 'attachment_size': attachmentSize,
    };
  }
}

/// Paginated messages response
class MessagesResponse extends Equatable {
  final List<ChatMessage> messages;
  final bool hasMore;
  final String? nextCursor;
  final int count;

  const MessagesResponse({
    required this.messages,
    required this.hasMore,
    this.nextCursor,
    required this.count,
  });

  factory MessagesResponse.fromJson(Map<String, dynamic> json) {
    return MessagesResponse(
      messages: (json['messages'] as List<dynamic>)
          .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
          .toList(),
      hasMore: json['has_more'] as bool,
      nextCursor: json['next_cursor'] as String?,
      count: json['count'] as int,
    );
  }

  @override
  List<Object?> get props => [messages, hasMore, nextCursor, count];
}
