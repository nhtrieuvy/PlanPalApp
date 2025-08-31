import 'dart:io';
import 'package:dio/dio.dart';
import 'package:planpal_flutter/core/providers/auth_provider.dart';
import '../services/apis.dart';
import '../dtos/user.dart';
import '../services/api_error.dart';

class UserRepository {
  final AuthProvider auth;
  UserRepository(this.auth);

  Never _throwApiError(Response res) => throw buildApiException(res);

  Future<User> getProfile() async {
    try {
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.get(Endpoints.profile),
      );
      if (res.statusCode == 200 && res.data is Map) {
        final user = User.fromJson(Map<String, dynamic>.from(res.data as Map));
        auth.setUser(user);
        return user;
      }
      return _throwApiError(res);
    } on DioException catch (e) {
      final res = e.response;
      if (res != null) return _throwApiError(res);
      rethrow;
    }
  }

  Future<User> updateProfile({
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
      final Response res = await auth.requestWithAutoRefresh(
        (c) => c.dio.patch(Endpoints.updateProfile, data: formData),
      );
      if (res.statusCode == 200 && res.data is Map) {
        final updatedUser = User.fromJson(
          Map<String, dynamic>.from(res.data as Map),
        );
        auth.setUser(updatedUser); // Update cached user in auth provider
        return updatedUser;
      }
      return _throwApiError(res);
    } on DioException catch (e) {
      final res = e.response;
      if (res != null) return _throwApiError(res);
      rethrow;
    }
  }

  // Register remains public (no auth required)
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
    final apiClient = ApiClient();
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
    if (response.statusCode == 201) return;

    if (response.data is Map<String, dynamic>) {
      final errorData = response.data as Map<String, dynamic>;
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

    throw Exception('Đăng ký thất bại');
  }
}
