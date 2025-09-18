import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:planpal_flutter/core/providers/auth_provider.dart';
import 'package:planpal_flutter/core/services/apis.dart';

class LocationRepository {
  final AuthProvider _authProvider;
  late final Dio _dio;

  LocationRepository(this._authProvider) {
    _dio = Dio();
  }

  /// Reverse geocode coordinates to get address using backend Goong service
  Future<Map<String, dynamic>?> reverseGeocode(
    double latitude,
    double longitude,
  ) async {
    try {
      final response = await _dio.post(
        '$baseUrl${Endpoints.locationReverseGeocode}',
        data: {'latitude': latitude, 'longitude': longitude},
        options: Options(
          headers: {
            'Authorization': 'Bearer ${_authProvider.token}',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        return response.data;
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
      final response = await _dio.get(
        '$baseUrl${Endpoints.locationSearch}',
        queryParameters: {'q': query},
        options: Options(
          headers: {'Authorization': 'Bearer ${_authProvider.token}'},
        ),
      );

      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data['results'] ?? []);
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
      final response = await _dio.get(
        '$baseUrl${Endpoints.locationAutocomplete}',
        queryParameters: {'input': input},
        options: Options(
          headers: {'Authorization': 'Bearer ${_authProvider.token}'},
        ),
      );

      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(
          response.data['predictions'] ?? [],
        );
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Get place details by place_id
  Future<Map<String, dynamic>?> getPlaceDetails(String placeId) async {
    try {
      final response = await _dio.get(
        '$baseUrl${Endpoints.locationPlaceDetails}',
        queryParameters: {'place_id': placeId},
        options: Options(
          headers: {'Authorization': 'Bearer ${_authProvider.token}'},
        ),
      );

      if (response.statusCode == 200) {
        return response.data;
      }
      return null;
    } catch (e) {
      debugPrint('Error getting place details: $e');
      return null;
    }
  }
}
