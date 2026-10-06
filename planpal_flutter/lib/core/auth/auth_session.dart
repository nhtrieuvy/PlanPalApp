import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../services/apis.dart';
import '../services/api_error.dart';
import '../services/firebase_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import '../dtos/user_model.dart';
import '../repositories/user_repository.dart';
import 'package:planpal_flutter/config/app_config.dart';
import 'package:planpal_flutter/core/storage/offline_storage.dart';

// Central auth/session service used by repositories and Riverpod providers.
class AuthProvider extends ChangeNotifier {
  AuthProvider({OfflineStorage? offlineStorage})
    : _offlineStorage = offlineStorage;

  static const String _kAccessTokenKey = 'access_token';
  static const String _kRefreshTokenKey = 'refresh_token';
  static const String _kCachedUserKey = 'cached_user';

  // Chỗ lưu bảo mật của thư viện flutter_secure_storage
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final OfflineStorage? _offlineStorage;

  UserModel? _user; // cached User model
  String? _token;
  String? _refreshToken; // OAuth2 refresh token
  UserModel? get user => _user;
  String? get token => _token; // Getter để lấy token
  String? get refreshToken => _refreshToken;
  bool get isLoggedIn => _user != null && _token != null;

  // Dùng để tránh nhiều refresh token chạy song song
  Completer<bool>? _refreshCompleter;

  // Getter để lấy CLIENT_ID từ AppConfig (gọi khi cần, không cache)
  String get _clientId => AppConfig.getClientId();

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
          // Set synchronously so UI can show immediately; repo will refresh later.
          _user = cachedUser;
        }
      } catch (_) {
        // ignore cache restore failures
      }

      // Refresh the cached profile when a stored token is available. A
      // temporary network failure must not sign a returning web user out.
      if (_token != null) {
        try {
          final userRepo = UserRepository(this);
          await userRepo
              .getProfile(); // This calls setUser() and updates cache.
          await markOnline();
        } catch (e) {
          if (_isUnauthorized(e)) {
            await _clearSession();
          } else {
            // Keep the encrypted token and cached profile so the app remains
            // usable while Fly/API connectivity recovers.
            debugPrint(
              'Session profile refresh failed; keeping cached session',
            );
            notifyListeners();
          }
        }
      }
    } catch (e) {
      // Nếu có lỗi khi khôi phục, đảm bảo trạng thái sạch
      await _clearSession();
    }
  }

  bool _isUnauthorized(Object error) {
    if (error is ApiException) return error.statusCode == 401;
    if (error is DioException) return error.response?.statusCode == 401;
    return false;
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
    if (_user == userData) return;
    _user = userData;
    notifyListeners();
    // Persist cached user asynchronously (don't block callers).
    SharedPreferences.getInstance().then((prefs) {
      try {
        prefs.setString(_kCachedUserKey, jsonEncode(userData.toJson()));
      } catch (_) {
        // ignore
      }
    });
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
        _refreshCompleter!.complete(true);
        return true;
      }
      _refreshCompleter!.complete(false);
      return false;
    } on DioException catch (e) {
      if (e.response != null) {
        debugPrint(
          'Refresh token failed with status ${e.response!.statusCode}',
        );
      } else {
        debugPrint('Refresh token network error: ${e.type}');
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
          await markOnline();

          await _initializeFirebaseAfterLogin();
        } catch (_) {
          debugPrint('Login profile fetch failed');
        }
      } else {
        throw buildApiException(response);
      }
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  Future<void> logout() async {
    final userId = _user?.id;
    try {
      if (_token != null) {
        final apiClient = ApiClient(token: _token);
        await apiClient.dio.post(Endpoints.logout);
      }
    } catch (e) {
      debugPrint('Logout API error');
    } finally {
      if (userId != null) {
        try {
          await _offlineStorage?.removeWhere(
            (key) => isOfflineStorageKeyForUser(key, userId),
          );
        } catch (_) {
          debugPrint('AuthProvider: failed to clear offline user data');
        }
      }
      await _clearSession();
      FirebaseService.instance.reset();
    }
  }

  Future<void> markOnline() => _setOnlineStatus(true);

  Future<void> markOffline() => _setOnlineStatus(false);

  Future<void> _setOnlineStatus(bool isOnline) async {
    if (_token == null || _user == null) return;

    try {
      final repo = UserRepository(this);
      await repo.setOnlineStatus(isOnline);
    } catch (e) {
      debugPrint('AuthProvider: failed to set online=$isOnline');
    }
  }

  Future<void> _initializeFirebaseAfterLogin() async {
    if (_token == null) return;

    try {
      final registered = kIsWeb
          ? await FirebaseService.instance.initialize()
          : await FirebaseService.instance.registerToken(_token!);
      if (!registered) {
        final error = FirebaseService.instance.lastInitializationError;
        if (error != null && error.isNotEmpty) {
          debugPrint('AuthProvider: Firebase unavailable: $error');
        }
      }
    } catch (e) {
      debugPrint('AuthProvider: Firebase initialization error: $e');
    }
  }
}
