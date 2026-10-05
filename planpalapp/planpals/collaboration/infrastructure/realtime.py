import logging

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer

from planpals.shared.events import ChannelGroups


logger = logging.getLogger(__name__)


class CollaborationRealtimePublisher:
    def notify_user(self, user_id, data: dict) -> None:
        from planpals.notifications.domain.entities import NotificationType
        from planpals.notifications.infrastructure.tasks import send_notification_task

        try:
            send_notification_task.apply_async(
                args=[str(user_id), NotificationType.PLAN_UPDATED.value, data],
                kwargs={'send_push': True},
                queue='high_priority',
                ignore_result=True,
            )
        except Exception:
            logger.exception(
                'Unable to enqueue collaboration notification',
                extra={'recipient_user_id': str(user_id)},
            )

    def publish_plan(self, plan_id, event_type: str, data: dict) -> None:
        layer = get_channel_layer()
        if layer is None:
            return
        try:
            async_to_sync(layer.group_send)(
                ChannelGroups.plan(str(plan_id)),
                {
                    'type': 'event.message',
                    'data': {
                        'event_type': event_type,
                        'plan_id': str(plan_id),
                        'data': data,
                    },
                },
            )
        except Exception:
            logger.exception(
                'Unable to publish collaboration plan event',
                extra={'plan_id': str(plan_id), 'event_type': event_type},
            )

    def publish_group(self, group_id, event_type: str, data: dict) -> None:
        layer = get_channel_layer()
        if layer is None:
            return
        try:
            async_to_sync(layer.group_send)(
                ChannelGroups.group(str(group_id)),
                {
                    'type': 'event.message',
                    'data': {
                        'event_type': event_type,
                        'group_id': str(group_id),
                        'data': data,
                    },
                },
            )
        except Exception:
            logger.exception(
                'Unable to publish collaboration group event',
                extra={'group_id': str(group_id), 'event_type': event_type},
            )
