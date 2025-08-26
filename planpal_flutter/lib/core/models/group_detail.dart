import 'group_summary.dart';
import 'user.dart';
import 'user_summary.dart';

class GroupDetail extends GroupSummary {
  final List<User> members; // flattened users (full detail objects for now)
  final String? userRole;
  final int plansCount;
  final String? coverImageUrl;
  final UserSummary? admin; // typed admin summary

  GroupDetail({
    required super.id,
    required super.name,
    required super.description,
    required super.memberCount,
    required super.isActive,
    super.avatarThumb,
    required this.members,
    required this.userRole,
    required this.plansCount,
    this.coverImageUrl,
  this.admin,
  });

  factory GroupDetail.fromJson(Map<String, dynamic> j) {
    final summary = GroupSummary.fromJson(j);
    final membersRaw = j['memberships'] is List
        ? j['memberships']
        : (j['members'] is List ? j['members'] : const []);
    final members = membersRaw
        .whereType<Map>()
        .map((m) => (m['user'] is Map ? m['user'] : m))
        .whereType<Map>()
        .map((u) => User.fromJson(Map<String, dynamic>.from(u as Map)))
        .toList(growable: false);
    return GroupDetail(
      id: summary.id,
      name: summary.name,
      description: summary.description,
      memberCount: summary.memberCount,
      isActive: summary.isActive,
      avatarThumb: summary.avatarThumb,
      members: members,
      userRole: j['user_role']?.toString(),
      plansCount: j['plans_count'] is int ? j['plans_count'] : int.tryParse('${j['plans_count']}') ?? 0,
      coverImageUrl: j['cover_image_url']?.toString(),
      admin: j['admin'] is Map ? UserSummary.fromJson(Map<String, dynamic>.from(j['admin'] as Map)) : null,
    );
  }
}
