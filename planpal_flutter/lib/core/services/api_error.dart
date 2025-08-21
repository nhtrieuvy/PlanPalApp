import 'package:dio/dio.dart';

/// Centralized helper to extract a meaningful error message from a [Response].
/// Falls back to HTTP status code when no structured message is found.
Exception buildApiException(Response res) {
  final data = res.data;
  String? message;
  if (data is Map) {
    // Common DRF / OAuth2 fields
    for (final key in ['error', 'detail', 'message', 'non_field_errors']) {
      final v = data[key];
      if (v != null) {
        if (v is List && v.isNotEmpty) {
          message = v.first.toString();
          break;
        }
        message = v.toString();
        break;
      }
    }
    // As a last resort take the first value
    message ??= data.values.isNotEmpty ? data.values.first.toString() : null;
  } else if (data != null) {
    message = data.toString();
  }
  message ??= 'Yêu cầu thất bại (${res.statusCode})';
  return Exception(message);
}
