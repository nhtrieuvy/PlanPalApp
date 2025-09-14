import 'package:equatable/equatable.dart';
import 'user_summary.dart';

/// GroupMembership model matching backend GroupMembershipSerializer
/// Represents a user's membership in a group with role information
class GroupMembership extends Equatable {
  final String id;
  final UserSummary user;
  final String role;
  final DateTime joinedAt;

  const GroupMembership({
    required this.id,
    required this.user,
    required this.role,
    required this.joinedAt,
  });

  factory GroupMembership.fromJson(Map<String, dynamic> json) {
    return GroupMembership(
      id: json['id']?.toString() ?? '',
      user: UserSummary.fromJson(json['user'] ?? {}),
      role: json['role']?.toString() ?? 'member',
      joinedAt: json['joined_at'] != null
          ? DateTime.parse(json['joined_at'].toString())
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user': user.toJson(),
      'role': role,
      'joined_at': joinedAt.toIso8601String(),
    };
  }

  GroupMembership copyWith({
    String? id,
    UserSummary? user,
    String? role,
    DateTime? joinedAt,
  }) {
    return GroupMembership(
      id: id ?? this.id,
      user: user ?? this.user,
      role: role ?? this.role,
      joinedAt: joinedAt ?? this.joinedAt,
    );
  }

  /// Helper getters for UI display
  bool get isAdmin => role == 'admin';
  bool get isMember => role == 'member';
  String get roleDisplay => role == 'admin' ? 'Admin' : 'Member';

  @override
  List<Object?> get props => [id, user, role, joinedAt];

  @override
  String toString() =>
      'GroupMembership(id: $id, user: ${user.username}, role: $role)';
}
