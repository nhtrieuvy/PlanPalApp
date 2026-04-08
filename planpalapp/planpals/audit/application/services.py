"""
Audit application services.
"""
from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from enum import Enum
from typing import Any
from uuid import UUID

from rest_framework.exceptions import PermissionDenied, ValidationError

from planpals.audit.application.repositories import (
    AuditLogCreateData,
    AuditLogFilters,
    AuditLogRepository,
)
from planpals.audit.domain.entities import AuditAction


class AuditLogService:
    MAX_PAGE_SIZE = 100

    def __init__(
        self,
        audit_log_repo: AuditLogRepository,
        audit_log_notification_dispatcher=None,
    ):
        self.audit_log_repo = audit_log_repo
        self.audit_log_notification_dispatcher = audit_log_notification_dispatcher

    def log_action(
        self,
        user,
        action: str,
        resource_type: str,
        resource_id,
        metadata: dict[str, Any] | None = None,
    ):
        user_id = self._normalize_optional_uuid(user, field_name='user')
        resource_uuid = self._normalize_optional_uuid(resource_id, field_name='resource_id')

        if action not in AuditAction.values():
            raise ValidationError({'action': f'Unsupported audit action: {action}'})

        normalized_resource_type = (resource_type or '').strip().lower()
        if not normalized_resource_type:
            raise ValidationError({'resource_type': 'resource_type is required'})

        payload = AuditLogCreateData(
            user_id=user_id,
            action=action,
            resource_type=normalized_resource_type,
            resource_id=resource_uuid,
            metadata=self._sanitize_metadata(metadata or {}),
        )
        log = self.audit_log_repo.create_log(payload)
        if self.audit_log_notification_dispatcher:
            self.audit_log_notification_dispatcher(log)
        return log

    def list_logs(self, viewer, filters: AuditLogFilters):
        viewer_id = self._normalize_required_uuid(viewer, field_name='viewer')
        normalized_filters = self._normalize_filters(filters)
        return self.audit_log_repo.list_logs(viewer_id, normalized_filters)

    def get_logs_by_resource(
        self,
        viewer,
        resource_type: str,
        resource_id,
        filters: AuditLogFilters,
    ):
        viewer_id = self._normalize_required_uuid(viewer, field_name='viewer')
        normalized_resource_id = self._normalize_required_uuid(resource_id, field_name='resource_id')
        normalized_resource_type = (resource_type or '').strip().lower()
        if not normalized_resource_type:
            raise ValidationError({'resource_type': 'resource_type is required'})

        if not self.audit_log_repo.can_view_resource(
            viewer_id=viewer_id,
            resource_type=normalized_resource_type,
            resource_id=normalized_resource_id,
        ):
            raise PermissionDenied('You do not have permission to view these audit logs.')

        normalized_filters = self._normalize_filters(filters)
        return self.audit_log_repo.get_logs_by_resource(
            viewer_id=viewer_id,
            resource_type=normalized_resource_type,
            resource_id=normalized_resource_id,
            filters=normalized_filters,
        )

    def get_logs_by_user(self, viewer, user_id, filters: AuditLogFilters):
        viewer_id = self._normalize_required_uuid(viewer, field_name='viewer')
        normalized_user_id = self._normalize_required_uuid(user_id, field_name='user_id')
        normalized_filters = self._normalize_filters(filters)
        return self.audit_log_repo.get_logs_by_user(
            viewer_id=viewer_id,
            user_id=normalized_user_id,
            filters=normalized_filters,
        )

    def _normalize_filters(self, filters: AuditLogFilters) -> AuditLogFilters:
        page_size = min(max(filters.page_size or 20, 1), self.MAX_PAGE_SIZE)
        if filters.date_from and filters.date_to and filters.date_from > filters.date_to:
            raise ValidationError({'date_range': 'date_from must be earlier than or equal to date_to'})

        return AuditLogFilters(
            user_id=filters.user_id,
            action=filters.action,
            resource_type=(filters.resource_type or '').strip().lower() or None,
            date_from=filters.date_from,
            date_to=filters.date_to,
            cursor=filters.cursor,
            page_size=page_size,
        )

    def _normalize_required_uuid(self, value, field_name: str) -> UUID:
        normalized = self._normalize_optional_uuid(value, field_name=field_name)
        if normalized is None:
            raise ValidationError({field_name: f'{field_name} is required'})
        return normalized

    @staticmethod
    def _normalize_optional_uuid(value, field_name: str) -> UUID | None:
        if value is None:
            return None

        raw_value = getattr(value, 'id', value)
        if isinstance(raw_value, UUID):
            return raw_value
        try:
            return UUID(str(raw_value))
        except (TypeError, ValueError) as exc:
            raise ValidationError({field_name: f'Invalid UUID for {field_name}'}) from exc

    def _sanitize_metadata(self, value: Any) -> Any:
        if isinstance(value, dict):
            return {str(key): self._sanitize_metadata(item) for key, item in value.items()}
        if isinstance(value, (list, tuple, set)):
            return [self._sanitize_metadata(item) for item in value]
        if isinstance(value, UUID):
            return str(value)
        if isinstance(value, datetime):
            return value.isoformat()
        if isinstance(value, date):
            return value.isoformat()
        if isinstance(value, Decimal):
            return float(value)
        if isinstance(value, Enum):
            return value.value
        return value
