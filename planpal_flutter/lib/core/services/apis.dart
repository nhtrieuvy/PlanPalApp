import 'package:dio/dio.dart';

const String baseUrl = 'http://10.0.2.2:8000';

class Endpoints {
  // OAuth2 endpoints
  static const String token = '/o/token/';
  static const String logout = '/auth/logout/';

  // User endpoints
  static const String register = '/users/';
  static const String users = '/users';
  static const String profile = '/users/profile/';
  static const String updateProfile = '/users/update_profile/';
  static const String searchUsers = '/users/search/';

  // Core API endpoints
  static const String plans = '/plans/';
  static const String groups = '/groups/';

  // Dynamic endpoints
  static String planDetails(String planId) => '/plans/$planId/';
  static String groupDetails(String groupId) => '/groups/$groupId/';

  // Friendship endpoints
  static const String friendRequest = '/friends/request/';
  static const String friendRequests = '/friends/requests/';
  static const String friends = '/friends/';
  static String friendRequestAction(String requestId) =>
      '/friends/requests/$requestId/action/';

  // User profile endpoints
  static String userProfile(String userId) => '/users/$userId/';
  static String userFriendshipStatus(String userId) =>
      '/users/$userId/friendship-status/';
}

class ApiClient {
  final String? token;
  late final Dio _dio;

  ApiClient({this.token}) {
    BaseOptions options = BaseOptions(
      baseUrl: baseUrl,
      headers: {if (token != null) 'Authorization': 'Bearer $token'},
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    );
    _dio = Dio(options);
  }

  Dio get dio => _dio;
}
