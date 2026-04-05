import 'package:dio/dio.dart';

const String baseUrl = String.fromEnvironment(
  'PLANPAL_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

String get baseWsUrl {
  final uri = Uri.parse(baseUrl);
  final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
  return uri.replace(scheme: wsScheme, path: '', query: '').toString();
}

class Endpoints {
  static const String _apiV1 = '/api/v1';

  static String _v1(String path) => '$_apiV1$path';

  // OAuth2 endpoints
  static const String token = '/o/token/';
  static String get logout => _v1('/auth/logout/');

  // User endpoints
  static String get register => _v1('/users/');
  static String get users => _v1('/users');
  static String get profile => _v1('/users/profile/');
  static String get updateProfile => _v1('/users/update_profile/');
  static String get searchUsers => _v1('/users/search/');

  // Core API endpoints
  static String get plans => _v1('/plans/');
  static String get groups => _v1('/groups/');
  static String get activities => _v1('/activities/');
  static String get auditLogs => _v1('/audit-logs/');

  // Plan-related endpoints
  static String get joinedPlans => _v1('/plans/joined/');
  static String get publicPlans => _v1('/plans/public/');

  // Dynamic endpoints
  static String planDetails(String planId) => _v1('/plans/$planId/');
  static String planActivitiesByDate(String planId, String date) =>
      _v1('/plans/$planId/activities_by_date/?date=$date');
  static String planSchedule(String planId) => _v1('/plans/$planId/schedule/');
  static String planJoin(String planId) => _v1('/plans/$planId/join/');

  static String groupDetails(String groupId) => _v1('/groups/$groupId/');
  static String groupJoin(String groupId) => _v1('/groups/$groupId/join/');
  static String groupPlans(String groupId) => _v1('/groups/$groupId/plans/');
  static String groupAddMember(String groupId) =>
      _v1('/groups/$groupId/add_member/');
  static String groupLeave(String groupId) => _v1('/groups/$groupId/leave/');
  static String groupRemoveMember(String groupId) =>
      _v1('/groups/$groupId/remove_member/');
  static String resourceAuditLogs(String resourceType, String resourceId) =>
      _v1('/audit-logs/resource/$resourceType/$resourceId/');

  static String activityDetails(String activityId) =>
      _v1('/activities/$activityId/');
  static String activityDetail(String activityId) =>
      _v1('/activities/$activityId/');
  static String activityToggleCompletion(String planId, String activityId) =>
      _v1('/plans/$planId/activities/$activityId/complete/');

  // Friendship endpoints
  static String get friendRequest => _v1('/friends/request/');
  static String get friendRequests => _v1('/friends/requests/');
  static String get friends => _v1('/friends/');
  static String friendRequestAction(String requestId) =>
      _v1('/friends/requests/$requestId/action/');

  // User profile endpoints
  static String userProfile(String userId) => _v1('/users/$userId/');
  static String userFriendshipStatus(String userId) =>
      _v1('/users/$userId/friendship_status/');
  static String userUnfriend(String userId) => _v1('/users/$userId/unfriend/');
  static String userBlock(String userId) => _v1('/users/$userId/block/');
  static String userUnblock(String userId) => _v1('/users/$userId/unblock/');
  // Device token registration
  static String get registerDeviceToken => _v1('/users/register_device_token/');

  // Location endpoints
  static String get locationReverseGeocode => _v1('/location/reverse-geocode/');
  static String get locationSearch => _v1('/location/search/');
  static String get locationAutocomplete => _v1('/location/autocomplete/');
  static String get locationPlaceDetails => _v1('/location/place-details/');

  // Chat endpoints
  static String get conversations => _v1('/conversations/');
  static String get createDirectConversation =>
      _v1('/conversations/create_direct/');
  static String conversationDetails(String conversationId) =>
      _v1('/conversations/$conversationId/');
  static String conversationMessages(String conversationId) =>
      _v1('/conversations/$conversationId/messages/');
  static String sendMessage(String conversationId) =>
      _v1('/conversations/$conversationId/send_message/');
  static String markRead(String conversationId) =>
      _v1('/conversations/$conversationId/mark_read/');
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

  /// Fetch paginated resources either from an endpoint path or an absolute
  /// `next` URL returned by Django REST pagination.
  Future<Response<dynamic>> getPaginated(
    String endpoint, {
    String? pageUrl,
    Map<String, dynamic>? queryParameters,
  }) {
    if (pageUrl != null && pageUrl.isNotEmpty) {
      return _dio.getUri(Uri.parse(pageUrl));
    }
    return _dio.get(endpoint, queryParameters: queryParameters);
  }
}
