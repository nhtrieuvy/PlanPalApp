import 'package:equatable/equatable.dart';

/// CreateFriendRequest model matching backend FriendRequestSerializer
/// Represents a friend request payload sent from client to server
class FriendRequest extends Equatable {
  final String friendId;
  final String? message;

  const FriendRequest({required this.friendId, this.message});

  factory FriendRequest.fromJson(Map<String, dynamic> json) {
    return FriendRequest(
      friendId: json['friend_id']?.toString() ?? '',
      message: json['message']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'friend_id': friendId, 'message': message};
  }

  FriendRequest copyWith({String? friendId, String? message}) {
    return FriendRequest(
      friendId: friendId ?? this.friendId,
      message: message ?? this.message,
    );
  }

  /// Helper getters for UI display
  bool get hasMessage => message != null && message!.isNotEmpty;

  @override
  List<Object?> get props => [friendId, message];

  @override
  String toString() =>
      'FriendRequest(friendId: $friendId, hasMessage: $hasMessage)';
}
