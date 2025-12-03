import 'package:dio/dio.dart';

// Production backend on Fly.io
const String baseUrl = 'https://planpal-backend.fly.dev';
// Local development: 'http://10.0.2.2:8000'

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
  static const String groupJoin = '/groups/join/';
  static const String activities = '/activities/';

  // Plan-related endpoints
  static const String joinedPlans = '/plans/joined/';
  static const String publicPlans = '/plans/public/';

  // Dynamic endpoints
  static String planDetails(String planId) => '/plans/$planId/';
  static String planActivitiesByDate(String planId, String date) =>
      '/plans/$planId/activities_by_date/?date=$date';
  static String planSchedule(String planId) => '/plans/$planId/schedule/';
  static String planJoin(String planId) => '/plans/$planId/join/';

  static String groupDetails(String groupId) => '/groups/$groupId/';
  static String groupPlans(String groupId) => '/groups/$groupId/plans/';
  static String groupAddMember(String groupId) =>
      '/groups/$groupId/add_member/';
  static String groupLeave(String groupId) => '/groups/$groupId/leave/';
  static String groupRemoveMember(String groupId) =>
      '/groups/$groupId/remove_member/';

  static String activityDetails(String activityId) =>
      '/activities/$activityId/';
  static String activityDetail(String activityId) => '/activities/$activityId/';
  static String activityToggleCompletion(String planId, String activityId) =>
      '/plans/$planId/activities/$activityId/complete/';

  // Friendship endpoints
  static const String friendRequest = '/friends/request/';
  static const String friendRequests = '/friends/requests/';
  static const String friends = '/friends/';
  static String friendRequestAction(String requestId) =>
      '/friends/requests/$requestId/action/';

  // User profile endpoints
  static String userProfile(String userId) => '/users/$userId/';
  static String userFriendshipStatus(String userId) =>
      '/users/$userId/friendship_status/';
  static String userUnfriend(String userId) => '/users/$userId/unfriend/';
  static String userBlock(String userId) => '/users/$userId/block/';
  static String userUnblock(String userId) => '/users/$userId/unblock/';
  // Device token registration
  static const String registerDeviceToken = '/users/register_device_token/';

  // Location endpoints
  static const String locationReverseGeocode = '/location/reverse-geocode/';
  static const String locationSearch = '/location/search/';
  static const String locationAutocomplete = '/location/autocomplete/';
  static const String locationPlaceDetails = '/location/place-details/';

  // Chat endpoints
  static const String conversations = '/conversations/';
  static const String createDirectConversation =
      '/conversations/create_direct/';
  static String conversationDetails(String conversationId) =>
      '/conversations/$conversationId/';
  static String conversationMessages(String conversationId) =>
      '/conversations/$conversationId/messages/';
  static String sendMessage(String conversationId) =>
      '/conversations/$conversationId/send_message/';
  static String markRead(String conversationId) =>
      '/conversations/$conversationId/mark_read/';
}

class ApiClient {
  final String? token;
  late final Dio _dio;

  ApiClient({this.token}) {
    BaseOptions options = BaseOptions(
      baseUrl: baseUrl,
      headers: {if (token != null) 'Authorization': 'Bearer $token'},
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 15),
    );
    _dio = Dio(options);
  }

  Dio get dio => _dio;
}
