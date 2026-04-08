import 'package:dio/dio.dart';
import 'package:planpal_flutter/core/auth/auth_session.dart';
import 'package:planpal_flutter/core/dtos/analytics_model.dart';
import 'package:planpal_flutter/core/services/api_error.dart';
import 'package:planpal_flutter/core/services/apis.dart';


class AnalyticsRepository {
  final AuthProvider _auth;

  AnalyticsRepository(this._auth);

  Future<AnalyticsSummary> getDashboardSummary({String range = '30d'}) async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (client) => client.dio.get(
          Endpoints.analyticsSummary,
          queryParameters: {'range': range},
        ),
      );
      if (res.statusCode == 200 && res.data is Map) {
        return AnalyticsSummary.fromJson(Map<String, dynamic>.from(res.data as Map));
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  Future<AnalyticsTimeSeries> getTimeSeries({
    required String metric,
    String range = '30d',
  }) async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (client) => client.dio.get(
          Endpoints.analyticsTimeseries,
          queryParameters: {
            'metric': metric,
            'range': range,
          },
        ),
      );
      if (res.statusCode == 200 && res.data is Map) {
        return AnalyticsTimeSeries.fromJson(Map<String, dynamic>.from(res.data as Map));
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }

  Future<AnalyticsTopEntities> getTopEntities({
    String range = '30d',
    int limit = 5,
  }) async {
    try {
      final Response res = await _auth.requestWithAutoRefresh(
        (client) => client.dio.get(
          Endpoints.analyticsTop,
          queryParameters: {
            'range': range,
            'limit': limit,
          },
        ),
      );
      if (res.statusCode == 200 && res.data is Map) {
        return AnalyticsTopEntities.fromJson(Map<String, dynamic>.from(res.data as Map));
      }
      throw buildApiException(res);
    } on DioException catch (e) {
      if (e.response != null) throw buildApiException(e.response!);
      rethrow;
    }
  }
}
