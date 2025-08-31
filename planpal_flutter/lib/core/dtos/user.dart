import 'package:equatable/equatable.dart';

bool _isValidImageUrl(String? url) {
  if (url == null || url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  return uri != null &&
      uri.isAbsolute &&
      (uri.scheme == 'http' || uri.scheme == 'https');
}

class User extends Equatable {
  final String? id;
  final String username;
  final String firstName;
  final String lastName;
  final String fullName;
  final String initials;
  final String? avatarUrl;
  final String? email;
  final String? phoneNumber;
  final String? dateOfBirth;
  final String? bio;
  final int plansCount;
  final int groupsCount;
  final int friendsCount;

  const User({
    this.id,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.fullName,
    required this.initials,
    this.avatarUrl,
    this.email,
    this.phoneNumber,
    this.dateOfBirth,
    this.bio,
    this.plansCount = 0,
    this.groupsCount = 0,
    this.friendsCount = 0,
  });

  factory User.fromJson(Map<String, dynamic> raw) {
    String? avatarUrl;
    final rawAvatar = raw['avatar_url']?.toString();
    if (_isValidImageUrl(rawAvatar)) {
      avatarUrl = rawAvatar;
    }

    return User(
      id: raw['id']?.toString(),
      avatarUrl: avatarUrl,
      username: raw['username']?.toString() ?? '',
      firstName: raw['first_name']?.toString() ?? '',
      lastName: raw['last_name']?.toString() ?? '',
      fullName: raw['full_name']?.toString() ?? '',
      initials: raw['initials']?.toString() ?? '',
      email: raw['email']?.toString(),
      phoneNumber: raw['phone_number']?.toString(),
      dateOfBirth: raw['date_of_birth']?.toString(),
      bio: raw['bio']?.toString(),
      plansCount: raw['plans_count'] is int
          ? raw['plans_count'] as int
          : int.tryParse('${raw['plans_count']}') ?? 0,
      groupsCount: raw['groups_count'] is int
          ? raw['groups_count'] as int
          : int.tryParse('${raw['groups_count']}') ?? 0,
      friendsCount: raw['friends_count'] is int
          ? raw['friends_count'] as int
          : int.tryParse('${raw['friends_count']}') ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'first_name': firstName,
      'last_name': lastName,
      'full_name': fullName,
      'initials': initials,
      'avatar_url': avatarUrl,
      'email': email,
      'phone_number': phoneNumber,
      'date_of_birth': dateOfBirth,
      'bio': bio,
      'plans_count': plansCount,
      'groups_count': groupsCount,
      'friends_count': friendsCount,
    };
  }

  User copyWith({
    String? id,
    String? username,
    String? firstName,
    String? lastName,
    String? fullName,
    String? initials,
    String? avatarUrl,
    String? email,
    String? phoneNumber,
    String? dateOfBirth,
    String? bio,
    int? plansCount,
    int? groupsCount,
    int? friendsCount,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      fullName: fullName ?? this.fullName,
      initials: initials ?? this.initials,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      bio: bio ?? this.bio,
      plansCount: plansCount ?? this.plansCount,
      groupsCount: groupsCount ?? this.groupsCount,
      friendsCount: friendsCount ?? this.friendsCount,
    );
  }

  @override
  List<Object?> get props => [
    id,
    username,
    firstName,
    lastName,
    fullName,
    initials,
    avatarUrl,
    email,
    phoneNumber,
    dateOfBirth,
    bio,
    plansCount,
    groupsCount,
    friendsCount,
  ];
}
