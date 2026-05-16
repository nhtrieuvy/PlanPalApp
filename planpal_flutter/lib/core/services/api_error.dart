import 'package:dio/dio.dart';

import '../localization/app_locale.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic data;
  final String? errorCode;
  final Map<String, List<String>> fieldErrors;

  const ApiException(
    this.message, {
    this.statusCode,
    this.data,
    this.errorCode,
    this.fieldErrors = const {},
  });

  @override
  String toString() => message;
}

const Set<String> _reservedErrorKeys = {
  'code',
  'error',
  'detail',
  'details',
  'message',
  'error_code',
  'status_code',
  'non_field_errors',
  'errors',
};

String _currentLanguageCode() => AppLocaleStore.currentLanguageCode;

String _fallbackMessageForStatus(int? statusCode, {String? languageCode}) {
  final lang = languageCode ?? _currentLanguageCode();
  final en = lang == 'en';
  switch (statusCode) {
    case 400:
      return en
          ? 'Some information is invalid. Please check and try again.'
          : 'Thông tin chưa hợp lệ. Vui lòng kiểm tra lại.';
    case 401:
      return en
          ? 'Your session has expired. Please sign in again.'
          : 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.';
    case 403:
      return en
          ? 'You do not have permission to perform this action.'
          : 'Bạn không có quyền thực hiện hành động này.';
    case 404:
      return en
          ? 'The requested information could not be found.'
          : 'Không tìm thấy dữ liệu yêu cầu.';
    case 409:
      return en
          ? 'The data has changed. Please refresh and try again.'
          : 'Dữ liệu đã thay đổi. Vui lòng tải lại và thử lại.';
    case 413:
      return en
          ? 'The uploaded file is too large. Please choose a smaller file.'
          : 'Tệp tải lên quá lớn. Vui lòng chọn tệp nhỏ hơn.';
    case 429:
      return en
          ? 'Too many requests. Please wait a moment and try again.'
          : 'Bạn đã gửi quá nhiều yêu cầu. Vui lòng chờ một chút.';
    case 500:
    case 502:
    case 503:
      return en
          ? 'The server is having trouble. Please try again later.'
          : 'Máy chủ đang gặp sự cố. Vui lòng thử lại sau.';
    default:
      return en
          ? 'Request failed. Please try again.'
          : 'Yêu cầu thất bại. Vui lòng thử lại.';
  }
}

bool _looksLikeHtml(String value) {
  final trimmed = value.trimLeft().toLowerCase();
  return trimmed.startsWith('<!doctype html') ||
      trimmed.startsWith('<html') ||
      trimmed.contains('<head>') ||
      trimmed.contains('<body>');
}

bool _looksCorrupted(String value) {
  return value.contains('Ã') ||
      value.contains('Ä') ||
      value.contains('Â') ||
      value.contains('áº') ||
      value.contains('á»');
}

