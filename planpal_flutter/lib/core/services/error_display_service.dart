import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../localization/app_locale.dart';
import '../localization/app_localizations.dart';
import 'api_error.dart';

/// Centralized service for production-safe, user-friendly error messages.
///
/// UI code should pass raw exceptions here instead of interpolating `$error`.
/// Technical details stay in logs; users receive localized, actionable text.
class ErrorDisplayService {
  static void showErrorDialog(
    BuildContext context, {
    required String title,
    required String message,
    VoidCallback? onRetry,
  }) {
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Text(message, style: const TextStyle(fontSize: 16)),
          actions: [
            if (onRetry != null)
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onRetry();
                },
                child: Text(l10n.t('common.retry')),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(foregroundColor: Colors.grey[600]),
              child: Text(l10n.t('common.close')),
            ),
          ],
        );
      },
    );
  }

  static void showErrorSnackbar(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: const TextStyle(fontSize: 15)),
            ),
          ],
        ),
        backgroundColor: Colors.red[700],
        duration: duration,
        action: action,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static void showWarningSnackbar(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: const TextStyle(fontSize: 15)),
            ),
          ],
        ),
        backgroundColor: Colors.orange[700],
        duration: duration,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static void showSuccessSnackbar(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: const TextStyle(fontSize: 15)),
            ),
          ],
        ),
        backgroundColor: Colors.green[700],
        duration: duration,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static String parseApiError(dynamic error) {
    if (error is ApiException) {
      return error.message;
    }

    if (error is DioException) {
      final response = error.response;
      if (response != null) {
        return buildApiException(response).message;
      }
      return _networkMessage(error);
    }

    if (error is FormatException) {
      return _localized(
        en: 'The server returned unexpected data. Please try again.',
        vi: 'Máy chủ trả về dữ liệu không hợp lệ. Vui lòng thử lại.',
      );
    }

    final raw = _cleanPlainException(error);
    if (raw != null) return raw;

    return _localized(
      en: 'Something went wrong. Please try again.',
      vi: 'Đã xảy ra lỗi không mong đợi. Vui lòng thử lại.',
    );
  }

  static String getUserFriendlyMessage(dynamic error) => parseApiError(error);

  static String getErrorTitle(dynamic error) {
    final statusCode = error is ApiException
        ? error.statusCode
        : error is DioException
        ? error.response?.statusCode
        : null;

    if (error is DioException && error.response == null) {
      return _localized(en: 'Connection Error', vi: 'Lỗi kết nối');
    }

    switch (statusCode) {
      case 400:
        return _localized(
          en: 'Invalid Information',
          vi: 'Thông tin chưa hợp lệ',
        );
      case 401:
        return _localized(en: 'Session Expired', vi: 'Phiên đã hết hạn');
      case 403:
        return _localized(en: 'Permission Denied', vi: 'Không có quyền');
      case 404:
        return _localized(en: 'Not Found', vi: 'Không tìm thấy');
      case 409:
        return _localized(en: 'Data Conflict', vi: 'Xung đột dữ liệu');
      case 413:
        return _localized(en: 'File Too Large', vi: 'Tệp quá lớn');
      case 429:
        return _localized(en: 'Too Many Requests', vi: 'Quá nhiều yêu cầu');
      case 500:
      case 502:
      case 503:
        return _localized(en: 'Server Error', vi: 'Lỗi máy chủ');
      default:
        return _localized(en: 'Something Went Wrong', vi: 'Có lỗi xảy ra');
    }
  }

  static void handleError(
    BuildContext context,
    dynamic error, {
    bool showDialog = false,
    VoidCallback? onRetry,
  }) {
    final message = parseApiError(error);
    final title = getErrorTitle(error);

    if (showDialog) {
      showErrorDialog(
        context,
        title: title,
        message: message,
        onRetry: onRetry,
      );
    } else {
      showErrorSnackbar(
        context,
        message,
        action: onRetry != null
            ? SnackBarAction(
                label: context.l10n.t('common.retry'),
                textColor: Colors.white,
                onPressed: onRetry,
              )
            : null,
      );
    }
  }

  static String _localized({required String en, required String vi}) {
    return AppLocaleStore.currentLanguageCode == 'en' ? en : vi;
  }

  static String _networkMessage(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return _localized(
          en: 'Connection timed out. Please check your network and try again.',
          vi: 'Kết nối quá hạn. Vui lòng kiểm tra mạng và thử lại.',
        );
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return _localized(
          en: 'Cannot connect to the server. Please check your network.',
          vi: 'Không thể kết nối đến máy chủ. Vui lòng kiểm tra mạng.',
        );
      case DioExceptionType.cancel:
        return _localized(
          en: 'Request was cancelled.',
          vi: 'Yêu cầu đã bị hủy.',
        );
      case DioExceptionType.badCertificate:
        return _localized(
          en: 'Secure connection failed. Please try again later.',
          vi: 'Kết nối bảo mật thất bại. Vui lòng thử lại sau.',
        );
      case DioExceptionType.badResponse:
        return _localized(
          en: 'Request failed. Please try again.',
          vi: 'Yêu cầu thất bại. Vui lòng thử lại.',
        );
    }
  }

  static String? _cleanPlainException(dynamic error) {
    if (error == null) return null;
    var text = error.toString().trim();
    if (text.isEmpty) return null;

    text = text
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .replaceFirst(RegExp(r'^ApiException:\s*'), '')
        .trim();

    if (text.isEmpty) return null;
    final normalized = text.toLowerCase();
    if (_looksCorrupted(text)) {
      if (normalized.contains('sai')) {
        return _localized(
          en: 'Incorrect username or password.',
          vi: 'Sai tên đăng nhập hoặc mật khẩu.',
        );
      }
      if (normalized.contains('email')) {
        return _localized(
          en: 'Your email is not verified. Please enter the verification code before signing in.',
          vi: 'Email chưa được xác thực. Vui lòng nhập mã xác thực trước khi đăng nhập.',
        );
      }
      if (normalized.contains('oauth') || normalized.contains('client')) {
        return _localized(
          en: 'The app login configuration is invalid.',
          vi: 'Cấu hình đăng nhập của ứng dụng không hợp lệ.',
        );
      }
      if (normalized.contains('kết') || normalized.contains('kh')) {
        return _localized(
          en: 'Cannot connect to the server. Please check your network.',
          vi: 'Không thể kết nối đến máy chủ. Vui lòng kiểm tra mạng.',
        );
      }
      return null;
    }
    if (_looksTechnical(text)) return null;
    return text;
  }

  static bool _looksCorrupted(String text) {
    return text.contains('Ã') ||
        text.contains('Ä') ||
        text.contains('Â') ||
        text.contains('áº') ||
        text.contains('á»') ||
        text.contains('Æ');
  }

  static bool _looksTechnical(String text) {
    final lower = text.toLowerCase();
    return lower.contains('dioexception') ||
        lower.contains('socketexception') ||
        lower.contains('httpexception') ||
        lower.contains('status code') ||
        lower.contains('bad response') ||
        lower.contains('<!doctype html') ||
        lower.contains('<html') ||
        lower.contains('traceback') ||
        lower.contains('null check operator') ||
        lower.contains('typeerror') ||
        lower.contains('os error') ||
        lower.contains('errno');
  }
}
