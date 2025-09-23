import 'package:equatable/equatable.dart';
import 'user_summary.dart';
import 'group_membership.dart';


bool _isValidImageUrl(String? url) {
  if (url == null || url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  return uri != null &&
      uri.isAbsolute &&
      (uri.scheme == 'http' || uri.scheme == 'https');
}


class GroupModel extends Equatable {
  final String id;
  final String name;
  final String? description;
  final String? avatar;
  final String? coverImage;
  final String avatarUrl;
  final bool hasAvatar;
  final String coverImageUrl;
  final bool hasCoverImage;
  final UserSummary admin;
  final List<GroupMembership> memberships;
  final int memberCount;
  final int plansCount;
  final int activePlansCount;
  final bool isActive;
  final bool isMember;
  final String userRole;
  final bool canEdit;
  final bool canDelete;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String initials;

  const GroupModel({
    required this.id,
    required this.name,
    this.description,
    this.avatar,
    this.coverImage,
    required this.avatarUrl,
    required this.hasAvatar,
    required this.coverImageUrl,
    required this.hasCoverImage,
    required this.admin,
    required this.memberships,
    required this.memberCount,
    required this.plansCount,
    required this.activePlansCount,
    required this.isActive,
    required this.isMember,
    required this.userRole,
    required this.canEdit,
    required this.canDelete,
    required this.createdAt,
    required this.updatedAt,
    required this.initials,
  });

  factory GroupModel.fromJson(Map<String, dynamic> json) {
    String validatedAvatarUrl = '';
    String validatedCoverImageUrl = '';

    final rawAvatarUrl = json['avatar_url']?.toString();
    if (_isValidImageUrl(rawAvatarUrl)) {
      validatedAvatarUrl = rawAvatarUrl!;
    }

    final rawCoverImageUrl = json['cover_image_url']?.toString();
    if (_isValidImageUrl(rawCoverImageUrl)) {
      validatedCoverImageUrl = rawCoverImageUrl!;
    }

    final membershipsList = json['memberships'] as List<dynamic>? ?? [];
    final memberships = membershipsList
        .map((membershipJson) => GroupMembership.fromJson(membershipJson))
        .toList();

    return GroupModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      avatar: json['avatar']?.toString(),
      coverImage: json['cover_image']?.toString(),
      avatarUrl: validatedAvatarUrl,
      hasAvatar: json['has_avatar'] == true,
      coverImageUrl: validatedCoverImageUrl,
      hasCoverImage: json['has_cover_image'] == true,
      admin: UserSummary.fromJson(json['admin'] ?? {}),
      memberships: memberships,
      memberCount: json['member_count']?.toInt() ?? 0,
      plansCount: json['plans_count']?.toInt() ?? 0,
      activePlansCount: json['active_plans_count']?.toInt() ?? 0,
      isActive: json['is_active'] == true,
      isMember: json['is_member'] == true,
      userRole: json['user_role']?.toString() ?? 'member',
      canEdit: json['can_edit'] == true,
      canDelete: json['can_delete'] == true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'].toString())
          : DateTime.now(),
      initials: json['initials']?.toString() ?? 'G',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'avatar': avatar,
      'cover_image': coverImage,
      'avatar_url': avatarUrl,
      'has_avatar': hasAvatar,
      'cover_image_url': coverImageUrl,
      'has_cover_image': hasCoverImage,
      'admin': admin.toJson(),
      'memberships': memberships.map((m) => m.toJson()).toList(),
      'member_count': memberCount,
      'plans_count': plansCount,
      'active_plans_count': activePlansCount,
      'is_active': isActive,
      'is_member': isMember,
      'user_role': userRole,
      'can_edit': canEdit,
      'can_delete': canDelete,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'initials': initials,
    };
  }

  GroupModel copyWith({
    String? id,
    String? name,
    String? description,
    String? avatar,
    String? coverImage,
    String? avatarUrl,
    bool? hasAvatar,
    String? coverImageUrl,
    bool? hasCoverImage,
    UserSummary? admin,
    List<GroupMembership>? memberships,
    int? memberCount,
    int? plansCount,
    int? activePlansCount,
    bool? isActive,
    bool? isMember,
    String? userRole,
    bool? canEdit,
    bool? canDelete,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? initials,
  }) {
    return GroupModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      avatar: avatar ?? this.avatar,
      coverImage: coverImage ?? this.coverImage,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      hasAvatar: hasAvatar ?? this.hasAvatar,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      hasCoverImage: hasCoverImage ?? this.hasCoverImage,
      admin: admin ?? this.admin,
      memberships: memberships ?? this.memberships,
      memberCount: memberCount ?? this.memberCount,
      plansCount: plansCount ?? this.plansCount,
      activePlansCount: activePlansCount ?? this.activePlansCount,
      isActive: isActive ?? this.isActive,
      isMember: isMember ?? this.isMember,
      userRole: userRole ?? this.userRole,
      canEdit: canEdit ?? this.canEdit,
      canDelete: canDelete ?? this.canDelete,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      initials: initials ?? this.initials,
    );
  }

  /// Helper getters for UI display
  String get avatarForDisplay => avatarUrl.isNotEmpty ? avatarUrl : '';
  String get coverImageForDisplay =>
      coverImageUrl.isNotEmpty ? coverImageUrl : '';
  bool get isAdmin => userRole == 'admin';
  String get memberCountText =>
      '$memberCount ${memberCount == 1 ? 'member' : 'members'}';
  String get plansCountText =>
      '$plansCount ${plansCount == 1 ? 'plan' : 'plans'}';

  /// Get list of members from memberships
  List<UserSummary> get members => memberships.map((m) => m.user).toList();

  @override
  List<Object?> get props => [
    id,
    name,
    description,
    avatar,
    coverImage,
    avatarUrl,
    hasAvatar,
    coverImageUrl,
    hasCoverImage,
    admin,
    memberships,
    memberCount,
    plansCount,
    activePlansCount,
    isActive,
    isMember,
    userRole,
    canEdit,
    canDelete,
    createdAt,
    updatedAt,
    initials,
  ];

  @override
  String toString() =>
      'GroupModel(id: $id, name: $name, memberCount: $memberCount)';
}
