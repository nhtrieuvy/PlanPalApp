import 'package:dio/dio.dart';
import 'package:planpal_flutter/core/auth/auth_session.dart';
import 'package:planpal_flutter/core/dtos/notification_model.dart';
import 'package:planpal_flutter/core/services/api_error.dart';
import 'package:planpal_flutter/core/services/apis.dart';

class NotificationRepository {
  final AuthProvider _auth;

  NotificationRepository(this._auth);

  Future<NotificationsResponse> getNotifications({
    NotificationFilter filters = const NotificationFilter(),
    String? nextPageUrl,
  }) async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (client) => client.getPaginated(
          Endpoints.notifications,
          pageUrl: nextPageUrl,
          queryParameters: nextPageUrl == null
              ? filters.toQueryParameters()
              : null,
        ),
      );

      if (res.statusCode == 200 && res.data is Map) {
        return NotificationsResponse.fromJson(
          Map<String, dynamic>.from(res.data as Map),
        );
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  Future<int> getUnreadCount() async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (client) => client.dio.get(Endpoints.notificationsUnreadCount),
      );

      if (res.statusCode == 200 && res.data is Map) {
        return (res.data as Map)['unread_count'] as int? ?? 0;
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  Future<void> markAsRead(String notificationId) async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (client) =>
            client.dio.patch(Endpoints.notificationRead(notificationId)),
      );
      if (res.statusCode != 200) {
        throw buildApiException(res);
      }
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  Future<int> markAllAsRead() async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (client) => client.dio.patch(Endpoints.notificationsReadAll),
      );
      if (res.statusCode == 200 && res.data is Map) {
        return (res.data as Map)['updated_count'] as int? ?? 0;
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }
}
