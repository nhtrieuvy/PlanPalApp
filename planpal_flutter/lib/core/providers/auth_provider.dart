import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../services/apis.dart';
import '../services/firebase_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import '../dtos/user_model.dart';
import '../repositories/user_repository.dart';

// ChangeNotifier cho phép lắng nghe khi dữ liệu thay đổi
class AuthProvider extends ChangeNotifier {
  static const String _kAccessTokenKey = 'access_token';
  static const String _kRefreshTokenKey = 'refresh_token';
  static const String _kCachedUserKey = 'cached_user';

  // Chỗ lưu bảo mật của thư viện flutter_secure_storage
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  UserModel? _user; // cached User model
  String? _token;
  String? _refreshToken; // OAuth2 refresh token
  UserModel? get user => _user;
  String? get token => _token; // Getter để lấy token
  String? get refreshToken => _refreshToken;
  bool get isLoggedIn => _user != null && _token != null;

  final String _clientId = dotenv.env['CLIENT_ID'] ?? '';

  // Dùng để tránh nhiều refresh token chạy song song
  Completer<bool>? _refreshCompleter;

  // Khởi tạo provider, khôi phục token nếu có và fetch profile
  Future<void> init() async {
    try {
      _token = await _secureStorage.read(key: _kAccessTokenKey);
      _refreshToken = await _secureStorage.read(key: _kRefreshTokenKey);

      // Try to restore cached user from SharedPreferences so UI can show immediately
      try {
        final prefs = await SharedPreferences.getInstance();
        final cached = prefs.getString(_kCachedUserKey);
        if (cached != null && cached.isNotEmpty) {
          final Map<String, dynamic> map = Map<String, dynamic>.from(
            jsonDecode(cached) as Map,
          );
          final cachedUser = UserModel.fromJson(map);
          // Set synchronously so UI can show immediately; repo will refresh later
          _user = cachedUser;
          notifyListeners();
        }
      } catch (_) {
        // ignore cache restore failures
      }

      // Nếu có token, fetch user profile
      if (_token != null) {
        try {
          final userRepo = UserRepository(this);
          await userRepo
              .getProfile(); // This will call setUser() and update cache
        } catch (e) {
          // Nếu token hết hạn hoặc không hợp lệ, clear session
          await _clearSession();
        }
      }
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
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kCachedUserKey);
    } catch (_) {}
    await _clearTokens();
    notifyListeners();
  }

  void setUser(UserModel userData) {
    if (_user == userData) return; // Tránh rebuild không cần thiết
    _user = userData;
    // Persist cached user asynchronously (don't block callers)
    SharedPreferences.getInstance().then((prefs) {
      try {
        prefs.setString(_kCachedUserKey, jsonEncode(userData.toJson()));
      } catch (_) {
        // ignore
      }
    });
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
        try {
          final repo = UserRepository(this);
          final profile = await repo.getProfile();
          setUser(profile);

          await _initializeFirebaseAfterLogin();
        } catch (e) {
          debugPrint('Login profile fetch failed: $e');
        }
      } else {
        throw Exception('Đăng nhập thất bại.');
      }
    } on DioException catch (e) {
      final res = e.response;
      if (res != null) {

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

  Future<void> logout() async {
    try {
      if (_token != null) {
        final apiClient = ApiClient(token: _token);
        await apiClient.dio.post(Endpoints.logout);
      }
    } catch (e) {
      debugPrint('Logout API error: $e');
    } finally {
      await _clearSession();
      FirebaseService.instance.reset();
    }
  }

  Future<void> _initializeFirebaseAfterLogin() async {
    if (_token == null) return;

    try {
      await FirebaseService.instance.initialize();

      await FirebaseService.instance.registerToken(_token!);
    } catch (e) {
      debugPrint('AuthProvider: Firebase initialization error: $e');
    }
  }
}
