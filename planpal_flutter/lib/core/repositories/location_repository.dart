import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:planpal_flutter/core/providers/auth_provider.dart';
import 'package:planpal_flutter/core/services/apis.dart';

class LocationRepository {
  final AuthProvider _authProvider;

  LocationRepository(this._authProvider);

  /// Reverse geocode coordinates to get address using backend Goong service
  Future<Map<String, dynamic>?> reverseGeocode(
    double latitude,
    double longitude,
  ) async {
    try {
      final Response res = await _authProvider.requestWithAutoRefresh(
        (c) => c.dio.post(
          Endpoints.locationReverseGeocode,
          data: {'latitude': latitude, 'longitude': longitude},
        ),
      );

      if (res.statusCode == 200) {
        return res.data as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      // If backend service fails, return basic coordinate-based address
      return {
        'formatted_address':
            '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
        'location_name': 'Vị trí đã chọn',
      };
    }
  }

  /// Search for places using backend Goong service
  Future<List<Map<String, dynamic>>> searchPlaces(String query) async {
    try {
      final Response res = await _authProvider.requestWithAutoRefresh(
        (c) =>
            c.dio.get(Endpoints.locationSearch, queryParameters: {'q': query}),
      );

      if (res.statusCode == 200) {
        return List<Map<String, dynamic>>.from(res.data['results'] ?? []);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Get place autocomplete suggestions
  Future<List<Map<String, dynamic>>> getAutocompleteSuggestions(
    String input,
  ) async {
    try {
      final Response res = await _authProvider.requestWithAutoRefresh(
        (c) => c.dio.get(
          Endpoints.locationAutocomplete,
          queryParameters: {'input': input},
        ),
      );

      if (res.statusCode == 200) {
        return List<Map<String, dynamic>>.from(res.data['predictions'] ?? []);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Get place details by place_id
  Future<Map<String, dynamic>?> getPlaceDetails(String placeId) async {
    try {
      final Response res = await _authProvider.requestWithAutoRefresh(
        (c) => c.dio.get(
          Endpoints.locationPlaceDetails,
          queryParameters: {'place_id': placeId},
        ),
      );

      if (res.statusCode == 200) {
        return res.data as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
