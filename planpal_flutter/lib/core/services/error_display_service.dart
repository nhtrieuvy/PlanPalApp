import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

/// Service to display user-friendly error messages
class ErrorDisplayService {
  /// Show error dialog with user-friendly message
  static void showErrorDialog(
    BuildContext context, {
    required String title,
    required String message,
    VoidCallback? onRetry,
  }) {
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
                child: const Text('Thử lại'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Đóng'),
              style: TextButton.styleFrom(foregroundColor: Colors.grey[600]),
            ),
          ],
        );
      },
    );
  }

  /// Show error snackbar with user-friendly message
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

  /// Show warning snackbar
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

  /// Show success snackbar
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

  /// Parse error from API response and return user-friendly message
  static String parseApiError(dynamic error) {
    if (error is DioException) {
      final response = error.response;

      // Handle network errors
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return 'Không thể kết nối đến máy chủ. Vui lòng kiểm tra kết nối mạng.';
      }

      if (error.type == DioExceptionType.connectionError) {
        return 'Lỗi kết nối. Vui lòng kiểm tra kết nối mạng và thử lại.';
      }

      // Handle response errors
      if (response != null && response.data != null) {
        final data = response.data;

        // Check for our custom error format
        if (data is Map<String, dynamic>) {
          // Backend custom error format
          if (data.containsKey('error')) {
            return data['error'] as String;
          }

          // DRF validation errors
          if (data.containsKey('detail')) {
            return data['detail'] as String;
          }

          // Field-specific errors
          final errorMessages = <String>[];
          for (final entry in data.entries) {
            if (entry.value is List) {
              for (final msg in entry.value as List) {
                errorMessages.add('${_fieldNameToVietnamese(entry.key)}: $msg');
              }
            } else if (entry.value is String) {
              errorMessages.add(
                '${_fieldNameToVietnamese(entry.key)}: ${entry.value}',
              );
            }
          }

          if (errorMessages.isNotEmpty) {
            return errorMessages.join('\n');
          }
        }

        // Handle status codes
        switch (response.statusCode) {
          case 400:
            return 'Dữ liệu không hợp lệ. Vui lòng kiểm tra lại thông tin.';
          case 401:
            return 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.';
          case 403:
            return 'Bạn không có quyền thực hiện hành động này.';
          case 404:
            return 'Không tìm thấy dữ liệu yêu cầu.';
          case 409:
            return 'Dữ liệu bị xung đột. Vui lòng thử lại.';
          case 429:
            return 'Bạn đã gửi quá nhiều yêu cầu. Vui lòng đợi một chút.';
          case 500:
          case 502:
          case 503:
            return 'Lỗi máy chủ. Vui lòng thử lại sau.';
        }
      }
    }

    // Generic error message
    return error.toString().contains('Exception: ')
        ? error.toString().replaceFirst('Exception: ', '')
        : 'Đã xảy ra lỗi không mong đợi. Vui lòng thử lại.';
  }

  /// Get error title based on error type
  static String getErrorTitle(dynamic error) {
    if (error is DioException) {
      final response = error.response;

      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionError) {
        return 'Lỗi Kết Nối';
      }

      if (response != null) {
        switch (response.statusCode) {
          case 400:
            return 'Dữ Liệu Không Hợp Lệ';
          case 401:
            return 'Phiên Hết Hạn';
          case 403:
            return 'Không Có Quyền';
          case 404:
            return 'Không Tìm Thấy';
          case 409:
            return 'Xung Đột Dữ Liệu';
          case 429:
            return 'Quá Nhiều Yêu Cầu';
          case 500:
          case 502:
          case 503:
            return 'Lỗi Máy Chủ';
        }
      }
    }

    return 'Có Lỗi Xảy Ra';
  }

  /// Handle error and show appropriate UI feedback
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
                label: 'Thử lại',
                textColor: Colors.white,
                onPressed: onRetry,
              )
            : null,
      );
    }
  }

  /// Convert English field names to Vietnamese
  static String _fieldNameToVietnamese(String field) {
    const fieldMap = {
      'title': 'Tiêu đề',
      'description': 'Mô tả',
      'start_date': 'Ngày bắt đầu',
      'end_date': 'Ngày kết thúc',
      'start_time': 'Thời gian bắt đầu',
      'end_time': 'Thời gian kết thúc',
      'name': 'Tên',
      'email': 'Email',
      'password': 'Mật khẩu',
      'username': 'Tên đăng nhập',
      'phone_number': 'Số điện thoại',
      'location_name': 'Tên địa điểm',
      'location_address': 'Địa chỉ',
      'estimated_cost': 'Chi phí dự kiến',
      'activity_type': 'Loại hoạt động',
      'non_field_errors': 'Lỗi chung',
    };

    return fieldMap[field] ?? field;
  }
}
