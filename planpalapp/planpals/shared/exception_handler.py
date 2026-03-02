"""
Custom exception handler for DRF to provide user-friendly error messages
"""
from typing import Any

from rest_framework.views import exception_handler
from rest_framework.response import Response
from rest_framework import status
from django.core.exceptions import ValidationError as DjangoValidationError, PermissionDenied as DjangoPermissionDenied
from planpals.shared.exceptions import PlanPalException
import logging

logger = logging.getLogger(__name__)


RESERVED_ERROR_KEYS = {
    'error',
    'detail',
    'message',
    'error_code',
    'status_code',
    'non_field_errors',
    'errors',
}


def _to_str(value: Any) -> str:
    if value is None:
        return ''
    return str(value)


def _normalize_messages(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, (list, tuple)):
        return [_to_str(item) for item in value if _to_str(item)]
    text = _to_str(value)
    return [text] if text else []


def _first_message(value: Any) -> str | None:
    messages = _normalize_messages(value)
    return messages[0] if messages else None


def _normalize_error_data(error_data: Any) -> tuple[str, dict[str, list[str]], list[str], dict[str, Any]]:
    default_message = 'Đã xảy ra lỗi.'

    if isinstance(error_data, dict):
        errors: dict[str, list[str]] = {}
        passthrough_fields: dict[str, Any] = {}

        for field, value in error_data.items():
            if field in RESERVED_ERROR_KEYS:
                continue
            normalized = _normalize_messages(value)
            if normalized:
                errors[field] = normalized
                passthrough_fields[field] = value

        non_field_errors = _normalize_messages(error_data.get('non_field_errors'))

        message = (
            _first_message(error_data.get('error'))
            or _first_message(error_data.get('detail'))
            or _first_message(error_data.get('message'))
            or (non_field_errors[0] if non_field_errors else None)
            or (next(iter(errors.values()))[0] if errors else None)
            or default_message
        )

        if not non_field_errors:
            non_field_errors = [message]

        return message, errors, non_field_errors, passthrough_fields

    if isinstance(error_data, list):
        non_field_errors = _normalize_messages(error_data)
        message = non_field_errors[0] if non_field_errors else default_message
        return message, {}, non_field_errors or [message], {}

    message = _to_str(error_data) or default_message
    return message, {}, [message], {}


def _build_error_response(
    *,
    message: str,
    status_code: int,
    error_code: str,
    errors: dict[str, list[str]] | None = None,
    non_field_errors: list[str] | None = None,
    extra_fields: dict[str, Any] | None = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        'error': message,
        'detail': message,
        'message': message,
        'error_code': error_code,
        'status_code': status_code,
        'non_field_errors': non_field_errors or [message],
    }

    if errors:
        payload['errors'] = errors

    if extra_fields:
        payload.update(extra_fields)

    return payload


