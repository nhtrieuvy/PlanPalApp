import 'package:equatable/equatable.dart';

/// Utility function to validate image URLs
bool _isValidImageUrl(String? url) {
  if (url == null || url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  return uri != null &&
      uri.isAbsolute &&
      (uri.scheme == 'http' || uri.scheme == 'https');
}

/// UserSummary model matching backend UserSummarySerializer
/// Lightweight version of User for lists and references
class UserSummary extends Equatable {
  final String id;
  final String username;
  final String firstName;
  final String lastName;
  final String? email;
  final bool isOnline;
  final String onlineStatus;
  final String? avatarUrl;
  final bool hasAvatar;
  final DateTime dateJoined;
  final DateTime? lastSeen;
  final String fullName;
  final String initials;

  const UserSummary({
    required this.id,
    required this.username,
    required this.firstName,
    required this.lastName,
    this.email,
    required this.isOnline,
    required this.onlineStatus,
    this.avatarUrl,
    required this.hasAvatar,
    required this.dateJoined,
    this.lastSeen,
    required this.fullName,
    required this.initials,
  });

  factory UserSummary.fromJson(Map<String, dynamic> json) {
    String? validatedAvatarUrl;
    final rawAvatarUrl = json['avatar_url']?.toString();
    if (_isValidImageUrl(rawAvatarUrl)) {
      validatedAvatarUrl = rawAvatarUrl;
    }

    return UserSummary(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      firstName: json['first_name']?.toString() ?? '',
      lastName: json['last_name']?.toString() ?? '',
      email: json['email']?.toString(),
      isOnline: json['is_online'] == true,
      onlineStatus: json['online_status']?.toString() ?? 'offline',
      avatarUrl: validatedAvatarUrl,
      hasAvatar: json['has_avatar'] == true,
      dateJoined: json['date_joined'] != null
          ? DateTime.parse(json['date_joined'].toString())
          : DateTime.now(),
      lastSeen: json['last_seen'] != null
          ? DateTime.tryParse(json['last_seen'].toString())
          : null,
      fullName: json['full_name']?.toString() ?? '',
      initials: json['initials']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'is_online': isOnline,
      'online_status': onlineStatus,
      'avatar_url': avatarUrl,
      'has_avatar': hasAvatar,
      'date_joined': dateJoined.toIso8601String(),
      'last_seen': lastSeen?.toIso8601String(),
      'full_name': fullName,
      'initials': initials,
    };
  }

  UserSummary copyWith({
    String? id,
    String? username,
    String? firstName,
    String? lastName,
    String? email,
    bool? isOnline,
    String? onlineStatus,
    String? avatarUrl,
    bool? hasAvatar,
    DateTime? dateJoined,
    DateTime? lastSeen,
    String? fullName,
    String? initials,
  }) {
    return UserSummary(
      id: id ?? this.id,
      username: username ?? this.username,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      isOnline: isOnline ?? this.isOnline,
      onlineStatus: onlineStatus ?? this.onlineStatus,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      hasAvatar: hasAvatar ?? this.hasAvatar,
      dateJoined: dateJoined ?? this.dateJoined,
      lastSeen: lastSeen ?? this.lastSeen,
      fullName: fullName ?? this.fullName,
      initials: initials ?? this.initials,
    );
  }

  /// Helper getters for UI display
  String get avatarForDisplay => avatarUrl ?? '';
  String get statusText => isOnline ? 'Online' : 'Offline';

  @override
  List<Object?> get props => [
    id,
    username,
    firstName,
    lastName,
    email,
    isOnline,
    onlineStatus,
    avatarUrl,
    hasAvatar,
    dateJoined,
    lastSeen,
    fullName,
    initials,
  ];

  @override
  String toString() =>
      'UserSummary(id: $id, username: $username, fullName: $fullName)';
}
