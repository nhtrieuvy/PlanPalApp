import 'package:equatable/equatable.dart';
import 'package:planpal_flutter/core/dtos/user_summary.dart';
import 'package:planpal_flutter/core/utils/server_datetime.dart';

class AuditActionOption extends Equatable {
  final String value;
  final String label;

  const AuditActionOption({required this.value, required this.label});

  @override
  List<Object?> get props => [value, label];
}

class AuditLogModel extends Equatable {
  final String id;
  final String? userId;
  final UserSummary? user;
  final String action;
  final String resourceType;
  final String? resourceId;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  const AuditLogModel({
    required this.id,
    required this.userId,
    required this.user,
    required this.action,
    required this.resourceType,
    required this.resourceId,
    required this.metadata,
    required this.createdAt,
  });

  static const List<AuditActionOption> actionOptions = [
    AuditActionOption(value: 'CREATE_PLAN', label: 'Create Plan'),
    AuditActionOption(value: 'UPDATE_PLAN', label: 'Update Plan'),
    AuditActionOption(value: 'DELETE_PLAN', label: 'Delete Plan'),
    AuditActionOption(value: 'COMPLETE_PLAN', label: 'Complete Plan'),
    AuditActionOption(value: 'JOIN_GROUP', label: 'Join Group'),
    AuditActionOption(value: 'LEAVE_GROUP', label: 'Leave Group'),
    AuditActionOption(value: 'CHANGE_ROLE', label: 'Change Role'),
    AuditActionOption(value: 'DELETE_GROUP', label: 'Delete Group'),
    AuditActionOption(
      value: 'NOTIFICATION_OPENED',
      label: 'Notification Opened',
    ),
  ];

  factory AuditLogModel.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'];
    return AuditLogModel(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString(),
      user: userJson is Map<String, dynamic>
          ? UserSummary.fromJson(userJson)
          : (userJson is Map
                ? UserSummary.fromJson(Map<String, dynamic>.from(userJson))
                : null),
      action: json['action']?.toString() ?? '',
      resourceType: json['resource_type']?.toString() ?? '',
      resourceId: json['resource_id']?.toString(),
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : const <String, dynamic>{},
      createdAt: parseServerDateTime(json['created_at']) ?? DateTime.now(),
    );
  }

  String get actorDisplayName {
    if (user == null) return 'Unknown user';
    if (user!.fullName.isNotEmpty) return user!.fullName;
    if (user!.username.isNotEmpty) return user!.username;
    return 'Unknown user';
  }

  String get actionLabel {
    for (final option in actionOptions) {
      if (option.value == action) return option.label;
    }
    return action.replaceAll('_', ' ');
  }

  String get metadataSummary {
    final title = _metadataString('title');
    final groupName = _metadataString('group_name');
    final newRole = _metadataString('new_role');
    final updatedFields = metadata['updated_fields'];

    switch (action) {
      case 'CREATE_PLAN':
        return title.isNotEmpty ? 'Created "$title"' : 'Created a plan';
      case 'UPDATE_PLAN':
        if (updatedFields is List && updatedFields.isNotEmpty) {
          return 'Updated ${updatedFields.join(', ')}';
        }
        return title.isNotEmpty ? 'Updated "$title"' : 'Updated a plan';
      case 'DELETE_PLAN':
        return title.isNotEmpty ? 'Deleted "$title"' : 'Deleted a plan';
      case 'COMPLETE_PLAN':
        return title.isNotEmpty ? 'Completed "$title"' : 'Completed a plan';
      case 'JOIN_GROUP':
        return groupName.isNotEmpty ? 'Joined "$groupName"' : 'Joined a group';
      case 'LEAVE_GROUP':
        return groupName.isNotEmpty ? 'Left "$groupName"' : 'Left a group';
      case 'CHANGE_ROLE':
        return newRole.isNotEmpty
            ? 'Changed role to ${newRole.toUpperCase()}'
            : 'Changed a member role';
      case 'DELETE_GROUP':
        return groupName.isNotEmpty
            ? 'Deleted "$groupName"'
            : 'Deleted a group';
      case 'NOTIFICATION_OPENED':
        return 'Opened ${metadata['notification_count'] ?? 1} notification(s)';
      default:
        return _fallbackSummary();
    }
  }

  String _metadataString(String key) => metadata[key]?.toString() ?? '';

  String _fallbackSummary() {
    if (metadata.isEmpty) return actionLabel;
    final preview = metadata.entries
        .take(2)
        .map((entry) {
          return '${entry.key}: ${entry.value}';
        })
        .join(' | ');
    return preview.isNotEmpty ? preview : actionLabel;
  }

  @override
  List<Object?> get props => [
    id,
    userId,
    user,
    action,
    resourceType,
    resourceId,
    metadata,
    createdAt,
  ];
}

class AuditLogFilter extends Equatable {
  final String? action;
  final String? userId;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final int pageSize;

  const AuditLogFilter({
    this.action,
    this.userId,
    this.dateFrom,
    this.dateTo,
    this.pageSize = 20,
  });

  Map<String, dynamic> toQueryParameters() {
    return {
      if (action != null && action!.isNotEmpty) 'action': action,
      if (userId != null && userId!.isNotEmpty) 'user_id': userId,
      if (dateFrom != null) 'date_from': dateFrom!.toUtc().toIso8601String(),
      if (dateTo != null) 'date_to': dateTo!.toUtc().toIso8601String(),
      'page_size': pageSize,
    };
  }

  @override
  List<Object?> get props => [action, userId, dateFrom, dateTo, pageSize];
}

class AuditLogQuery extends Equatable {
  final String resourceType;
  final String resourceId;
  final AuditLogFilter filters;

  const AuditLogQuery({
    required this.resourceType,
    required this.resourceId,
    this.filters = const AuditLogFilter(),
  });

  @override
  List<Object?> get props => [resourceType, resourceId, filters];
}

class AuditLogsResponse extends Equatable {
  final List<AuditLogModel> logs;
  final String? nextPageUrl;
  final bool hasMore;
  final int pageSize;

  const AuditLogsResponse({
    required this.logs,
    required this.nextPageUrl,
    required this.hasMore,
    required this.pageSize,
  });

  factory AuditLogsResponse.fromJson(Map<String, dynamic> json) {
    final rawResults = json['results'] as List<dynamic>? ?? const <dynamic>[];
    return AuditLogsResponse(
      logs: rawResults
          .whereType<Map>()
          .map(
            (item) => AuditLogModel.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      nextPageUrl: json['next']?.toString(),
      hasMore: json['has_more'] == true,
      pageSize: json['page_size'] as int? ?? 20,
    );
  }

  @override
  List<Object?> get props => [logs, nextPageUrl, hasMore, pageSize];
}
