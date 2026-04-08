import 'package:dio/dio.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

String _fallbackMessageForStatus(int? statusCode) {
  switch (statusCode) {
    case 400:
      return 'Du lieu gui len khong hop le.';
    case 401:
      return 'Phien dang nhap da het han. Vui long dang nhap lai.';
    case 403:
      return 'Ban khong co quyen thuc hien hanh dong nay.';
    case 404:
      return 'Khong tim thay du lieu yeu cau.';
    case 409:
      return 'Du lieu bi xung dot. Vui long thu lai.';
    case 429:
      return 'Ban da gui qua nhieu yeu cau. Vui long doi mot chut.';
    case 500:
    case 502:
    case 503:
      return 'May chu dang gap su co. Vui long thu lai sau.';
    default:
      return 'Yeu cau that bai${statusCode != null ? ' ($statusCode)' : ''}.';
  }
}

bool _looksLikeHtml(String value) {
  final trimmed = value.trimLeft().toLowerCase();
  return trimmed.startsWith('<!doctype html') ||
      trimmed.startsWith('<html') ||
      trimmed.contains('<head>') ||
      trimmed.contains('<body>');
}

/// Centralized helper to extract a meaningful error message from a [Response].
ApiException buildApiException(Response res) {
  final data = res.data;
  String? message;

  if (data is Map) {
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

    for (final key in ['error', 'detail', 'message', 'non_field_errors']) {
      if (message != null && message.isNotEmpty) break;
      final value = data[key];
      if (value == null) continue;

      if (value is List && value.isNotEmpty) {
        message = value.first.toString();
        break;
      }

      message = value.toString();
      break;
    }

    message ??= data.values.isNotEmpty ? data.values.first.toString() : null;
  } else if (data != null) {
    final raw = data.toString();
    if (!_looksLikeHtml(raw)) {
      message = raw;
    }
  }

  message = (message ?? '').trim();
  if (message.isEmpty || _looksLikeHtml(message)) {
    message = _fallbackMessageForStatus(res.statusCode);
  }

  return ApiException(message, statusCode: res.statusCode);
}
