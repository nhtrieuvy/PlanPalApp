import 'package:equatable/equatable.dart';

bool _isValidImageUrl(String? url) {
  if (url == null || url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  return uri != null &&
      uri.isAbsolute &&
      (uri.scheme == 'http' || uri.scheme == 'https');
}


class GroupSummary extends Equatable {
  final String id;
  final String name;
  final String? description;
  final int memberCount;
  final String avatarUrl;
  final DateTime createdAt;
  final String initials;

  const GroupSummary({
    required this.id,
    required this.name,
    this.description,
    required this.memberCount,
    required this.avatarUrl,
    required this.createdAt,
    required this.initials,
  });

  factory GroupSummary.fromJson(Map<String, dynamic> json) {
    String validatedAvatarUrl = '';
    final rawAvatarUrl = json['avatar_url']?.toString();
    if (_isValidImageUrl(rawAvatarUrl)) {
      validatedAvatarUrl = rawAvatarUrl!;
    }

    return GroupSummary(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      memberCount: json['member_count']?.toInt() ?? 0,
      avatarUrl: validatedAvatarUrl,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : DateTime.now(),
      initials: json['initials']?.toString() ?? 'G',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'member_count': memberCount,
      'avatar_url': avatarUrl,
      'created_at': createdAt.toIso8601String(),
      'initials': initials,
    };
  }

  GroupSummary copyWith({
    String? id,
    String? name,
    String? description,
    int? memberCount,
    String? avatarUrl,
    DateTime? createdAt,
    String? initials,
  }) {
    return GroupSummary(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      memberCount: memberCount ?? this.memberCount,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt ?? this.createdAt,
      initials: initials ?? this.initials,
    );
  }

  /// Helper getters for UI display
  String get avatarForDisplay => avatarUrl.isNotEmpty ? avatarUrl : '';
  String get memberCountText =>
      '$memberCount ${memberCount == 1 ? 'member' : 'members'}';

  @override
  List<Object?> get props => [
    id,
    name,
    description,
    memberCount,
    avatarUrl,
    createdAt,
    initials,
  ];

  @override
  String toString() =>
      'GroupSummary(id: $id, name: $name, memberCount: $memberCount)';
}
