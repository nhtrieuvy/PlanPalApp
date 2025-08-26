class UserSummary {
  final String id;
  final String username;
  final String displayName;
  final String initials;
  final String? avatarUrl;

  const UserSummary({
    required this.id,
    required this.username,
    required this.displayName,
    required this.initials,
    this.avatarUrl,
  });

  factory UserSummary.fromJson(Map<String, dynamic> j) {
    return UserSummary(
      id: j['id']?.toString() ?? '',
      username: j['username']?.toString() ?? '',
      displayName: j['display_name']?.toString() ?? '',
      initials: j['initials']?.toString() ?? '',
      avatarUrl: j['avatar_url']?.toString(),
    );
  }
}
