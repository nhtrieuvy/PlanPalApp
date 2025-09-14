import 'package:equatable/equatable.dart';

/// Utility function to validate image URLs
bool _isValidImageUrl(String? url) {
  if (url == null || url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  return uri != null &&
      uri.isAbsolute &&
      (uri.scheme == 'http' || uri.scheme == 'https');
}

/// User model matching backend UserSerializer
class User extends Equatable {
  final String id;
  final String username;
  final String? email;
  final String firstName;
  final String lastName;
  final String? phoneNumber;
  final String? avatar;
  final String? avatarUrl;
  final bool hasAvatar;
  final DateTime? dateOfBirth;
  final String? bio;
  final bool isOnline;
  final DateTime? lastSeen;
  final bool isRecentlyOnline;
  final String onlineStatus;
  final int plansCount;
  final int personalPlansCount;
  final int groupPlansCount;
  final int groupsCount;
  final int friendsCount;
  final int unreadMessagesCount;
  final DateTime dateJoined;
  final bool isActive;
  final String fullName;
  final String initials;

  const User({
    required this.id,
    required this.username,
    this.email,
    required this.firstName,
    required this.lastName,
    this.phoneNumber,
    this.avatar,
    this.avatarUrl,
    required this.hasAvatar,
    this.dateOfBirth,
    this.bio,
    required this.isOnline,
    this.lastSeen,
    required this.isRecentlyOnline,
    required this.onlineStatus,
    required this.plansCount,
    required this.personalPlansCount,
    required this.groupPlansCount,
    required this.groupsCount,
    required this.friendsCount,
    required this.unreadMessagesCount,
    required this.dateJoined,
    required this.isActive,
    required this.fullName,
    required this.initials,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    String? validatedAvatarUrl;
    final rawAvatarUrl = json['avatar_url']?.toString();
    if (_isValidImageUrl(rawAvatarUrl)) {
      validatedAvatarUrl = rawAvatarUrl;
    }

    return User(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      email: json['email']?.toString(),
      firstName: json['first_name']?.toString() ?? '',
      lastName: json['last_name']?.toString() ?? '',
      phoneNumber: json['phone_number']?.toString(),
      avatar: json['avatar']?.toString(),
      avatarUrl: validatedAvatarUrl,
      hasAvatar: json['has_avatar'] == true,
      dateOfBirth: json['date_of_birth'] != null
          ? DateTime.tryParse(json['date_of_birth'].toString())
          : null,
      bio: json['bio']?.toString(),
      isOnline: json['is_online'] == true,
      lastSeen: json['last_seen'] != null
          ? DateTime.tryParse(json['last_seen'].toString())
          : null,
      isRecentlyOnline: json['is_recently_online'] == true,
      onlineStatus: json['online_status']?.toString() ?? 'offline',
      plansCount: _parseIntField(json['plans_count']),
      personalPlansCount: _parseIntField(json['personal_plans_count']),
      groupPlansCount: _parseIntField(json['group_plans_count']),
      groupsCount: _parseIntField(json['groups_count']),
      friendsCount: _parseIntField(json['friends_count']),
      unreadMessagesCount: _parseIntField(json['unread_messages_count']),
      dateJoined: json['date_joined'] != null
          ? DateTime.parse(json['date_joined'].toString())
          : DateTime.now(),
      isActive: json['is_active'] != false,
      fullName: json['full_name']?.toString() ?? '',
      initials: json['initials']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'first_name': firstName,
      'last_name': lastName,
      'phone_number': phoneNumber,
      'avatar': avatar,
      'avatar_url': avatarUrl,
      'has_avatar': hasAvatar,
      'date_of_birth': dateOfBirth?.toIso8601String(),
      'bio': bio,
      'is_online': isOnline,
      'last_seen': lastSeen?.toIso8601String(),
      'is_recently_online': isRecentlyOnline,
      'online_status': onlineStatus,
      'plans_count': plansCount,
      'personal_plans_count': personalPlansCount,
      'group_plans_count': groupPlansCount,
      'groups_count': groupsCount,
      'friends_count': friendsCount,
      'unread_messages_count': unreadMessagesCount,
      'date_joined': dateJoined.toIso8601String(),
      'is_active': isActive,
      'full_name': fullName,
      'initials': initials,
    };
  }

  User copyWith({
    String? id,
    String? username,
    String? email,
    String? firstName,
    String? lastName,
    String? phoneNumber,
    String? avatar,
    String? avatarUrl,
    bool? hasAvatar,
    DateTime? dateOfBirth,
    String? bio,
    bool? isOnline,
    DateTime? lastSeen,
    bool? isRecentlyOnline,
    String? onlineStatus,
    int? plansCount,
    int? personalPlansCount,
    int? groupPlansCount,
    int? groupsCount,
    int? friendsCount,
    int? unreadMessagesCount,
    DateTime? dateJoined,
    bool? isActive,
    String? fullName,
    String? initials,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      avatar: avatar ?? this.avatar,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      hasAvatar: hasAvatar ?? this.hasAvatar,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      bio: bio ?? this.bio,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      isRecentlyOnline: isRecentlyOnline ?? this.isRecentlyOnline,
      onlineStatus: onlineStatus ?? this.onlineStatus,
      plansCount: plansCount ?? this.plansCount,
      personalPlansCount: personalPlansCount ?? this.personalPlansCount,
      groupPlansCount: groupPlansCount ?? this.groupPlansCount,
      groupsCount: groupsCount ?? this.groupsCount,
      friendsCount: friendsCount ?? this.friendsCount,
      unreadMessagesCount: unreadMessagesCount ?? this.unreadMessagesCount,
      dateJoined: dateJoined ?? this.dateJoined,
      isActive: isActive ?? this.isActive,
      fullName: fullName ?? this.fullName,
      initials: initials ?? this.initials,
    );
  }

  @override
  List<Object?> get props => [
    id,
    username,
    email,
    firstName,
    lastName,
    phoneNumber,
    avatar,
    avatarUrl,
    hasAvatar,
    dateOfBirth,
    bio,
    isOnline,
    lastSeen,
    isRecentlyOnline,
    onlineStatus,
    plansCount,
    personalPlansCount,
    groupPlansCount,
    groupsCount,
    friendsCount,
    unreadMessagesCount,
    dateJoined,
    isActive,
    fullName,
    initials,
  ];

  @override
  String toString() =>
      'User(id: $id, username: $username, fullName: $fullName)';
}

/// Utility function to safely parse integer fields
int _parseIntField(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
