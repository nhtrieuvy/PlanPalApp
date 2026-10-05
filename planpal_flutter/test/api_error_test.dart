import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planpal_flutter/core/localization/app_locale.dart';
import 'package:planpal_flutter/core/services/api_error.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';

void main() {
  tearDown(() => AppLocaleStore.setCurrentLocale(const Locale('vi')));

  test('localizes a stable backend error code in Vietnamese', () {
    AppLocaleStore.setCurrentLocale(const Locale('vi'));
    final response = Response<dynamic>(
      requestOptions: RequestOptions(path: '/api/v1/groups/join-code/'),
      statusCode: 400,
      data: {
        'code': 'already_member',
        'message': 'You are already in this group.',
      },
    );

    expect(buildApiException(response).message, 'Bạn đã ở trong nhóm này rồi.');
  });

  test('localizes a stable backend error code in English', () {
    AppLocaleStore.setCurrentLocale(const Locale('en'));
    final response = Response<dynamic>(
      requestOptions: RequestOptions(path: '/api/v1/activities/1/'),
      statusCode: 409,
      data: {
        'error_code': 'activity_version_conflict',
        'message': 'server implementation detail',
      },
    );

    expect(
      buildApiException(response).message,
      'This activity was updated by someone else. Please reload before saving.',
    );
  });

  test('localizes collaboration validation errors', () {
    AppLocaleStore.setCurrentLocale(const Locale('vi'));
    final response = Response<dynamic>(
      requestOptions: RequestOptions(path: '/api/v1/plans/1/work-items/'),
      statusCode: 409,
      data: {
        'code': 'invalid_assignee',
        'message': 'Assignee must belong to this plan.',
      },
    );

    expect(
      buildApiException(response).message,
      'Người được giao phải là thành viên của kế hoạch.',
    );
  });

  test('does not expose unknown backend or technical exception text', () {
    AppLocaleStore.setCurrentLocale(const Locale('en'));
    final response = Response<dynamic>(
      requestOptions: RequestOptions(path: '/api/v1/plans/'),
      statusCode: 500,
      data: {'message': 'SQL connection password=secret'},
    );

    expect(
      buildApiException(response).message,
      'The server is having trouble. Please try again later.',
    );
    expect(
      ErrorDisplayService.parseApiError(
        Exception('SocketException: connection refused'),
      ),
      'Something went wrong. Please try again.',
    );
  });
}
