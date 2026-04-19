"""
Notification push service adapters.
"""
from __future__ import annotations

from typing import Any, Sequence

from planpals.integrations.notification_service import NotificationService as FirebasePushNotificationService
from planpals.notifications.application.repositories import DeviceTokenRepository, PushService


class FCMPushService(PushService):
    def __init__(self, device_token_repo: DeviceTokenRepository):
        self.device_token_repo = device_token_repo
        self._push_service: FirebasePushNotificationService | None = None

    def _get_push_service(self) -> FirebasePushNotificationService:
        if self._push_service is None:
            self._push_service = FirebasePushNotificationService()
        return self._push_service

    def send_to_users(
        self,
        user_ids: Sequence[Any],
        title: str,
        body: str,
        data: dict[str, Any],
    ) -> dict[str, int]:
        fcm_tokens = self.device_token_repo.get_active_tokens(user_ids)
        if not fcm_tokens:
            return {'success_count': 0, 'total_count': 0}

        success_count, total_count = self._get_push_service().send_push_notification_batch(
            fcm_tokens=fcm_tokens,
            title=title,
            body=body,
            data=data,
        )
        return {'success_count': success_count, 'total_count': total_count}
