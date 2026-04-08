"""
Notification realtime publishers.
"""
from __future__ import annotations

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer

from planpals.notifications.application.repositories import NotificationPublisher
from planpals.shared.events import ChannelGroups


class ChannelsNotificationPublisher(NotificationPublisher):
    def __init__(self):
        self.channel_layer = get_channel_layer()

    def publish_notification_created(self, notification, unread_count: int) -> None:
        self._send(
            notification.user_id,
            {
                'type': 'notification.created',
                'notification': self._serialize(notification),
                'unread_count': unread_count,
            },
        )

    def publish_notification_read(self, user_id, notification_id, unread_count: int) -> None:
        self._send(
            user_id,
            {
                'type': 'notification.read',
                'notification_id': str(notification_id),
                'unread_count': unread_count,
            },
        )

    def publish_all_read(self, user_id) -> None:
        self._send(
            user_id,
            {
                'type': 'notification.read_all',
                'unread_count': 0,
            },
        )

    def _send(self, user_id, payload: dict) -> None:
        if not self.channel_layer:
            return
        async_to_sync(self.channel_layer.group_send)(
            ChannelGroups.user(str(user_id)),
            {
                'type': 'event.message',
                'data': payload,
            },
        )

    @staticmethod
    def _serialize(notification) -> dict:
        return {
            'id': str(notification.id),
            'user_id': str(notification.user_id),
            'type': notification.type,
            'title': notification.title,
            'message': notification.message,
            'data': notification.data or {},
            'is_read': notification.is_read,
            'read_at': notification.read_at.isoformat() if notification.read_at else None,
            'created_at': notification.created_at.isoformat() if notification.created_at else None,
        }
