import 'package:equatable/equatable.dart';
import 'package:planpal_flutter/core/utils/server_datetime.dart';

class SearchResultItem extends Equatable {
  const SearchResultItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
  });

  final String id;
  final String type;
  final String title;
  final String subtitle;

  factory SearchResultItem.fromJson(String type, Map<String, dynamic> json) =>
      SearchResultItem(
        id: json['id']?.toString() ?? '',
        type: type,
        title: json['title']?.toString() ?? '',
        subtitle: json['subtitle']?.toString() ?? '',
      );

  @override
  List<Object?> get props => [id, type, title, subtitle];
}

class GlobalSearchResult extends Equatable {
  const GlobalSearchResult({required this.query, required this.items});

  final String query;
  final List<SearchResultItem> items;

  factory GlobalSearchResult.fromJson(Map<String, dynamic> json) {
    final items = <SearchResultItem>[];
    for (final entry in const {
      'plans': 'plan',
      'groups': 'group',
      'chats': 'chat',
    }.entries) {
      for (final raw in json[entry.key] as List? ?? const []) {
        if (raw is Map) {
          items.add(
            SearchResultItem.fromJson(
              entry.value,
              Map<String, dynamic>.from(raw),
            ),
          );
        }
      }
    }
    return GlobalSearchResult(
      query: json['query']?.toString() ?? '',
      items: items,
    );
  }

  @override
  List<Object?> get props => [query, items];
}

class GroupPollOptionModel extends Equatable {
  const GroupPollOptionModel({
    required this.id,
    required this.text,
    required this.voteCount,
    this.voters = const [],
  });
  final String id;
  final String text;
  final int voteCount;
  final List<GroupPollVoterModel> voters;

  factory GroupPollOptionModel.fromJson(Map<String, dynamic> json) =>
      GroupPollOptionModel(
        id: json['id']?.toString() ?? '',
        text: json['text']?.toString() ?? '',
        voteCount: int.tryParse(json['vote_count']?.toString() ?? '') ?? 0,
        voters: (json['voters'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (item) =>
                  GroupPollVoterModel.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList(),
      );

  @override
  List<Object?> get props => [id, text, voteCount, voters];
}

class GroupPollVoterModel extends Equatable {
  const GroupPollVoterModel({
    required this.id,
    required this.username,
    required this.fullName,
    required this.avatarUrl,
  });

  final String id;
  final String username;
  final String fullName;
  final String avatarUrl;

  factory GroupPollVoterModel.fromJson(Map<String, dynamic> json) =>
      GroupPollVoterModel(
        id: json['id']?.toString() ?? '',
        username: json['username']?.toString() ?? '',
        fullName: json['full_name']?.toString() ?? '',
        avatarUrl: json['avatar_url']?.toString() ?? '',
      );

  String get displayName => fullName.isNotEmpty ? fullName : username;

  @override
  List<Object?> get props => [id, username, fullName, avatarUrl];
}

class GroupPollModel extends Equatable {
  const GroupPollModel({
    required this.id,
    required this.groupId,
    required this.question,
    required this.allowMultiple,
    required this.isClosed,
    required this.options,
    required this.selectedOptionIds,
    required this.totalVotes,
    required this.createdById,
    this.closesAt,
  });

  final String id;
  final String groupId;
  final String question;
  final bool allowMultiple;
  final bool isClosed;
  final List<GroupPollOptionModel> options;
  final Set<String> selectedOptionIds;
  final int totalVotes;
  final String createdById;
  final DateTime? closesAt;

  factory GroupPollModel.fromJson(Map<String, dynamic> json) => GroupPollModel(
    id: json['id']?.toString() ?? '',
    groupId: json['group_id']?.toString() ?? '',
    question: json['question']?.toString() ?? '',
    allowMultiple: json['allow_multiple'] == true,
    isClosed: json['is_closed'] == true,
    options: (json['options'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              GroupPollOptionModel.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(),
    selectedOptionIds: (json['selected_option_ids'] as List? ?? const [])
        .map((value) => value.toString())
        .toSet(),
    totalVotes: int.tryParse(json['total_votes']?.toString() ?? '') ?? 0,
    createdById: (json['created_by'] as Map?)?['id']?.toString() ?? '',
    closesAt: parseServerDateTime(json['closes_at']),
  );

  @override
  List<Object?> get props => [
    id,
    groupId,
    question,
    allowMultiple,
    isClosed,
    options,
    selectedOptionIds,
    totalVotes,
    createdById,
    closesAt,
  ];
}

class LiveLocationModel extends Equatable {
  const LiveLocationModel({
    required this.id,
    required this.conversationId,
    required this.userId,
    required this.userName,
    required this.latitude,
    required this.longitude,
    required this.expiresAt,
    required this.isActive,
    required this.updatedAt,
    this.accuracyMeters,
  });

  final String id;
  final String conversationId;
  final String userId;
  final String userName;
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final DateTime expiresAt;
  final bool isActive;
  final DateTime updatedAt;

  factory LiveLocationModel.fromJson(Map<String, dynamic> json) {
    final user = Map<String, dynamic>.from(json['user'] as Map? ?? const {});
    return LiveLocationModel(
      id: json['id']?.toString() ?? '',
      conversationId: json['conversation_id']?.toString() ?? '',
      userId: user['id']?.toString() ?? '',
      userName: user['full_name']?.toString().trim().isNotEmpty == true
          ? user['full_name'].toString()
          : user['username']?.toString() ?? '',
      latitude: double.tryParse(json['latitude']?.toString() ?? '') ?? 0,
      longitude: double.tryParse(json['longitude']?.toString() ?? '') ?? 0,
      accuracyMeters: double.tryParse(
        json['accuracy_meters']?.toString() ?? '',
      ),
      expiresAt: parseServerDateTime(json['expires_at']) ?? DateTime.now(),
      isActive: json['is_active'] == true,
      updatedAt: parseServerDateTime(json['updated_at']) ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
    id,
    conversationId,
    userId,
    userName,
    latitude,
    longitude,
    accuracyMeters,
    expiresAt,
    isActive,
    updatedAt,
  ];
}
