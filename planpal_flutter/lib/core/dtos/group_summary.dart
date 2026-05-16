import 'package:equatable/equatable.dart';
import 'package:planpal_flutter/core/utils/server_datetime.dart';

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
  final String visibility;
  final int memberCount;
  final String avatarUrl;
  final DateTime createdAt;
  final String initials;

  const GroupSummary({
    required this.id,
    required this.name,
    this.description,
    this.visibility = 'private',
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
      visibility: json['visibility']?.toString() ?? 'private',
      memberCount: json['member_count']?.toInt() ?? 0,
      avatarUrl: validatedAvatarUrl,
      createdAt: parseServerDateTime(json['created_at']) ?? DateTime.now(),
      initials: json['initials']?.toString() ?? 'G',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'visibility': visibility,
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
    String? visibility,
    int? memberCount,
    String? avatarUrl,
    DateTime? createdAt,
    String? initials,
  }) {
    return GroupSummary(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      visibility: visibility ?? this.visibility,
      memberCount: memberCount ?? this.memberCount,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt ?? this.createdAt,
      initials: initials ?? this.initials,
    );
  }

  /// Helper getters for UI display
  String get avatarForDisplay => avatarUrl.isNotEmpty ? avatarUrl : '';
  bool get isPublic => visibility == 'public';
  String get memberCountText =>
      '$memberCount ${memberCount == 1 ? 'member' : 'members'}';

  @override
  List<Object?> get props => [
    id,
    name,
    description,
    visibility,
    memberCount,
    avatarUrl,
    createdAt,
    initials,
  ];

  @override
  String toString() =>
      'GroupSummary(id: $id, name: $name, memberCount: $memberCount)';
}
