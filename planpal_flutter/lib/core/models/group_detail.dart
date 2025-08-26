import 'group_summary.dart';
// import 'user.dart';
import 'user_summary.dart';

class GroupDetail extends GroupSummary {
  final List<UserSummary> members;
  final String? userRole;
  final int plansCount;
  final int? activePlansCount;
  final String? coverImageUrl;
  final String? avatarUrl;
  final UserSummary? admin;
  final bool? canEdit;
  final bool? canDelete;
  final bool? isMember;

  GroupDetail({
    required super.id,
    required super.name,
    required super.description,
    required super.memberCount,
    required super.isActive,
    super.avatarThumb,
    super.initials,
    required this.members,
    required this.userRole,
    required this.plansCount,
    this.activePlansCount,
    this.coverImageUrl,
    this.avatarUrl,
    this.admin,
    this.canEdit,
    this.canDelete,
    this.isMember,
  });

  factory GroupDetail.fromJson(Map<String, dynamic> gd) {
    final summary = GroupSummary.fromJson(gd);
    final List<dynamic> membersRaw = gd['memberships'] is List
        ? List<dynamic>.from(gd['memberships'] as List)
        : const <dynamic>[];

    final members = <UserSummary>[];
    for (final item in membersRaw) {
      if (item is Map) {
        final dynamic userObj = item['user'] ?? item;
        if (userObj is Map) {
          members.add(UserSummary.fromJson(Map<String, dynamic>.from(userObj)));
        }
      }
    }

    final membersList = List<UserSummary>.unmodifiable(members);
    return GroupDetail(
      id: summary.id,
      name: summary.name,
      description: summary.description,
      memberCount: summary.memberCount,
      isActive: summary.isActive,
      initials: summary.initials,
      avatarUrl: gd['avatar_url']?.toString(),
      members: membersList,
      userRole: gd['user_role']?.toString(),
      plansCount: gd['plans_count'] is int
          ? gd['plans_count']
          : int.tryParse('${gd['plans_count']}') ?? 0,
      activePlansCount: gd['active_plans_count'] is int
          ? gd['active_plans_count']
          : int.tryParse('${gd['active_plans_count']}'),
      coverImageUrl: gd['cover_image_url']?.toString(),
      admin: gd['admin'] is Map
          ? UserSummary.fromJson(Map<String, dynamic>.from(gd['admin'] as Map))
          : null,
      canEdit: gd['can_edit'] as bool?,
      canDelete: gd['can_delete'] as bool?,
      isMember: gd['is_member'] as bool?,
    );
  }
}
