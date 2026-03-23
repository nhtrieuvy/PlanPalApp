import 'package:dio/dio.dart';

/// Centralized helper to extract a meaningful error message from a [Response].
/// Falls back to HTTP status code when no structured message is found.
Exception buildApiException(Response res) {
  final data = res.data;
  String? message;
  if (data is Map) {
    // New frozen error contract keys first.
    final directMessage = data['message'];
    if (directMessage is String && directMessage.isNotEmpty) {
      message = directMessage;
    }

    final details = data['details'];
    if (message == null && details is Map) {
      final nonField = details['non_field_errors'];
      if (nonField is List && nonField.isNotEmpty) {
        message = nonField.first.toString();
      }
    }

    // Common DRF / OAuth2 legacy fields
    for (final key in ['error', 'detail', 'message', 'non_field_errors']) {
      if (message != null && message.isNotEmpty) break;
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
