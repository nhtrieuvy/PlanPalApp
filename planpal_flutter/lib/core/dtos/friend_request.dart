import 'user_summary.dart';

class FriendRequest {
  final String id;
  final UserSummary user;
  final String status;
  final DateTime createdAt;
  final String? message;

  const FriendRequest({
    required this.id,
    required this.user,
    required this.status,
    required this.createdAt,
    this.message,
  });

  factory FriendRequest.fromJson(Map<String, dynamic> json) {
    return FriendRequest(
      id: json['id']?.toString() ?? '',
      user: UserSummary.fromJson(Map<String, dynamic>.from(json['user'] ?? {})),
      status: json['status']?.toString() ?? 'pending',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      message: json['message']?.toString(),
    );
  }

  bool get isPending => status == 'pending';
}
