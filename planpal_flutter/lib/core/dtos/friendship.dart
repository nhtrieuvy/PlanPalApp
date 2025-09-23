import 'package:equatable/equatable.dart';
import 'user_summary.dart';


class Friendship extends Equatable {
  final String id;
  final UserSummary user;
  final UserSummary friend;
  final UserSummary initiator;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Friendship({
    required this.id,
    required this.user,
    required this.friend,
    required this.initiator,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Friendship.fromJson(Map<String, dynamic> json) {
    return Friendship(
      id: json['id']?.toString() ?? '',
      user: UserSummary.fromJson(json['user'] ?? {}),
      friend: UserSummary.fromJson(json['friend'] ?? {}),
      initiator: UserSummary.fromJson(json['initiator'] ?? {}),
      status: json['status']?.toString() ?? 'pending',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'].toString())
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user': user.toJson(),
      'friend': friend.toJson(),
      'initiator': initiator.toJson(),
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Friendship copyWith({
    String? id,
    UserSummary? user,
    UserSummary? friend,
    UserSummary? initiator,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Friendship(
      id: id ?? this.id,
      user: user ?? this.user,
      friend: friend ?? this.friend,
      initiator: initiator ?? this.initiator,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Helper getters for UI display
  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isRejected => status == 'rejected';
  bool get isBlocked => status == 'blocked';

  String get statusDisplay {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Friends';
      case 'rejected':
        return 'Rejected';
      case 'blocked':
        return 'Blocked';
      default:
        return status;
    }
  }

  @override
  List<Object?> get props => [
    id,
    user,
    friend,
    initiator,
    status,
    createdAt,
    updatedAt,
  ];

  @override
  String toString() =>
      'Friendship(id: $id, status: $status, friend: ${friend.username})';
}
