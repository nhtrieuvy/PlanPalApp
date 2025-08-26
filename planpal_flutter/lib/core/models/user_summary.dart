class UserSummary {
  final String id;
  final String username;
  final String displayName;
  final String initials;
  final String? avatarThumb;
  final String? avatarUrl;
  final String fullName;
  final String? firstName;
  final String? lastName;
  final String? email;
  final bool isOnline;
  final DateTime? dateJoined;
  final DateTime? lastSeen;

  const UserSummary({
    required this.id,
    required this.username,
    required this.displayName,
    required this.initials,
    required this.fullName,
    this.avatarThumb,
    this.avatarUrl,
    this.firstName,
    this.lastName,
    this.email,
    this.isOnline = false,
    this.dateJoined,
    this.lastSeen,
  });

  factory UserSummary.fromJson(Map<String, dynamic> j) {
    return UserSummary(
      id: j['id']?.toString() ?? '',
      username: j['username']?.toString() ?? '',
      displayName: j['display_name']?.toString() ?? '',
      initials: j['initials']?.toString() ?? '',
      fullName:
          j['full_name']?.toString() ?? j['display_name']?.toString() ?? '',
      avatarThumb: j['avatar_thumb']?.toString(),
      avatarUrl: j['avatar_url']?.toString(),
      firstName: j['first_name']?.toString(),
      lastName: j['last_name']?.toString(),
      email: j['email']?.toString(),
      isOnline: j['is_online'] == true,
      dateJoined: j['date_joined'] != null
          ? DateTime.tryParse(j['date_joined'].toString())
          : null,
      lastSeen: j['last_seen'] != null
          ? DateTime.tryParse(j['last_seen'].toString())
          : null,
    );
  }

  // Helper getter for avatar display
  String get avatarForDisplay => avatarUrl ?? avatarThumb ?? '';

  // Status text helper
  String get statusText => isOnline ? 'Online' : 'Offline';
}
