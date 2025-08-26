class GroupSummary {
  final String id;
  final String name;
  final String description;
  final int memberCount;
  final bool isActive;
  final String? avatarThumb;

  const GroupSummary({
    required this.id,
    required this.name,
    required this.description,
    required this.memberCount,
    required this.isActive,
    this.avatarThumb,
  });

  factory GroupSummary.fromJson(Map<String, dynamic> j) {
    return GroupSummary(
      id: j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      description: j['description']?.toString() ?? '',
      memberCount: j['members_count'] is int
          ? j['members_count']
          : j['member_count'] is int
              ? j['member_count']
              : int.tryParse('${j['members_count'] ?? j['member_count']}') ?? 0,
      isActive: j['is_active'] == true,
      avatarThumb: j['avatar_thumb']?.toString(),
    );
  }
}
