"""
Notification infrastructure repository implementations.
"""
from __future__ import annotations

import base64
import json
from datetime import datetime
from typing import Optional, Sequence
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from django.contrib.auth import get_user_model
from django.db import transaction
from django.db.models import Count, Q, QuerySet
from django.utils import timezone

from planpals.notifications.application.repositories import (
    DeviceTokenRepository,
    NotificationCreateData,
    NotificationFilters,
    NotificationPage,
    NotificationRepository,
)
from planpals.notifications.infrastructure.models import (
    Notification,
    NotificationPreference,
    UserDeviceToken,
)

User = get_user_model()


class DjangoNotificationRepository(NotificationRepository):
    def create_notification(self, data: NotificationCreateData) -> Notification:
        return Notification.objects.create(
            id=data.id,
            user_id=data.user_id,
            type=data.type,
            title=data.title,
            message=data.message,
            data=data.data,
        )

    def bulk_create_notifications(
        self,
        items: Sequence[NotificationCreateData],
    ) -> Sequence[Notification]:
        created_at = timezone.now()
        notifications = [
            Notification(
                id=item.id,
                user_id=item.user_id,
                type=item.type,
                title=item.title,
                message=item.message,
                data=item.data,
                created_at=created_at,
            )
            for item in items
        ]
        if not notifications:
            return []
        Notification.objects.bulk_create(notifications, batch_size=500)
        return notifications

    def get_user_notifications(
        self,
        user_id: UUID,
        filters: NotificationFilters,
    ) -> NotificationPage:
        queryset = self._base_queryset().filter(user_id=user_id)
        if filters.is_read is not None:
            queryset = queryset.filter(is_read=filters.is_read)

        created_at, last_id = self._decode_cursor(filters.cursor)
        if created_at and last_id:
            queryset = queryset.filter(
                Q(created_at__lt=created_at)
                | Q(created_at=created_at, id__lt=last_id)
            )

        page_size = filters.page_size or 20
        items = list(queryset[: page_size + 1])
        has_more = len(items) > page_size
        if has_more:
            items = items[:page_size]

        next_cursor = None
        if has_more and items:
            last_item = items[-1]
            next_cursor = self._encode_cursor(last_item.created_at, last_item.id)

        return NotificationPage(
            items=items,
            next_cursor=next_cursor,
            has_more=has_more,
            page_size=page_size,
            unread_count=self.get_unread_count(user_id),
        )

    def get_notification_for_user(self, user_id: UUID, notification_id: UUID) -> Notification | None:
        return self._base_queryset().filter(user_id=user_id, id=notification_id).first()

    def mark_as_read(self, user_id: UUID, notification_id: UUID) -> bool:
        updated = Notification.objects.filter(
            user_id=user_id,
            id=notification_id,
            is_read=False,
        ).update(
            is_read=True,
            read_at=timezone.now(),
        )
        return updated > 0

    def mark_all_as_read(self, user_id: UUID) -> int:
        return Notification.objects.filter(
            user_id=user_id,
            is_read=False,
        ).update(
            is_read=True,
            read_at=timezone.now(),
        )

    def get_unread_count(self, user_id: UUID) -> int:
        return Notification.objects.filter(user_id=user_id, is_read=False).count()

    def get_unread_counts(self, user_ids: Sequence[UUID]) -> dict[UUID, int]:
        counts = (
            Notification.objects.filter(user_id__in=user_ids, is_read=False)
            .values('user_id')
            .annotate(total=Count('id'))
        )
        count_map = {UUID(str(item['user_id'])): int(item['total']) for item in counts}
        for user_id in user_ids:
            count_map.setdefault(user_id, 0)
        return count_map

    def get_preferences(self, user_id: UUID):
        preference, _ = NotificationPreference.objects.get_or_create(user_id=user_id)
        return preference

    def update_preferences(self, user_id: UUID, values: dict):
        preference, _ = NotificationPreference.objects.update_or_create(
            user_id=user_id,
            defaults=values,
        )
        return preference

    def get_push_allowed_user_ids(self, user_ids, current_time):
        unique_ids = list(dict.fromkeys(UUID(str(value)) for value in user_ids))
        preferences = {
            item.user_id: item
            for item in NotificationPreference.objects.filter(user_id__in=unique_ids)
        }
        return [
            user_id
            for user_id in unique_ids
            if self._push_allowed(preferences.get(user_id), current_time)
        ]

    def list_digest_candidates(self, current_time):
        candidates = NotificationPreference.objects.filter(
            daily_digest_enabled=True,
            push_enabled=True,
        ).select_related('user')
        result = []
        for preference in candidates.iterator(chunk_size=500):
            try:
                zone = ZoneInfo(preference.timezone)
            except ZoneInfoNotFoundError:
                zone = ZoneInfo('UTC')
            local_now = current_time.astimezone(zone)
            already_sent_today = (
                preference.last_digest_sent_at is not None
                and preference.last_digest_sent_at.astimezone(zone).date()
                == local_now.date()
            )
            if (
                local_now.hour == preference.daily_digest_hour
                and not already_sent_today
                and self._push_allowed(preference, current_time)
            ):
                result.append(preference)
        return result

    def get_digest_summary(self, user_id, since):
        queryset = Notification.objects.filter(
            user_id=user_id,
            is_read=False,
            created_at__gte=since,
        )
        return {
            'count': queryset.count(),
            'titles': list(queryset.values_list('title', flat=True)[:3]),
        }

    def mark_digest_sent(self, user_id, sent_at):
        NotificationPreference.objects.filter(user_id=user_id).update(
            last_digest_sent_at=sent_at,
            updated_at=timezone.now(),
        )

    @staticmethod
    def _push_allowed(preference, current_time):
        if preference is None:
            return True
        if not preference.push_enabled:
            return False
        if not preference.quiet_hours_enabled:
            return True
        if preference.quiet_hours_start is None or preference.quiet_hours_end is None:
            return True
        try:
            local_time = current_time.astimezone(
                ZoneInfo(preference.timezone)
            ).time().replace(tzinfo=None)
        except ZoneInfoNotFoundError:
            local_time = current_time.astimezone(
                ZoneInfo('UTC')
            ).time().replace(tzinfo=None)
        start = preference.quiet_hours_start
        end = preference.quiet_hours_end
        in_quiet_hours = (
            start <= local_time < end
            if start < end
            else local_time >= start or local_time < end
        )
        return not in_quiet_hours

    def _base_queryset(self) -> QuerySet[Notification]:
        return Notification.objects.select_related('user').order_by('-created_at', '-id')

    @staticmethod
    def _encode_cursor(created_at: datetime, item_id: UUID) -> str:
        raw = json.dumps({'created_at': created_at.isoformat(), 'id': str(item_id)})
        return base64.urlsafe_b64encode(raw.encode('utf-8')).decode('ascii')

    @staticmethod
    def _decode_cursor(cursor: Optional[str]) -> tuple[Optional[datetime], Optional[UUID]]:
        if not cursor:
            return None, None

        try:
            payload = json.loads(base64.urlsafe_b64decode(cursor.encode('ascii')).decode('utf-8'))
            created_at = datetime.fromisoformat(payload['created_at'])
            item_id = UUID(str(payload['id']))
            return created_at, item_id
        except (KeyError, TypeError, ValueError, json.JSONDecodeError):
            return None, None


class DjangoDeviceTokenRepository(DeviceTokenRepository):
    @transaction.atomic
    def register_device_token(self, user_id: UUID, token: str, platform: str) -> bool:
        token = (token or '').strip()
        if not token:
            return False

        device_token, _ = UserDeviceToken.objects.update_or_create(
            token=token,
            defaults={
                'user_id': user_id,
                'platform': platform,
                'is_active': True,
                'last_seen_at': timezone.now(),
            },
        )
        User.objects.filter(id=user_id).update(fcm_token=device_token.token)
        return True

    def get_active_tokens(self, user_ids: Sequence[UUID | str]) -> list[str]:
        normalized_user_ids = [str(user_id) for user_id in user_ids]
        if not normalized_user_ids:
            return []
        tokens = (
            UserDeviceToken.objects.filter(
                user_id__in=normalized_user_ids,
                is_active=True,
            )
            .values_list('token', flat=True)
        )
        return list(tokens)
