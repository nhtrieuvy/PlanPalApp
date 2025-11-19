import 'package:equatable/equatable.dart';
import 'user_summary.dart';
import 'group_summary.dart';
import 'chat_message.dart';

enum ConversationType {
  direct('direct'),
  group('group');

  const ConversationType(this.value);
  final String value;

  static ConversationType fromString(String value) {
    return ConversationType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => ConversationType.direct,
    );
  }
}

class OtherParticipant extends Equatable {
  final String id;
  final String username;
  final String fullName;
  final bool isOnline;
  final DateTime? lastSeen;

  const OtherParticipant({
    required this.id,
    required this.username,
    required this.fullName,
    required this.isOnline,
    this.lastSeen,
  });

  factory OtherParticipant.fromJson(Map<String, dynamic> json) {
    return OtherParticipant(
      id: json['id'] as String,
      username: json['username'] as String,
      fullName: json['full_name'] as String,
      isOnline: json['is_online'] as bool,
      lastSeen: json['last_seen'] != null
          ? DateTime.parse(json['last_seen'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'full_name': fullName,
      'is_online': isOnline,
      'last_seen': lastSeen?.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [id, username, fullName, isOnline, lastSeen];
}

/// Last message preview for conversation list
class LastMessage extends Equatable {
  final String id;
  final String content;
  final MessageType messageType;
  final String sender;
  final DateTime createdAt;

  const LastMessage({
    required this.id,
    required this.content,
    required this.messageType,
    required this.sender,
    required this.createdAt,
  });

  factory LastMessage.fromJson(Map<String, dynamic> json) {
    return LastMessage(
      id: json['id'] as String,
      content: (json['content'] as String?) ?? '',
      messageType: MessageType.fromString(
        (json['message_type'] as String?) ?? 'text',
      ),
      sender: (json['sender'] as String?) ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'message_type': messageType.value,
      'sender': sender,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Get display text for last message based on type
  String get displayText {
    switch (messageType) {
      case MessageType.text:
        return content;
      case MessageType.image:
        return '📷 Image';
      case MessageType.location:
        return '📍 Location';
      case MessageType.file:
        return '📎 File';
      case MessageType.system:
        return content;
    }
  }

  @override
  List<Object?> get props => [id, content, messageType, sender, createdAt];
}

/// Conversation model matching backend ConversationSerializer
class Conversation extends Equatable {
  final String id;
  final ConversationType conversationType;
  final String? name;
  final String? avatar;
  final String avatarUrl;
  final GroupSummary? group;
  final List<UserSummary> participants;
  final DateTime? lastMessageAt;
  final bool isActive;
  final int unreadCount;
  final LastMessage? lastMessage;
  final DateTime createdAt;
  final DateTime updatedAt;
  final OtherParticipant? otherParticipant;

  const Conversation({
    required this.id,
    required this.conversationType,
    this.name,
    this.avatar,
    required this.avatarUrl,
    this.group,
    required this.participants,
    this.lastMessageAt,
    required this.isActive,
    required this.unreadCount,
    this.lastMessage,
    required this.createdAt,
    required this.updatedAt,
    this.otherParticipant,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String,
      conversationType: ConversationType.fromString(
        (json['conversation_type'] as String?) ?? 'direct',
      ),
      name: json['name'] as String?,
      avatar: json['avatar'] as String?,
      avatarUrl: (json['avatar_url'] as String?) ?? '',
      group: json['group'] != null
          ? GroupSummary.fromJson(json['group'] as Map<String, dynamic>)
          : null,
      participants:
          (json['participants'] as List<dynamic>?)
              ?.map(
                (item) => UserSummary.fromJson(item as Map<String, dynamic>),
              )
              .toList() ??
          [],
      lastMessageAt: json['last_message_at'] != null
          ? DateTime.parse(json['last_message_at'] as String)
          : null,
      isActive: (json['is_active'] as bool?) ?? true,
      unreadCount: (json['unread_count'] as int?) ?? 0,
      lastMessage: json['last_message'] != null
          ? LastMessage.fromJson(json['last_message'] as Map<String, dynamic>)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      otherParticipant: json['other_participant'] != null
          ? OtherParticipant.fromJson(
              json['other_participant'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversation_type': conversationType.value,
      'name': name,
      'avatar': avatar,
      'avatar_url': avatarUrl,
      'group': group?.toJson(),
      'participants': participants.map((p) => p.toJson()).toList(),
      'last_message_at': lastMessageAt?.toIso8601String(),
      'is_active': isActive,
      'unread_count': unreadCount,
      'last_message': lastMessage?.toJson(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'other_participant': otherParticipant?.toJson(),
    };
  }

  /// Get conversation display name
  String get displayName {
    if (conversationType == ConversationType.group) {
      return group?.name ?? name ?? 'Group Chat';
    } else {
      return otherParticipant?.fullName ??
          otherParticipant?.username ??
          'Direct Chat';
    }
  }

  /// Check if conversation is a direct chat
  bool get isDirect => conversationType == ConversationType.direct;

  /// Check if conversation is a group chat
  bool get isGroup => conversationType == ConversationType.group;

  /// Check if conversation has unread messages
  bool get hasUnreadMessages => unreadCount > 0;

  /// Get formatted unread count
  String get unreadCountText {
    if (unreadCount == 0) return '';
    if (unreadCount > 99) return '99+';
    return unreadCount.toString();
  }

  /// Get other participant's online status for direct chats
  bool get isOtherUserOnline => otherParticipant?.isOnline ?? false;

  /// Get last message preview text
  String? get lastMessagePreview {
    return lastMessage?.displayText;
  }

  /// Get last message sender name
  String? get lastMessageSender {
    return lastMessage?.sender;
  }

  /// Get formatted last message time
  String? get lastMessageTime {
    if (lastMessageAt == null) return null;

    final now = DateTime.now();
    final diff = now.difference(lastMessageAt!);

    if (diff.inDays > 0) {
      return '${diff.inDays}d';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m';
    } else {
      return 'now';
    }
  }

  /// Create copy with updated fields
  Conversation copyWith({
    String? id,
    ConversationType? conversationType,
    String? name,
    String? avatar,
    String? avatarUrl,
    GroupSummary? group,
    List<UserSummary>? participants,
    DateTime? lastMessageAt,
    bool? isActive,
    int? unreadCount,
    LastMessage? lastMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
    OtherParticipant? otherParticipant,
  }) {
    return Conversation(
      id: id ?? this.id,
      conversationType: conversationType ?? this.conversationType,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      group: group ?? this.group,
      participants: participants ?? this.participants,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      isActive: isActive ?? this.isActive,
      unreadCount: unreadCount ?? this.unreadCount,
      lastMessage: lastMessage ?? this.lastMessage,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      otherParticipant: otherParticipant ?? this.otherParticipant,
    );
  }

  @override
  List<Object?> get props => [
    id,
    conversationType,
    name,
    avatar,
    avatarUrl,
    group,
    participants,
    lastMessageAt,
    isActive,
    unreadCount,
    lastMessage,
    createdAt,
    updatedAt,
    otherParticipant,
  ];
}

/// Create direct conversation request
class CreateDirectConversationRequest {
  final String userId;

  const CreateDirectConversationRequest({required this.userId});

  Map<String, dynamic> toJson() {
    return {'user_id': userId};
  }
}

/// Create direct conversation response
class CreateDirectConversationResponse extends Equatable {
  final Conversation conversation;
  final bool created;

  const CreateDirectConversationResponse({
    required this.conversation,
    required this.created,
  });

  factory CreateDirectConversationResponse.fromJson(Map<String, dynamic> json) {
    return CreateDirectConversationResponse(
      conversation: Conversation.fromJson(
        json['conversation'] as Map<String, dynamic>,
      ),
      created: json['created'] as bool,
    );
  }

  @override
  List<Object?> get props => [conversation, created];
}

/// Conversations list response
class ConversationsResponse extends Equatable {
  final List<Conversation> conversations;

  const ConversationsResponse({required this.conversations});

  factory ConversationsResponse.fromJson(Map<String, dynamic> json) {
    return ConversationsResponse(
      conversations: (json['conversations'] as List<dynamic>)
          .map((item) => Conversation.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  List<Object?> get props => [conversations];
}

/// Mark messages as read request
class MarkMessagesReadRequest {
  final List<String> messageIds;

  const MarkMessagesReadRequest({required this.messageIds});

  Map<String, dynamic> toJson() {
    return {'message_ids': messageIds};
  }
}
