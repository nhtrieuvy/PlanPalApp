import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'dart:io';
import '../services/apis.dart';

// ChangeNotifier cho phép lắng nghe khi dữ liệu thay đổi
class AuthProvider extends ChangeNotifier {
  Map<String, dynamic>?
  _user; // dữ liệu user thường trả về từ API là JSON nên dùng Map
  String? _token;
  Map<String, dynamic>? get user => _user;
  String? get token => _token; // Getter để lấy token
  bool get isLoggedIn => _user != null;

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
}
