import 'package:equatable/equatable.dart';
import 'package:planpal_flutter/core/utils/server_datetime.dart';

class NotificationTypeOption extends Equatable {
  final String value;
  final String label;

  const NotificationTypeOption({required this.value, required this.label});

  @override
  List<Object?> get props => [value, label];
}

class NotificationModel extends Equatable {
  final String id;
  final String type;
  final String title;
  final String message;
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime? readAt;
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.data,
    required this.isRead,
    required this.readAt,
    required this.createdAt,
  });

  static const List<NotificationTypeOption> typeOptions = [
    NotificationTypeOption(value: 'PLAN_REMINDER', label: 'Plan reminder'),
    NotificationTypeOption(value: 'GROUP_JOIN', label: 'Group activity'),
    NotificationTypeOption(value: 'GROUP_INVITE', label: 'Group invite'),
    NotificationTypeOption(value: 'ROLE_CHANGED', label: 'Role changed'),
    NotificationTypeOption(value: 'PLAN_UPDATED', label: 'Plan updated'),
    NotificationTypeOption(value: 'NEW_MESSAGE', label: 'New message'),
    NotificationTypeOption(value: 'BUDGET_ALERT', label: 'Budget alert'),
    NotificationTypeOption(value: 'LARGE_EXPENSE', label: 'Large expense'),
  ];

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      data: json['data'] is Map
          ? Map<String, dynamic>.from(json['data'] as Map)
          : const <String, dynamic>{},
      isRead: json['is_read'] == true,
      readAt: parseServerDateTime(json['read_at']),
      createdAt: parseServerDateTime(json['created_at']) ?? DateTime.now(),
    );
  }

  bool get isUnread => !isRead;

  String get typeLabel {
    for (final option in typeOptions) {
      if (option.value == type) return option.label;
    }
    return type.replaceAll('_', ' ');
  }

  NotificationModel copyWith({
    String? id,
    String? type,
    String? title,
    String? message,
    Map<String, dynamic>? data,
    bool? isRead,
    DateTime? readAt,
    DateTime? createdAt,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      message: message ?? this.message,
      data: data ?? this.data,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    type,
    title,
    message,
    data,
    isRead,
    readAt,
    createdAt,
  ];
}

class NotificationFilter extends Equatable {
  final bool? isRead;
  final int pageSize;

  const NotificationFilter({this.isRead, this.pageSize = 20});

  Map<String, dynamic> toQueryParameters() {
    return {if (isRead != null) 'is_read': isRead, 'page_size': pageSize};
  }

  @override
  List<Object?> get props => [isRead, pageSize];
}

class NotificationsResponse extends Equatable {
  final List<NotificationModel> notifications;
  final String? nextPageUrl;
  final bool hasMore;
  final int pageSize;
  final int unreadCount;

  const NotificationsResponse({
    required this.notifications,
    required this.nextPageUrl,
    required this.hasMore,
    required this.pageSize,
    required this.unreadCount,
  });

  factory NotificationsResponse.fromJson(Map<String, dynamic> json) {
    final rawResults = json['results'] as List<dynamic>? ?? const <dynamic>[];
    return NotificationsResponse(
      notifications: rawResults
          .whereType<Map>()
          .map(
            (item) =>
                NotificationModel.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      nextPageUrl: json['next']?.toString(),
      hasMore: json['has_more'] == true,
      pageSize: json['page_size'] as int? ?? 20,
      unreadCount: json['unread_count'] as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [
    notifications,
    nextPageUrl,
    hasMore,
    pageSize,
    unreadCount,
  ];
}

class NotificationPreferenceModel extends Equatable {
  const NotificationPreferenceModel({
    required this.pushEnabled,
    required this.quietHoursEnabled,
    required this.timezone,
    required this.dailyDigestEnabled,
    required this.dailyDigestHour,
    this.quietHoursStart,
    this.quietHoursEnd,
  });

  final bool pushEnabled;
  final bool quietHoursEnabled;
  final String? quietHoursStart;
  final String? quietHoursEnd;
  final String timezone;
  final bool dailyDigestEnabled;
  final int dailyDigestHour;

  factory NotificationPreferenceModel.fromJson(Map<String, dynamic> json) =>
      NotificationPreferenceModel(
        pushEnabled: json['push_enabled'] != false,
        quietHoursEnabled: json['quiet_hours_enabled'] == true,
        quietHoursStart: json['quiet_hours_start']?.toString(),
        quietHoursEnd: json['quiet_hours_end']?.toString(),
        timezone: json['timezone']?.toString() ?? 'Asia/Ho_Chi_Minh',
        dailyDigestEnabled: json['daily_digest_enabled'] == true,
        dailyDigestHour:
            int.tryParse(json['daily_digest_hour']?.toString() ?? '') ?? 8,
      );

  Map<String, dynamic> toJson() => {
    'push_enabled': pushEnabled,
    'quiet_hours_enabled': quietHoursEnabled,
    'quiet_hours_start': quietHoursStart,
    'quiet_hours_end': quietHoursEnd,
    'timezone': timezone,
    'daily_digest_enabled': dailyDigestEnabled,
    'daily_digest_hour': dailyDigestHour,
  };

  NotificationPreferenceModel copyWith({
    bool? pushEnabled,
    bool? quietHoursEnabled,
    String? quietHoursStart,
    String? quietHoursEnd,
    String? timezone,
    bool? dailyDigestEnabled,
    int? dailyDigestHour,
  }) => NotificationPreferenceModel(
    pushEnabled: pushEnabled ?? this.pushEnabled,
    quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
    quietHoursStart: quietHoursStart ?? this.quietHoursStart,
    quietHoursEnd: quietHoursEnd ?? this.quietHoursEnd,
    timezone: timezone ?? this.timezone,
    dailyDigestEnabled: dailyDigestEnabled ?? this.dailyDigestEnabled,
    dailyDigestHour: dailyDigestHour ?? this.dailyDigestHour,
  );

  @override
  List<Object?> get props => [
    pushEnabled,
    quietHoursEnabled,
    quietHoursStart,
    quietHoursEnd,
    timezone,
    dailyDigestEnabled,
    dailyDigestHour,
  ];
}
