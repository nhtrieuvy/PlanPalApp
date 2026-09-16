DateTime? _date(dynamic value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

class CollaborationUser {
  final String id;
  final String username;
  final String fullName;
  final String avatarUrl;

  const CollaborationUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.avatarUrl,
  });

  factory CollaborationUser.fromJson(Map<String, dynamic>? json) {
    final data = json ?? const <String, dynamic>{};
    return CollaborationUser(
      id: data['id']?.toString() ?? '',
      username: data['username']?.toString() ?? '',
      fullName:
          data['full_name']?.toString() ?? data['username']?.toString() ?? '',
      avatarUrl: data['avatar_url']?.toString() ?? '',
    );
  }
}

class AvailabilityOptionModel {
  final String id;
  final String label;
  final DateTime startAt;
  final DateTime endAt;
  final Map<String, int> voteCounts;
  final String? currentUserVote;

  const AvailabilityOptionModel({
    required this.id,
    required this.label,
    required this.startAt,
    required this.endAt,
    required this.voteCounts,
    this.currentUserVote,
  });

  factory AvailabilityOptionModel.fromJson(Map<String, dynamic> json) =>
      AvailabilityOptionModel(
        id: json['id'].toString(),
        label: json['label']?.toString() ?? '',
        startAt: _date(json['start_at'])!,
        endAt: _date(json['end_at'])!,
        voteCounts: Map<String, int>.from(
          (json['vote_counts'] as Map? ?? {}).map(
            (key, value) =>
                MapEntry(key.toString(), (value as num?)?.toInt() ?? 0),
          ),
        ),
        currentUserVote: json['current_user_vote']?.toString(),
      );
}

class AvailabilityPollModel {
  final String id;
  final String title;
  final CollaborationUser createdBy;
  final DateTime? closesAt;
  final bool isClosed;
  final int totalVoters;
  final List<AvailabilityOptionModel> options;

  const AvailabilityPollModel({
    required this.id,
    required this.title,
    required this.createdBy,
    this.closesAt,
    required this.isClosed,
    required this.totalVoters,
    required this.options,
  });

  factory AvailabilityPollModel.fromJson(
    Map<String, dynamic> json,
  ) => AvailabilityPollModel(
    id: json['id'].toString(),
    title: json['title']?.toString() ?? '',
    createdBy: CollaborationUser.fromJson(
      json['created_by'] is Map
          ? Map<String, dynamic>.from(json['created_by'])
          : null,
    ),
    closesAt: _date(json['closes_at']),
    isClosed: json['is_closed'] == true,
    totalVoters: (json['total_voters'] as num?)?.toInt() ?? 0,
    options: (json['options'] as List? ?? [])
        .whereType<Map>()
        .map(
          (item) =>
              AvailabilityOptionModel.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(),
  );
}

class PlanWorkItemModel {
  final String id;
  final String title;
  final String details;
  final String itemType;
  final String status;
  final CollaborationUser? assignee;
  final DateTime? dueAt;
  final DateTime? completedAt;

  const PlanWorkItemModel({
    required this.id,
    required this.title,
    required this.details,
    required this.itemType,
    required this.status,
    this.assignee,
    this.dueAt,
    this.completedAt,
  });

  factory PlanWorkItemModel.fromJson(Map<String, dynamic> json) =>
      PlanWorkItemModel(
        id: json['id'].toString(),
        title: json['title']?.toString() ?? '',
        details: json['details']?.toString() ?? '',
        itemType: json['item_type']?.toString() ?? 'task',
        status: json['status']?.toString() ?? 'todo',
        assignee: json['assignee'] is Map
            ? CollaborationUser.fromJson(
                Map<String, dynamic>.from(json['assignee']),
              )
            : null,
        dueAt: _date(json['due_at']),
        completedAt: _date(json['completed_at']),
      );
}

class PlanCommentModel {
  final String id;
  final String body;
  final String? activityTitle;
  final CollaborationUser author;
  final bool isPinned;
  final Map<String, int> reactionCounts;
  final String? currentUserReaction;
  final DateTime createdAt;

  const PlanCommentModel({
    required this.id,
    required this.body,
    this.activityTitle,
    required this.author,
    required this.isPinned,
    required this.reactionCounts,
    this.currentUserReaction,
    required this.createdAt,
  });

  factory PlanCommentModel.fromJson(Map<String, dynamic> json) =>
      PlanCommentModel(
        id: json['id'].toString(),
        body: json['body']?.toString() ?? '',
        activityTitle: json['activity_title']?.toString(),
        author: CollaborationUser.fromJson(
          json['author'] is Map
              ? Map<String, dynamic>.from(json['author'])
              : null,
        ),
        isPinned: json['is_pinned'] == true,
        reactionCounts: Map<String, int>.from(
          (json['reaction_counts'] as Map? ?? {}).map(
            (key, value) =>
                MapEntry(key.toString(), (value as num?)?.toInt() ?? 0),
          ),
        ),
        currentUserReaction: json['current_user_reaction']?.toString(),
        createdAt: _date(json['created_at']) ?? DateTime.now(),
      );
}
