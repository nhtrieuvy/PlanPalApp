"""
Notification application services.
"""
from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from enum import Enum
from typing import Any, Iterable
from uuid import UUID, uuid4

from rest_framework.exceptions import ValidationError

from planpals.notifications.application.repositories import (
    DeviceTokenRepository,
    NotificationCreateData,
    NotificationFilters,
    NotificationPublisher,
    NotificationRepository,
    PushService,
)
from planpals.audit.domain.entities import AuditAction, AuditResourceType
from planpals.notifications.domain.entities import NotificationType


class NotificationService:
    MAX_PAGE_SIZE = 100

    def __init__(
        self,
        notification_repo: NotificationRepository,
        device_token_repo: DeviceTokenRepository,
        push_service: PushService,
        publisher: NotificationPublisher,
        audit_service=None,
    ):
        self.notification_repo = notification_repo
        self.device_token_repo = device_token_repo
        self.push_service = push_service
        self.publisher = publisher
        self.audit_service = audit_service

    def notify(
        self,
        user_id,
        notification_type: str,
        data: dict[str, Any] | None = None,
        *,
        send_push: bool = True,
    ):
        normalized_user_id = self._normalize_required_uuid(user_id, 'user_id')
        payload = self._build_payload(notification_type, data or {})
        notification = self.notification_repo.create_notification(
            NotificationCreateData(
                id=uuid4(),
                user_id=normalized_user_id,
                type=notification_type,
                title=payload['title'],
                message=payload['message'],
                data=payload['data'],
            )
        )
        unread_count = self.notification_repo.get_unread_count(normalized_user_id)
        self.publisher.publish_notification_created(notification, unread_count)

        if send_push:
            self.push_service.send_to_users(
                [normalized_user_id],
                title=notification.title,
                body=notification.message,
                data=self._push_payload(notification),
            )
        return notification

    def notify_many(
        self,
        user_ids: Iterable[UUID | str],
        notification_type: str,
        data: dict[str, Any] | None = None,
        *,
        send_push: bool = True,
        exclude_user_ids: Iterable[UUID | str] | None = None,
    ):
        recipient_ids = self._normalize_user_id_list(user_ids)
        excluded_ids = set(self._normalize_user_id_list(exclude_user_ids or []))
        recipient_ids = [user_id for user_id in recipient_ids if user_id not in excluded_ids]
        if not recipient_ids:
            return []

        payload = self._build_payload(notification_type, data or {})
        items = [
            NotificationCreateData(
                id=uuid4(),
                user_id=user_id,
                type=notification_type,
                title=payload['title'],
                message=payload['message'],
                data=payload['data'],
            )
            for user_id in recipient_ids
        ]
        notifications = list(self.notification_repo.bulk_create_notifications(items))
        unread_counts = self.notification_repo.get_unread_counts(recipient_ids)
        for notification in notifications:
            self.publisher.publish_notification_created(
                notification,
                unread_counts.get(notification.user_id, 0),
            )

        if send_push:
            self.push_service.send_to_users(
                recipient_ids,
                title=payload['title'],
                body=payload['message'],
                data={
                    **payload['data'],
                    'notification_type': notification_type,
                },
            )
        return notifications

    def list_notifications(self, user_id, filters: NotificationFilters):
        normalized_user_id = self._normalize_required_uuid(user_id, 'user_id')
        normalized_filters = NotificationFilters(
            is_read=filters.is_read,
            cursor=filters.cursor,
            page_size=min(max(filters.page_size or 20, 1), self.MAX_PAGE_SIZE),
        )
        return self.notification_repo.get_user_notifications(
            normalized_user_id,
            normalized_filters,
        )

    def mark_as_read(self, user_id, notification_id):
        normalized_user_id = self._normalize_required_uuid(user_id, 'user_id')
        normalized_notification_id = self._normalize_required_uuid(
            notification_id,
            'notification_id',
        )
        notification = self.notification_repo.get_notification_for_user(
            normalized_user_id,
            normalized_notification_id,
        )
        updated = self.notification_repo.mark_as_read(
            normalized_user_id,
            normalized_notification_id,
        )
        if updated:
            unread_count = self.notification_repo.get_unread_count(normalized_user_id)
            self.publisher.publish_notification_read(
                normalized_user_id,
                normalized_notification_id,
                unread_count,
            )
            self._log_open_event(
                user_id=normalized_user_id,
                notification_id=normalized_notification_id,
                notification=notification,
                notification_count=1,
                bulk=False,
            )
        return updated

    def mark_all_as_read(self, user_id) -> int:
        normalized_user_id = self._normalize_required_uuid(user_id, 'user_id')
        updated_count = self.notification_repo.mark_all_as_read(normalized_user_id)
        if updated_count:
            self.publisher.publish_all_read(normalized_user_id)
            self._log_open_event(
                user_id=normalized_user_id,
                notification_id=None,
                notification=None,
                notification_count=updated_count,
                bulk=True,
            )
        return updated_count

    def get_unread_count(self, user_id) -> int:
        normalized_user_id = self._normalize_required_uuid(user_id, 'user_id')
        return self.notification_repo.get_unread_count(normalized_user_id)

    def register_device_token(self, user_id, token: str, platform: str) -> bool:
        normalized_user_id = self._normalize_required_uuid(user_id, 'user_id')
        normalized_token = (token or '').strip()
        if not normalized_token:
            raise ValidationError({'fcm_token': 'fcm_token is required'})

        normalized_platform = (platform or '').strip().lower() or 'android'
        if normalized_platform not in {'android', 'ios', 'web'}:
            raise ValidationError({'platform': 'Unsupported platform'})

        return self.device_token_repo.register_device_token(
            user_id=normalized_user_id,
            token=normalized_token,
            platform=normalized_platform,
        )

    def _build_payload(self, notification_type: str, data: dict[str, Any]) -> dict[str, Any]:
        if notification_type not in NotificationType.values():
            raise ValidationError({'type': f'Unsupported notification type: {notification_type}'})

        normalized_data = self._sanitize_data(data)
        if normalized_data.get('notification_title') and normalized_data.get('notification_message'):
            return {
                'title': str(normalized_data['notification_title']).strip(),
                'message': str(normalized_data['notification_message']).strip(),
                'data': normalized_data,
            }

        title, message = self._format_content(notification_type, normalized_data)
        return {
            'title': title,
            'message': message,
            'data': normalized_data,
        }

    def _format_content(self, notification_type: str, data: dict[str, Any]) -> tuple[str, str]:
        actor_name = str(data.get('actor_name') or data.get('sender_name') or 'Someone')
        group_name = str(data.get('group_name') or 'your group')
        plan_title = str(data.get('plan_title') or data.get('title') or 'your plan')
        membership_event = str(data.get('membership_event') or 'join').lower()
        change_type = str(data.get('change_type') or 'updated').lower()

        if notification_type == NotificationType.PLAN_REMINDER.value:
            start_date = str(data.get('start_date_display') or data.get('start_date') or 'soon')
            return 'Plan reminder', f'"{plan_title}" starts {start_date}.'

        if notification_type == NotificationType.GROUP_JOIN.value:
            if membership_event == 'leave':
                return 'Group activity', f'{actor_name} left "{group_name}".'
            if membership_event == 'deleted':
                return 'Group activity', f'"{group_name}" was deleted.'
            return 'Group activity', f'{actor_name} joined "{group_name}".'

        if notification_type == NotificationType.GROUP_INVITE.value:
            return 'Group invite', f'{actor_name} invited you to join "{group_name}".'

        if notification_type == NotificationType.ROLE_CHANGED.value:
            new_role = str(data.get('new_role') or '').upper() or 'UPDATED'
            return 'Role updated', f'Your role in "{group_name}" is now {new_role}.'

        if notification_type == NotificationType.PLAN_UPDATED.value:
            if change_type == 'created':
                return 'New plan', f'{actor_name} created "{plan_title}".'
            if change_type == 'deleted':
                return 'Plan removed', f'{actor_name} deleted "{plan_title}".'
            return 'Plan updated', f'{actor_name} updated "{plan_title}".'

        if notification_type == NotificationType.NEW_MESSAGE.value:
            preview = str(data.get('preview') or data.get('content') or 'Sent a new message')
            conversation_name = str(data.get('conversation_name') or group_name).strip()
            if conversation_name:
                return 'New message', f'{actor_name} in "{conversation_name}": {preview}'
            return 'New message', f'{actor_name}: {preview}'

        raise ValidationError({'type': f'Unsupported notification type: {notification_type}'})

    def _push_payload(self, notification) -> dict[str, Any]:
        return {
            'notification_id': str(notification.id),
            'notification_type': notification.type,
            **(notification.data or {}),
        }

    def _sanitize_data(self, value: Any) -> Any:
        if isinstance(value, dict):
            return {str(key): self._sanitize_data(item) for key, item in value.items()}
        if isinstance(value, (list, tuple, set)):
            return [self._sanitize_data(item) for item in value]
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

    def _log_open_event(
        self,
        *,
        user_id: UUID,
        notification_id: UUID | None,
        notification,
        notification_count: int,
        bulk: bool,
    ) -> None:
        if not self.audit_service or notification_count <= 0:
            return

        metadata = {
            'notification_count': notification_count,
            'bulk': bulk,
        }
        if notification is not None:
            metadata.update(
                {
                    'notification_type': notification.type,
                    'notification_title': notification.title,
                }
            )

        self.audit_service.log_action(
            user=user_id,
            action=AuditAction.NOTIFICATION_OPENED.value,
            resource_type=AuditResourceType.NOTIFICATION.value,
            resource_id=notification_id,
            metadata=metadata,
        )

    def _normalize_user_id_list(self, user_ids: Iterable[UUID | str]) -> list[UUID]:
        return [self._normalize_required_uuid(user_id, 'user_id') for user_id in user_ids]

    def _normalize_required_uuid(self, value, field_name: str) -> UUID:
        normalized = self._normalize_optional_uuid(value, field_name)
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