def custom_exception_handler(exc, context):
    """
    Custom exception handler that returns user-friendly error messages
    """
    # Call REST framework's default exception handler first
    response = exception_handler(exc, context)
    
    # Handle PlanPal custom exceptions
    if isinstance(exc, PlanPalException):
        message, errors, non_field_errors, passthrough_fields = _normalize_error_data(exc.detail)
        return Response(
            _build_error_response(
                message=message,
                status_code=exc.status_code,
                error_code=exc.default_code,
                errors=errors,
                non_field_errors=non_field_errors,
                extra_fields=passthrough_fields,
            ),
            status=exc.status_code,
        )
    
    # Handle Django ValidationError
    if isinstance(exc, DjangoValidationError):
        # Chuyển đổi ValidationError message sang tiếng Việt
        error_message = _translate_validation_error(exc)

        translated_errors = {}
        passthrough_fields = {}
        if hasattr(exc, 'message_dict'):
            for field, messages in exc.message_dict.items():
                translated = [
                    _translate_message_item(message)
                    for message in messages
                ]
                translated_errors[field] = translated
                passthrough_fields[field] = translated

        return Response(
            _build_error_response(
                message=error_message,
                status_code=status.HTTP_400_BAD_REQUEST,
                error_code='validation_error',
                errors=translated_errors,
                non_field_errors=[error_message],
                extra_fields=passthrough_fields,
            ),
            status=status.HTTP_400_BAD_REQUEST,
        )
    
    # Handle Django PermissionDenied
    if isinstance(exc, DjangoPermissionDenied):
        message = str(exc) if str(exc) else 'Bạn không có quyền thực hiện hành động này.'
        return Response(
            _build_error_response(
                message=message,
                status_code=status.HTTP_403_FORBIDDEN,
                error_code='permission_denied',
            ),
            status=status.HTTP_403_FORBIDDEN,
        )
    
    # If response was generated by DRF's handler
    if response is not None:
        message, errors, non_field_errors, passthrough_fields = _normalize_error_data(response.data)
        error_code = 'error'
        if isinstance(response.data, dict):
            error_code = _to_str(response.data.get('error_code') or 'error')

        return Response(
            _build_error_response(
                message=message,
                status_code=response.status_code,
                error_code=error_code,
                errors=errors,
                non_field_errors=non_field_errors,
                extra_fields=passthrough_fields,
            ),
            status=response.status_code,
        )
    
    # For unexpected exceptions, log them and return generic error
    logger.error(f"Unexpected exception: {exc}", exc_info=True)
    
    message = 'Đã xảy ra lỗi không mong đợi. Vui lòng thử lại sau.'
    return Response(
        _build_error_response(
            message=message,
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            error_code='internal_error',
        ),
        status=status.HTTP_500_INTERNAL_SERVER_ERROR,
    )


def _translate_message_item(message: Any) -> str:
    translations = {
        'Activity cannot end after plan end date': 'Thời gian kết thúc hoạt động không được vượt quá ngày kết thúc của kế hoạch.',
        'Activity cannot start before plan start date': 'Thời gian bắt đầu hoạt động không được sớm hơn ngày bắt đầu của kế hoạch.',
        'Activity duration must not exceed 24 hours': 'Thời lượng hoạt động không được vượt quá 24 giờ.',
        'End time must be after start time': 'Thời gian kết thúc phải sau thời gian bắt đầu.',
        'End date must be after start date': 'Ngày kết thúc phải sau ngày bắt đầu.',
        'Latitude must be between -90 and 90': 'Vĩ độ phải nằm trong khoảng -90 đến 90.',
        'Longitude must be between -180 and 180': 'Kinh độ phải nằm trong khoảng -180 đến 180.',
        'Estimated cost must be non-negative': 'Chi phí ước tính không được âm.',
        'Cannot create friendship with yourself': 'Không thể kết bạn với chính mình.',
        'Group must have at least one admin': 'Nhóm phải có ít nhất một quản trị viên.',
        'Personal plan cannot have a group': 'Kế hoạch cá nhân không thể có nhóm.',
        'Group plan must have a group': 'Kế hoạch nhóm phải có nhóm.',
        'You must be a member of the group to create a plan': 'Bạn phải là thành viên của nhóm để tạo kế hoạch.',
        'Cannot update a plan that is already completed': 'Không thể cập nhật kế hoạch đã hoàn thành.',
        'Permission denied to edit this plan': 'Bạn không có quyền chỉnh sửa kế hoạch này.',
        'Activity time conflicts with existing activities': 'Hoạt động trùng thời gian với hoạt động khác.',
    }
    text = _to_str(message)
    return translations.get(text, text)


def _translate_validation_error(exc):
    """
    Chuyển đổi Django ValidationError messages sang tiếng Việt
    """
    # Dictionary ánh xạ các message thường gặp
    
    # Lấy message từ exception
    if hasattr(exc, 'message'):
        error_message = exc.message
    elif hasattr(exc, 'message_dict'):
        # Multiple field errors
        errors = []
        for field, messages in exc.message_dict.items():
            for message in messages:
                translated = _translate_message_item(message)
                errors.append(f"{field}: {translated}")
        return '; '.join(errors)
    else:
        error_message = str(exc)

    # Chuyển đổi sang tiếng Việt nếu có trong dictionary
    return _translate_message_item(error_message)
