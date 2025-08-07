import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'dart:io';
import '../services/apis.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// ChangeNotifier cho phép lắng nghe khi dữ liệu thay đổi
class AuthProvider extends ChangeNotifier {
  Map<String, dynamic>?
  _user; // dữ liệu user thường trả về từ API là JSON nên dùng Map
  String? _token;
  String? _refreshToken; // OAuth2 refresh token
  Map<String, dynamic>? get user => _user;
  String? get token => _token; // Getter để lấy token
  String? get refreshToken => _refreshToken;
  bool get isLoggedIn => _user != null;

  // Hàm refresh token
  // Đọc client_id và client_secret từ biến môi trường Flutter (hoặc file cấu hình)
  final String _clientId = dotenv.env['CLIENT_ID'] ?? '';
  final String _clientSecret = dotenv.env['CLIENT_SECRET'] ?? '';

  Future<bool> refreshAccessToken() async {
    if (_refreshToken == null) return false;
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        ),
      );
      final response = await dio.post(
        '/o/token/',
        data: {
          'grant_type': 'refresh_token',
          'refresh_token': _refreshToken,
          'client_id': _clientId,
          'client_secret': _clientSecret,
        },
      );
      if (response.statusCode == 200 && response.data['access_token'] != null) {
        _token = response.data['access_token'];
        if (response.data['refresh_token'] != null) {
          _refreshToken = response.data['refresh_token'];
        }
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // Hàm gọi API có tự động refresh token nếu gặp 401
  Future<Response<T>> requestWithAutoRefresh<T>(
    Future<Response<T>> Function(ApiClient client) requestFn,
  ) async {
    ApiClient client = ApiClient(token: _token);
    try {
      return await requestFn(client);
    } on DioException catch (e) {
      // Nếu gặp lỗi 401, thử refresh token
      if (e.response?.statusCode == 401 && _refreshToken != null) {
        final refreshed = await refreshAccessToken();
        if (refreshed) {
          // Gọi lại request với token mới
          client = ApiClient(token: _token);
          return await requestFn(client);
        }
      }
      rethrow;
    }
  }

  // void setUser(Map<String, dynamic> userData) {
  //   _user = userData;
  //   notifyListeners(); // thông báo cho các widget lắng nghe rằng dữ liệu đã thay đổi
  // }

  // Login với API
  Future<void> login({
    required String username,
    required String password,
  }) async {
    try {
      final apiClient = ApiClient();
      final response = await apiClient.dio.post(
        Endpoints.login,
        data: {'username': username.trim(), 'password': password.trim()},
      );

      if (response.statusCode == 200 &&
          response.data != null &&
          response.data['user'] != null) {
        _user = response.data['user'];
        // OAuth2 token từ backend
        _token = response.data['access_token'];
        _refreshToken = response.data['refresh_token'];
        notifyListeners();
      } else {
        throw Exception(
          response.data['error'] ?? 'Đăng nhập thất bại. Vui lòng thử lại.',
        );
      }
    } on DioException catch (e) {
      String message = 'Đã xảy ra lỗi không xác định.';
      final res = e.response;
      if (res != null) {
        if (res.statusCode == 401 || res.statusCode == 400) {
          message = 'Sai tên đăng nhập hoặc mật khẩu.';
        } else {
          message = 'Đăng nhập thất bại. Vui lòng thử lại.';
        }
      } else if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.unknown) {
        message = 'Không có kết nối mạng.';
      } else {
        message = 'Lỗi kết nối máy chủ.';
      }
      throw Exception(message);
    } catch (e) {
      throw Exception('Đã xảy ra lỗi không xác định.');
    }
  }

  // Logout với API và xóa token
  Future<void> logout() async {
    try {
      // Gọi API logout với token hiện tại nếu có
      if (_token != null) {
        final apiClient = ApiClient(token: _token);
        await apiClient.dio.post(Endpoints.logout);
      }
    } catch (e) {
      // Không throw error nếu API logout lỗi, vẫn clear local data
      debugPrint('Logout API error: $e');
    } finally {
      // Luôn clear user và token local
      _user = null;
      _token = null;
      _refreshToken = null;
      notifyListeners();
    }
  }

  // Register
  Future<void> register({
    required String username,
    required String email,
    required String password,
    required String passwordConfirm,
    required String firstName,
    required String lastName,
    String? phoneNumber,
    File? avatar,
  }) async {
    try {
      final apiClient = ApiClient();

      // Tạo FormData để upload file
      FormData formData = FormData.fromMap({
        'username': username,
        'email': email,
        'password': password,
        'password_confirm': passwordConfirm,
        'first_name': firstName,
        'last_name': lastName,
        if (phoneNumber != null && phoneNumber.isNotEmpty)
          'phone_number': phoneNumber,
        if (avatar != null)
          'avatar': await MultipartFile.fromFile(
            avatar.path,
            filename: 'avatar.jpg',
          ),
      });

      final response = await apiClient.dio.post(
        Endpoints.register,
        data: formData,
      );

      if (response.statusCode == 201) {
        // Đăng ký thành công
        debugPrint('Đăng ký thành công: ${response.data}');
      } else {
        throw Exception('Đăng ký thất bại');
      }
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response!.data;
        if (errorData is Map<String, dynamic>) {
          // Lấy thông báo lỗi đầu tiên
          String errorMessage = 'Đăng ký thất bại';
          if (errorData.containsKey('username')) {
            errorMessage = errorData['username'][0];
          } else if (errorData.containsKey('email')) {
            errorMessage = errorData['email'][0];
          } else if (errorData.containsKey('password')) {
            errorMessage = errorData['password'][0];
          } else if (errorData.containsKey('non_field_errors')) {
            errorMessage = errorData['non_field_errors'][0];
          }
          throw Exception(errorMessage);
        }
      }
      throw Exception('Lỗi kết nối máy chủ');
    } catch (e) {
      throw Exception('Đăng ký thất bại: $e');
    }
  }

  // Fetch user profile from API (auto refresh token)
  Future<Map<String, dynamic>> fetchUserProfile() async {
    try {
      final response = await requestWithAutoRefresh(
        (client) => client.dio.get(Endpoints.profile),
      );
      if (response.statusCode == 200 && response.data != null) {
        _user = response.data;
        notifyListeners();
        return response.data;
      } else {
        throw Exception('Failed to fetch profile data');
      }
    } catch (e) {
      throw Exception('Không thể tải thông tin cá nhân: $e');
    }
  }

  // Update user profile (auto refresh token)
  Future<Map<String, dynamic>> updateUserProfile({
    String? firstName,
    String? lastName,
    String? email,
    String? phoneNumber,
    String? bio,
    File? avatar,
  }) async {
    try {
      FormData formData = FormData.fromMap({
        if (firstName != null) 'first_name': firstName,
        if (lastName != null) 'last_name': lastName,
        if (email != null) 'email': email,
        if (phoneNumber != null) 'phone_number': phoneNumber,
        if (bio != null) 'bio': bio,
        if (avatar != null)
          'avatar': await MultipartFile.fromFile(
            avatar.path,
            filename: 'avatar.jpg',
          ),
      });
      final response = await requestWithAutoRefresh(
        (client) => client.dio.patch(Endpoints.updateProfile, data: formData),
      );
      if (response.statusCode == 200 && response.data != null) {
        _user = response.data;
        notifyListeners();
        return response.data;
      } else {
        throw Exception('Failed to update profile');
      }
    } catch (e) {
      throw Exception('Không thể cập nhật thông tin: $e');
    }
  }
}
