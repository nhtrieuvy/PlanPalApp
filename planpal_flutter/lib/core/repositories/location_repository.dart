import 'package:dio/dio.dart';

import 'package:planpal_flutter/core/auth/auth_session.dart';
import 'package:planpal_flutter/core/services/apis.dart';

class LocationRepository {
  const LocationRepository(this._authProvider);

  static const String _defaultLocationName = 'Vị trí đã chọn';

  final AuthProvider _authProvider;

  Future<Map<String, dynamic>?> reverseGeocode(
    double latitude,
    double longitude,
  ) async {
    try {
      final Response<dynamic> response = await _authProvider.requestWithAutoRefresh(
        (client) => client.dio.post(
          Endpoints.locationReverseGeocode,
          data: {'latitude': latitude, 'longitude': longitude},
        ),
      );

      if (response.statusCode != 200 || response.data is! Map<String, dynamic>) {
        return _fallbackLocation(latitude, longitude);
      }

      final data = Map<String, dynamic>.from(response.data as Map<String, dynamic>);
      data['formatted_address'] ??= _formatCoordinates(latitude, longitude);
      data['location_name'] ??= data['formatted_address'] ?? _defaultLocationName;
      return data;
    } catch (_) {
      return _fallbackLocation(latitude, longitude);
    }
  }

  Future<List<Map<String, dynamic>>> searchPlaces(String query) async {
    try {
      final Response<dynamic> response = await _authProvider.requestWithAutoRefresh(
        (client) => client.dio.get(
          Endpoints.locationSearch,
          queryParameters: {'q': query},
        ),
      );

      if (response.statusCode != 200) {
        return const [];
      }

      return List<Map<String, dynamic>>.from(response.data['results'] ?? const []);
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> getAutocompleteSuggestions(
    String input,
  ) async {
    try {
      final Response<dynamic> response = await _authProvider.requestWithAutoRefresh(
        (client) => client.dio.get(
          Endpoints.locationAutocomplete,
          queryParameters: {'input': input},
        ),
      );

      if (response.statusCode != 200) {
        return const [];
      }

      return List<Map<String, dynamic>>.from(
        response.data['predictions'] ?? const [],
      );
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, dynamic>?> getPlaceDetails(String placeId) async {
    try {
      final Response<dynamic> response = await _authProvider.requestWithAutoRefresh(
        (client) => client.dio.get(
          Endpoints.locationPlaceDetails,
          queryParameters: {'place_id': placeId},
        ),
      );

      if (response.statusCode != 200 || response.data is! Map<String, dynamic>) {
        return null;
      }

      return Map<String, dynamic>.from(response.data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _fallbackLocation(double latitude, double longitude) {
    final formattedAddress = _formatCoordinates(latitude, longitude);
    return {
      'formatted_address': formattedAddress,
      'location_name': _defaultLocationName,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  String _formatCoordinates(double latitude, double longitude) =>
      '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
}
