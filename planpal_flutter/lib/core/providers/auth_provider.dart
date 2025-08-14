import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../services/apis.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:async';
import '../models/user.dart';
import '../repositories/user_repository.dart';

// ChangeNotifier cho phép lắng nghe khi dữ liệu thay đổi
class AuthProvider extends ChangeNotifier {
  // Secure storage keys
  static const String _kAccessTokenKey = 'access_token';
  static const String _kRefreshTokenKey = 'refresh_token';

  // Secure token storage
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  User? _user; // cached User model
  String? _token;
  String? _refreshToken; // OAuth2 refresh token
  User? get user => _user;
  String? get token => _token; // Getter để lấy token
  String? get refreshToken => _refreshToken;
  bool get isLoggedIn => _user != null && _token != null;

  // Hàm refresh token
  // Đọc client_id và client_secret từ biến môi trường Flutter (hoặc file cấu hình)
  final String _clientId = dotenv.env['CLIENT_ID'] ?? '';

  // Dùng để tránh nhiều refresh token chạy song song
  Completer<bool>? _refreshCompleter;

  // Khởi tạo provider, khôi phục token nếu có và fetch profile
  Future<void> init() async {
    try {
      _token = await _secureStorage.read(key: _kAccessTokenKey);
      _refreshToken = await _secureStorage.read(key: _kRefreshTokenKey);
      // Don't auto-fetch profile here; repositories handle profile requests
      // Keep tokens restored for requestWithAutoRefresh to work
    } catch (e) {
      // Nếu có lỗi khi khôi phục, đảm bảo trạng thái sạch
      await _clearSession();
    }
  }

  Future<void> _saveTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    _token = accessToken;
    if (refreshToken != null) {
      _refreshToken = refreshToken;
    }
    await _secureStorage.write(key: _kAccessTokenKey, value: _token);
    if (_refreshToken != null) {
      await _secureStorage.write(key: _kRefreshTokenKey, value: _refreshToken);
    }
  }

  Future<void> _clearTokens() async {
    _token = null;
    _refreshToken = null;
    await _secureStorage.delete(key: _kAccessTokenKey);
    await _secureStorage.delete(key: _kRefreshTokenKey);
  }

  Future<void> _clearSession() async {
    _user = null;
    await _clearTokens();
    notifyListeners();
  }

  // Public setter so callers (repositories or pages) can update cached user
  // with a typed User model and notify listeners.
  void setUser(User userData) {
    if (_user == userData) return; // avoid unnecessary rebuilds
    _user = userData;
    notifyListeners();
  }

  Future<bool> refreshAccessToken() async {
    if (_refreshToken == null) return false;

    // Nếu đã có refresh đang diễn ra, chờ kết quả
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    _refreshCompleter = Completer<bool>();
    try {
      final apiClient = ApiClient();

      final refreshForm = {
        'grant_type': 'refresh_token',
        'refresh_token': _refreshToken,
        'client_id': _clientId,
      };

      final response = await apiClient.dio.post(
        Endpoints.token,
        data: refreshForm,
      );
      if (response.statusCode == 200 && response.data['access_token'] != null) {
        await _saveTokens(
          accessToken: response.data['access_token'] as String,
          refreshToken: response.data['refresh_token'] as String?,
        );
        notifyListeners();
        _refreshCompleter!.complete(true);
        return true;
      }
      _refreshCompleter!.complete(false);
      return false;
    } on DioException catch (e) {
      if (e.response != null) {
        debugPrint('Refresh token error: ${e.response!.data}');
      } else {
        debugPrint('Refresh token network error: $e');
      }
      _refreshCompleter!.complete(false);
      return false;
    } catch (e) {
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
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
        } else {
          // Refresh thất bại => clear session để tránh trạng thái treo
          await _clearSession();
        }
      }
      rethrow;
    }
  }

  // Login chuẩn OAuth2 password grant
  Future<void> login({
    required String username,
    required String password,
  }) async {
    try {
      final apiClient = ApiClient();

      final form = {
        'grant_type': 'password',
        'username': username.trim(),
        'password': password.trim(),
        'client_id': _clientId,
      };

      final response = await apiClient.dio.post(Endpoints.token, data: form);

      if (response.statusCode == 200 && response.data['access_token'] != null) {
        await _saveTokens(
          accessToken: response.data['access_token'] as String,
          refreshToken: response.data['refresh_token'] as String?,
        );
        // Fetch profile immediately (safe fail)
        try {
          final repo = UserRepository(this);
          // Use repository for auto refresh logic path
          final profile = await repo.getProfile();
          setUser(profile);
        } catch (e) {
          debugPrint('Login profile fetch failed: $e');
        }
      } else {
        throw Exception('Đăng nhập thất bại.');
      }
    } on DioException catch (e) {
      final res = e.response;
      if (res != null) {
        debugPrint('Login error data: ${res.data}');

        if (res.data is Map) {
          final errorType = res.data['error'];
          final errorDesc = res.data['error_description'];

          if (errorType == 'invalid_grant') {
            throw Exception('Sai tên đăng nhập hoặc mật khẩu.');
          } else if (errorType == 'invalid_client') {
            throw Exception(
              'Client OAuth2 không hợp lệ. Kiểm tra cấu hình ứng dụng.',
            );
          } else if (errorType == 'unsupported_grant_type') {
            throw Exception('Phương thức đăng nhập không được hỗ trợ.');
          } else if (errorDesc != null) {
            throw Exception(errorDesc.toString());
          }
        }
      }
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.unknown) {
        throw Exception('Không có kết nối mạng.');
      }
      throw Exception('Đăng nhập thất bại. Vui lòng thử lại.');
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
      await _clearSession();
    }
  }
}
