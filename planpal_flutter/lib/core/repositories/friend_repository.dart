import 'package:dio/dio.dart';
import 'package:planpal_flutter/core/providers/auth_provider.dart';
import 'package:planpal_flutter/core/services/apis.dart';
import 'package:planpal_flutter/core/services/api_error.dart';
import '../dtos/user_summary.dart';
import '../dtos/friendship.dart';
import '../dtos/friend_request_detail.dart';

class FriendRepository {
  final AuthProvider auth;
  FriendRepository(this.auth);

  Never _throwApiError(Response res) => throw buildApiException(res);

  /// Search users for friend requests
  Future<List<UserSummary>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];

    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.get(
          Endpoints.searchUsers,
          queryParameters: {'q': query.trim()},
        ),
      );

      if (res.statusCode == 200) {
        final data = res.data;
        final List<dynamic> users = data['users'] ?? [];
        return users
            .whereType<Map>()
            .map(
              (user) => UserSummary.fromJson(Map<String, dynamic>.from(user)),
            )
            .toList();
      }
      return _throwApiError(res);
    } on DioException catch (e) {
      final res = e.response;
      if (res != null) return _throwApiError(res);
      rethrow;
    }
  }

  /// Send friend request
  Future<Friendship> sendFriendRequest(
    String friendId, {
    String? message,
  }) async {
    try {
      final payload = {
        'friend_id': friendId,
        if (message != null && message.isNotEmpty) 'message': message,
      };

      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.post(Endpoints.friendRequest, data: payload),
      );

      if (res.statusCode == 201 || res.statusCode == 200) {
        final friendship = res.data['friendship'] ?? res.data;
        return Friendship.fromJson(Map<String, dynamic>.from(friendship));
      }
      return _throwApiError(res);
    } on DioException catch (e) {
      final res = e.response;
      if (res != null) return _throwApiError(res);
      rethrow;
    }
  }

  /// Get pending friend requests (received)
  Future<List<FriendRequestDetail>> getPendingRequests() async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.get(Endpoints.friendRequests),
      );

      if (res.statusCode == 200) {
        final List<dynamic> requests = res.data is List
            ? res.data
            : (res.data['results'] ?? []);
        return requests
            .whereType<Map>()
            .map(
              (req) =>
                  FriendRequestDetail.fromJson(Map<String, dynamic>.from(req)),
            )
            .toList();
      }
      return _throwApiError(res);
    } on DioException catch (e) {
      final res = e.response;
      if (res != null) return _throwApiError(res);
      rethrow;
    }
  }

  /// Accept friend request
  Future<bool> acceptFriendRequest(String requestId) async {
    return _handleFriendRequestAction(requestId, 'accept');
  }

  /// Reject friend request
  Future<bool> rejectFriendRequest(String requestId) async {
    return _handleFriendRequestAction(requestId, 'reject');
  }

  /// Unfriend/Remove friendship
  Future<bool> unfriend(String friendId) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.delete(Endpoints.userUnfriend(friendId)),
      );

      return res.statusCode == 200;
    } on DioException catch (e) {
      final res = e.response;
      if (res != null) return _throwApiError(res);
      rethrow;
    }
  }

  /// Block user
  Future<bool> blockUser(String userId) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.post(Endpoints.userBlock(userId)),
      );

      return res.statusCode == 200;
    } on DioException catch (e) {
      final res = e.response;
      if (res != null) return _throwApiError(res);
      rethrow;
    }
  }

  /// Unblock user
  Future<bool> unblockUser(String userId) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.delete(Endpoints.userUnblock(userId)),
      );

      return res.statusCode == 200;
    } on DioException catch (e) {
      final res = e.response;
      if (res != null) return _throwApiError(res);
      rethrow;
    }
  }

  Future<bool> _handleFriendRequestAction(
    String requestId,
    String action,
  ) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.post(
          Endpoints.friendRequestAction(requestId),
          data: {'action': action},
        ),
      );

      return res.statusCode == 200;
    } on DioException catch (e) {
      final res = e.response;
      if (res != null) _throwApiError(res);
      rethrow;
    }
  }

  /// Get friends list
  Future<List<UserSummary>> getFriends() async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.get(Endpoints.friends),
      );

      if (res.statusCode == 200) {
        final List<dynamic> friends = res.data is List
            ? res.data
            : (res.data['results'] ?? []);
        return friends
            .whereType<Map>()
            .map(
              (friend) =>
                  UserSummary.fromJson(Map<String, dynamic>.from(friend)),
            )
            .toList();
      }
      return _throwApiError(res);
    } on DioException catch (e) {
      final res = e.response;
      if (res != null) return _throwApiError(res);
      rethrow;
    }
  }

  /// Get user profile by ID
  Future<UserSummary> getUserProfile(String userId) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.get(Endpoints.userProfile(userId)),
      );

      if (res.statusCode == 200) {
        return UserSummary.fromJson(Map<String, dynamic>.from(res.data));
      }
      return _throwApiError(res);
    } on DioException catch (e) {
      final res = e.response;
      if (res != null) return _throwApiError(res);
      rethrow;
    }
  }

  /// Get friendship status with a user
  Future<String?> getFriendshipStatus(String userId) async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.get(Endpoints.userFriendshipStatus(userId)),
      );

      if (res.statusCode == 200) {
        return res.data['status']?.toString();
      }
      return null;
    } on DioException catch (_) {
      return null; // No friendship exists
    }
  }
}
