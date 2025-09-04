class GroupSummary {
  final String id;
  final String name;
  final String description;
  final int memberCount;
  final bool isActive;
  final String? avatarThumb;
  final String? initials;

  const GroupSummary({
    required this.id,
    required this.name,
    required this.description,
    required this.memberCount,
    required this.isActive,
    this.avatarThumb,
    this.initials,
  });

  // factory là constructor đặc biệt cho phép chạy logic trước khi trả về một instance; nó không nhất thiết phải tạo object mới
  factory GroupSummary.fromJson(Map<String, dynamic> gs) {
    return GroupSummary(
      id: gs['id']?.toString() ?? '',
      name: gs['name']?.toString() ?? '',
      description: gs['description']?.toString() ?? '',
      memberCount: gs['member_count'] is int
          ? gs['member_count'] as int
          : int.tryParse('${gs['member_count']}') ?? 0,
      isActive: gs['is_active'] == true,
      avatarThumb: gs['avatar_thumb']?.toString(),
      initials: gs['initials']?.toString(),
    );
  }
}
