import 'package:equatable/equatable.dart';

class User extends Equatable {
  final String? id;
  final String username;
  final String firstName;
  final String lastName;
  final String displayName;
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
    required this.displayName,
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
    final firstName = (raw['first_name'] ?? '').toString();
    final lastName = (raw['last_name'] ?? '').toString();
    final username = (raw['username'] ?? '').toString();
    final email = (raw['email'] ?? '').toString();

    String displayName = [
      firstName,
      lastName,
    ].where((e) => e.isNotEmpty).join(' ').trim();
    if (displayName.isEmpty) {
      displayName = username.isNotEmpty ? username : email;
    }

    String initials = '';
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isNotEmpty) {
      initials = parts
          .take(2)
          .map((p) => p.isNotEmpty ? p[0] : '')
          .join()
          .toUpperCase();
    }

    String? avatarUrl;
    final avatar = raw['avatar'];
    if (avatar is String && avatar.isNotEmpty) {
      avatarUrl = avatar;
    } else if (avatar is Map && avatar['url'] is String) {
      avatarUrl = avatar['url'] as String;
    }

    return User(
      id: raw['id']?.toString(),
      username: username,
      firstName: firstName,
      lastName: lastName,
      displayName: displayName,
      initials: initials,
      avatarUrl: avatarUrl,
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
      'display_name': displayName,
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
    String? displayName,
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
      displayName: displayName ?? this.displayName,
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

  // Convenience computed properties / flags
  bool get hasAvatar => (avatarUrl != null && avatarUrl!.isNotEmpty);
  String get fullName =>
      [firstName, lastName].where((e) => e.isNotEmpty).join(' ').trim();
  String get primaryDisplay => displayName.isNotEmpty
      ? displayName
      : (fullName.isNotEmpty ? fullName : username);

  @override
  List<Object?> get props => [
    id,
    username,
    firstName,
    lastName,
    displayName,
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
