import 'package:dio/dio.dart';

const String baseUrl = 'http://10.0.2.2:8000';

class Endpoints {
  static const String login = '/auth/login/';
  static const String logout = '/auth/logout/';
  static const String register = '/users/';
  static const String currentUser = '/users/current-user/';
  static const String plans = '/plans/';
  static const String groups = '/groups/';
  static String planDetails(int planId) => '/plans/$planId/';
  static String groupDetails(int groupId) => '/groups/$groupId/';
}

class ApiClient {
  final String? token;
  late final Dio _dio;

  ApiClient({this.token}) {
    BaseOptions options = BaseOptions(
      baseUrl: baseUrl,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    );
    _dio = Dio(options);
  }

  Dio get dio => _dio;
}
