import 'package:equatable/equatable.dart';
import 'package:planpal_flutter/core/utils/server_datetime.dart';

bool _isValidImageUrl(String? url) {
  if (url == null || url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  return uri != null &&
      uri.isAbsolute &&
      (uri.scheme == 'http' || uri.scheme == 'https');
}

class UserModel extends Equatable {
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
  final bool isStaff;
  final String fullName;
  final String initials;

  const UserModel({
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
    required this.isStaff,
    required this.fullName,
    required this.initials,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    String? validatedAvatarUrl;
    final rawAvatarUrl = json['avatar_url']?.toString();
    if (_isValidImageUrl(rawAvatarUrl)) {
      validatedAvatarUrl = rawAvatarUrl;
    }

    return UserModel(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      email: json['email']?.toString(),
      firstName: json['first_name']?.toString() ?? '',
      lastName: json['last_name']?.toString() ?? '',
      phoneNumber: json['phone_number']?.toString(),
      avatar: json['avatar']?.toString(),
      avatarUrl: validatedAvatarUrl,
      hasAvatar: json['has_avatar'] == true,
      dateOfBirth: parseServerDateTime(json['date_of_birth']),
      bio: json['bio']?.toString(),
      isOnline: json['is_online'] == true,
      lastSeen: parseServerDateTime(json['last_seen']),
      isRecentlyOnline: json['is_recently_online'] == true,
      onlineStatus: json['online_status']?.toString() ?? 'offline',
      plansCount: _parseIntField(json['plans_count']),
      personalPlansCount: _parseIntField(json['personal_plans_count']),
      groupPlansCount: _parseIntField(json['group_plans_count']),
      groupsCount: _parseIntField(json['groups_count']),
      friendsCount: _parseIntField(json['friends_count']),
      unreadMessagesCount: _parseIntField(json['unread_messages_count']),
      dateJoined: parseServerDateTime(json['date_joined']) ?? DateTime.now(),
      isActive: json['is_active'] != false,
      isStaff: json['is_staff'] == true,
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
      'is_staff': isStaff,
      'full_name': fullName,
      'initials': initials,
    };
  }

  UserModel copyWith({
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
    bool? isStaff,
    String? fullName,
    String? initials,
  }) {
    return UserModel(
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
      isStaff: isStaff ?? this.isStaff,
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
    isStaff,
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