String? _asString(dynamic value) {
  if (value == null) return null;
  if (value is List && value.isNotEmpty) return _asString(value.first);
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

List<String> _asStringList(dynamic value) {
  if (value == null) return const [];
  if (value is List) {
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  final text = value.toString().trim();
  return text.isEmpty ? const [] : [text];
}

Map<String, List<String>> _extractFieldErrors(Map<dynamic, dynamic> data) {
  final result = <String, List<String>>{};

  final details = data['details'];
  if (details is Map) {
    final fields = details['fields'];
    if (fields is Map) {
      for (final entry in fields.entries) {
        final key = entry.key.toString();
        final messages = _asStringList(entry.value);
        if (messages.isNotEmpty) result[key] = messages;
      }
    }
  }

  final errors = data['errors'];
  if (errors is Map) {
    for (final entry in errors.entries) {
      final key = entry.key.toString();
      final messages = _asStringList(entry.value);
      if (messages.isNotEmpty) result[key] = messages;
    }
  }

  for (final entry in data.entries) {
    final key = entry.key.toString();
    if (_reservedErrorKeys.contains(key)) continue;
    final messages = _asStringList(entry.value);
    if (messages.isNotEmpty) result.putIfAbsent(key, () => messages);
  }

  return result;
}

String? _extractErrorCode(Map<dynamic, dynamic> data) {
  return _asString(data['error_code']) ?? _asString(data['code']);
}

String? _extractRawMessage(Map<dynamic, dynamic> data) {
  final details = data['details'];
  final detailNonField = details is Map
      ? _asString((details['non_field_errors'] as dynamic))
      : null;
  return _asString(data['message']) ??
      _asString(data['error']) ??
      _asString(data['detail']) ??
      _asString(data['non_field_errors']) ??
      detailNonField;
}

String? _localizedMessageForErrorCode(String? code, {required String lang}) {
  if (code == null || code.isEmpty || code == 'error') return null;
  final en = lang == 'en';
  final messages = <String, List<String>>{
    'username_exists': [
      'Username is already taken. Please choose another username.',
      'Tên đăng nhập đã tồn tại. Vui lòng chọn tên khác.',
    ],
    'username_pending_verification': [
      'This username is waiting for email verification. Please verify your email or try again later.',
      'Tên đăng nhập này đang chờ xác thực email. Vui lòng xác thực email hoặc thử lại sau.',
    ],
    'email_exists': [
      'This email is already registered. Please sign in or use another email.',
      'Email này đã được sử dụng. Vui lòng đăng nhập hoặc dùng email khác.',
    ],
    'email_not_verified': [
      'Your email is not verified. Please enter the verification code before signing in.',
      'Email chưa được xác thực. Vui lòng nhập mã xác thực trước khi đăng nhập.',
    ],
    'invalid_registration_payload': [
      'Registration information is incomplete. Please check and try again.',
      'Thông tin đăng ký chưa đầy đủ. Vui lòng kiểm tra lại.',
    ],
    'avatar_too_large': [
      'The avatar image is too large. Please choose a smaller image.',
      'Ảnh đại diện quá lớn. Vui lòng chọn ảnh nhỏ hơn.',
    ],
    'email_send_failed': [
      'Could not send the verification code. Please try again later.',
      'Không thể gửi mã xác thực. Vui lòng thử lại sau.',
    ],
    'missing_code': [
      'Please enter the 6-digit verification code.',
      'Vui lòng nhập mã xác thực 6 số.',
    ],
    'invalid_code_format': [
      'The verification code must contain exactly 6 digits.',
      'Mã xác thực phải gồm đúng 6 chữ số.',
    ],
    'invalid_or_expired_code': [
      'The verification code is invalid or expired. Please request a new code.',
      'Mã xác thực không đúng hoặc đã hết hạn. Vui lòng yêu cầu mã mới.',
    ],
    'too_many_attempts': [
      'Too many attempts. Please wait a moment before trying again.',
      'Bạn đã thử quá nhiều lần. Vui lòng chờ một chút rồi thử lại.',
    ],
    'invalid_grant': [
      'Incorrect username or password.',
      'Sai tên đăng nhập hoặc mật khẩu.',
    ],
    'invalid_client': [
      'The app login configuration is invalid.',
      'Cấu hình đăng nhập của ứng dụng không hợp lệ.',
    ],
    'permission_denied': [
      'You do not have permission to perform this action.',
      'Bạn không có quyền thực hiện hành động này.',
    ],
    'validation_error': [
      'Some information is invalid. Please check and try again.',
      'Thông tin chưa hợp lệ. Vui lòng kiểm tra lại.',
    ],
    'not_found': [
      'The requested information could not be found.',
      'Không tìm thấy dữ liệu yêu cầu.',
    ],
    'conflict': [
      'The data has changed. Please refresh and try again.',
      'Dữ liệu đã thay đổi. Vui lòng tải lại và thử lại.',
    ],
    'rate_limited': [
      'Too many requests. Please wait a moment and try again.',
      'Bạn đã gửi quá nhiều yêu cầu. Vui lòng chờ một chút rồi thử lại.',
    ],
    'internal_error': [
      'The server is having trouble. Please try again later.',
      'Máy chủ đang gặp sự cố. Vui lòng thử lại sau.',
    ],
    'not_group_admin': [
      'Only group administrators can perform this action.',
      'Chỉ quản trị viên nhóm mới có thể thực hiện hành động này.',
    ],
    'not_group_member': [
      'You are not a member of this group.',
      'Bạn chưa phải là thành viên của nhóm này.',
    ],
    'already_member': [
      'You are already in this group.',
      'Bạn đã ở trong nhóm này rồi.',
    ],
    'last_admin': [
      'The group must always have at least one administrator.',
      'Nhóm phải luôn có ít nhất một quản trị viên.',
    ],
    'cannot_remove_admin': [
      'You cannot remove another administrator from the group.',
      'Không thể xóa quản trị viên khác khỏi nhóm.',
    ],
    'not_friends': [
      'Only friends can be added to a group.',
      'Chỉ có thể thêm bạn bè vào nhóm.',
    ],
    'max_members_exceeded': [
      'This group has reached the member limit.',
      'Nhóm đã đạt giới hạn số lượng thành viên.',
    ],
    'group_not_found': ['Group could not be found.', 'Không tìm thấy nhóm.'],
    'group_invite_not_found': [
      'Invite code is invalid or no longer available.',
      'Mã mời không hợp lệ hoặc không còn khả dụng.',
    ],
    'group_invite_expired': [
      'This invite code has expired.',
      'Mã mời này đã hết hạn.',
    ],
    'group_invite_revoked': [
      'This invite code has been revoked.',
      'Mã mời này đã bị thu hồi.',
    ],
    'group_invite_usage_limit_exceeded': [
      'This invite code has reached its usage limit.',
      'Mã mời này đã đạt giới hạn lượt sử dụng.',
    ],
    'group_join_request_pending': [
      'Your join request is waiting for admin approval.',
      'Yêu cầu tham gia của bạn đang chờ quản trị viên duyệt.',
    ],
    'group_join_request_not_found': [
      'Join request could not be found.',
      'Không tìm thấy yêu cầu tham gia nhóm.',
    ],
    'group_join_request_not_pending': [
      'This join request has already been handled.',
      'Yêu cầu tham gia này đã được xử lý.',
    ],
    'already_friends': ['You are already friends.', 'Hai bạn đã là bạn bè.'],
    'friend_request_already_sent': [
      'Friend request has already been sent.',
      'Lời mời kết bạn đã được gửi trước đó.',
    ],
    'cannot_send_to_self': [
      'You cannot perform this action with yourself.',
      'Bạn không thể thực hiện hành động này với chính mình.',
    ],
    'activity_overlap': [
      'This activity overlaps another activity. Please choose a different time.',
      'Thời gian hoạt động bị trùng lặp. Vui lòng chọn giờ khác.',
    ],
    'invalid_date_range': [
      'End date must be after start date.',
      'Ngày kết thúc phải sau ngày bắt đầu.',
    ],
    'invalid_time_range': [
      'End time must be after start time.',
      'Thời gian kết thúc phải sau thời gian bắt đầu.',
    ],
    'activity_outside_plan_date': [
      'Activity time must be within the plan date range.',
      'Thời gian hoạt động phải nằm trong khoảng thời gian của kế hoạch.',
    ],
    'activity_version_conflict': [
      'This activity was updated by someone else. Please reload before saving.',
      'Hoạt động này đã được người khác cập nhật. Vui lòng tải lại trước khi lưu.',
    ],
    'plan_completed': [
      'This plan is already completed and cannot be changed.',
      'Kế hoạch đã hoàn thành nên không thể thay đổi.',
    ],
    'plan_cancelled': [
      'This plan has been cancelled and cannot be changed.',
      'Kế hoạch đã bị hủy nên không thể thay đổi.',
    ],
    'not_plan_owner': [
      'Only the plan creator can perform this action.',
      'Chỉ người tạo kế hoạch mới có thể thực hiện hành động này.',
    ],
    'plan_not_found': ['Plan could not be found.', 'Không tìm thấy kế hoạch.'],
    'activity_not_found': [
      'Activity could not be found.',
      'Không tìm thấy hoạt động.',
    ],
    'cannot_modify_activity': [
      'You do not have permission to edit this activity.',
      'Bạn không có quyền chỉnh sửa hoạt động này.',
    ],
    'activity_version_required': [
      'Please reload the activity before saving changes.',
      'Vui lòng tải lại hoạt động trước khi lưu thay đổi.',
    ],
    'payload_too_large': [
      'The uploaded file is too large. Please choose a smaller file.',
      'Tệp tải lên quá lớn. Vui lòng chọn tệp nhỏ hơn.',
    ],
    'invalid_file_type': [
      'This file type is not supported.',
      'Loại tệp này chưa được hỗ trợ.',
    ],
    'file_size_too_large': [
      'The file is too large. Please choose a smaller file.',
      'Tệp quá lớn. Vui lòng chọn tệp nhỏ hơn.',
    ],
  };

  final pair = messages[code];
  if (pair == null) {
    return null;
  }
  return en ? pair.first : pair.last;
}

String _localizedFieldLabel(String field, {required String lang}) {
  final en = lang == 'en';
  final labels = <String, List<String>>{
    'username': ['Username', 'Tên đăng nhập'],
    'email': ['Email', 'Email'],
    'password': ['Password', 'Mật khẩu'],
    'password_confirm': ['Confirm password', 'Xác nhận mật khẩu'],
    'first_name': ['First name', 'Tên'],
    'last_name': ['Last name', 'Họ'],
    'phone_number': ['Phone number', 'Số điện thoại'],
    'name': ['Name', 'Tên'],
    'title': ['Title', 'Tiêu đề'],
    'description': ['Description', 'Mô tả'],
    'start_date': ['Start date', 'Ngày bắt đầu'],
    'end_date': ['End date', 'Ngày kết thúc'],
    'start_time': ['Start time', 'Thời gian bắt đầu'],
    'end_time': ['End time', 'Thời gian kết thúc'],
    'activity_type': ['Activity type', 'Loại hoạt động'],
    'location_name': ['Location name', 'Tên địa điểm'],
    'location_address': ['Address', 'Địa chỉ'],
    'estimated_cost': ['Estimated cost', 'Chi phí dự kiến'],
    'amount': ['Amount', 'Số tiền'],
    'category': ['Category', 'Danh mục'],
    'code': ['Verification code', 'Mã xác thực'],
    'invite_code': ['Invite code', 'Mã mời'],
    'initial_members': ['Members', 'Thành viên'],
    'participants': ['Participants', 'Người tham gia'],
    'paid_by_user_id': ['Payer', 'Người trả tiền'],
    'split_strategy': ['Split method', 'Cách chia'],
    'total_budget': ['Total budget', 'Tổng ngân sách'],
    'currency': ['Currency', 'Đơn vị tiền'],
    'file': ['File', 'Tệp'],
    'attachment': ['Attachment', 'Tệp đính kèm'],
    'non_field_errors': ['Error', 'Lỗi'],
  };
  final pair = labels[field];
  if (pair == null) return field.replaceAll('_', ' ');
  return en ? pair.first : pair.last;
}

bool _messageSuggestsDuplicate(String raw) {
  final normalized = raw.toLowerCase();
  return normalized.contains('exist') ||
      normalized.contains('already') ||
      normalized.contains('taken') ||
      normalized.contains('unique') ||
      normalized.contains('tồn tại') ||
      normalized.contains('đã') ||
      _looksCorrupted(raw);
}

String _localizedFieldMessage(
  String field,
  List<String> rawMessages, {
  required String lang,
}) {
  final en = lang == 'en';
  final raw = rawMessages.join(' ');
  if (field == 'username' && _messageSuggestsDuplicate(raw)) {
    return en
        ? 'Username is already taken. Please choose another username.'
        : 'Tên đăng nhập đã tồn tại. Vui lòng chọn tên khác.';
  }
  if (field == 'email' && _messageSuggestsDuplicate(raw)) {
    return en
        ? 'This email is already registered. Please use another email.'
        : 'Email này đã được sử dụng. Vui lòng dùng email khác.';
  }
  if (field == 'password_confirm') {
    return en
        ? 'Password confirmation does not match.'
        : 'Mật khẩu xác nhận không khớp.';
  }
  if (field == 'code' || field == 'invite_code') {
    return en
        ? '${_localizedFieldLabel(field, lang: lang)} is invalid.'
        : '${_localizedFieldLabel(field, lang: lang)} không hợp lệ.';
  }

  final safeRaw = rawMessages.firstWhere(
    (message) => !_looksCorrupted(message) && !_looksLikeHtml(message),
    orElse: () => '',
  );
  if (safeRaw.isNotEmpty && safeRaw.length <= 160) {
    return '${_localizedFieldLabel(field, lang: lang)}: $safeRaw';
  }

  return en
      ? '${_localizedFieldLabel(field, lang: lang)} is invalid.'
      : '${_localizedFieldLabel(field, lang: lang)} chưa hợp lệ.';
}

String? _localizedMessageForFields(
  Map<String, List<String>> fields, {
  required String lang,
}) {
  if (fields.isEmpty) return null;
  final messages = fields.entries
      .map(
        (entry) => _localizedFieldMessage(entry.key, entry.value, lang: lang),
      )
      .toList();
  return messages.join('\n');
}

String? _safeBackendMessage(String? raw, {required String lang}) {
  if (raw == null || raw.isEmpty) return null;
  if (_looksLikeHtml(raw) || _looksCorrupted(raw)) return null;
  final lower = raw.toLowerCase();
  final known = <String, List<String>>{
    'incorrect username or password': [
      'Incorrect username or password.',
      'Sai tên đăng nhập hoặc mật khẩu.',
    ],
    'already friends': ['You are already friends.', 'Hai bạn đã là bạn bè.'],
    'friend request already sent': [
      'Friend request has already been sent.',
      'Lời mời kết bạn đã được gửi trước đó.',
    ],
    'cannot send friend request to yourself': [
      'You cannot send a friend request to yourself.',
      'Bạn không thể gửi lời mời kết bạn cho chính mình.',
    ],
  };
  for (final entry in known.entries) {
    if (lower.contains(entry.key)) {
      return lang == 'en' ? entry.value.first : entry.value.last;
    }
  }
  return raw;
}

/// Centralized helper to extract a meaningful error message from a [Response].
ApiException buildApiException(Response res) {
  final data = res.data;
  final lang = _currentLanguageCode();
  String? message;
  String? errorCode;
  Map<String, List<String>> fieldErrors = const {};

  if (data is Map) {
    errorCode = _extractErrorCode(data);
    fieldErrors = _extractFieldErrors(data);
    message =
        _localizedMessageForErrorCode(errorCode, lang: lang) ??
        _localizedMessageForFields(fieldErrors, lang: lang) ??
        _safeBackendMessage(_extractRawMessage(data), lang: lang);
  } else if (data != null) {
    final raw = data.toString();
    message = _safeBackendMessage(raw, lang: lang);
  }

  message = (message ?? '').trim();
  if (message.isEmpty || _looksLikeHtml(message)) {
    message = _fallbackMessageForStatus(res.statusCode, languageCode: lang);
  }

  return ApiException(
    message,
    statusCode: res.statusCode,
    data: data,
    errorCode: errorCode,
    fieldErrors: fieldErrors,
  );
}
