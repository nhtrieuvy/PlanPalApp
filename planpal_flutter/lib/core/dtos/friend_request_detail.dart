import 'package:equatable/equatable.dart';
import 'user_summary.dart';

/// FriendRequestDetail model for displaying pending friend requests
/// Represents a pending friendship with status information
class FriendRequestDetail extends Equatable {
  final String id;
  final UserSummary user;
  final UserSummary initiator;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FriendRequestDetail({
    required this.id,
    required this.user,
    required this.initiator,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FriendRequestDetail.fromJson(Map<String, dynamic> json) {
    return FriendRequestDetail(
      id: json['id']?.toString() ?? '',
      user: UserSummary.fromJson(json['user'] ?? {}),
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
      'initiator': initiator.toJson(),
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  FriendRequestDetail copyWith({
    String? id,
    UserSummary? user,
    UserSummary? initiator,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FriendRequestDetail(
      id: id ?? this.id,
      user: user ?? this.user,
      initiator: initiator ?? this.initiator,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Helper getters for UI display
  bool get isPending => status == 'pending';
  UserSummary get sender => initiator;
  String get senderName =>
      initiator.fullName.isNotEmpty ? initiator.fullName : initiator.username;

  @override
  List<Object?> get props => [
    id,
    user,
    initiator,
    status,
    createdAt,
    updatedAt,
  ];

  @override
  String toString() =>
      'FriendRequestDetail(id: $id, from: ${initiator.username}, status: $status)';
}
