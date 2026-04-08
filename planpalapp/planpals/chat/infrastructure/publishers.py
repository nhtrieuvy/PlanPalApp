"""
Chat-specific realtime event publishers.
"""
import logging
from typing import Any

from planpals.shared.events import RealtimeEvent, EventType, EventPriority
from planpals.shared.realtime_publisher import event_publisher

logger = logging.getLogger(__name__)


def publish_message_sent(conversation_id: str, message_id: str, sender_id: str, 
                        sender_username: str, content: str, timestamp: str,
                        message_type: str = 'text', group_id: str = None):
    """Publish message sent event"""
    event = RealtimeEvent(
        event_type=EventType.MESSAGE_SENT,
        group_id=group_id,
        data={
            'message_id': message_id,
            'conversation_id': conversation_id,
            'sender_id': sender_id,
            'sender_username': sender_username,
            'content': content,
            'timestamp': timestamp,
            'message_type': message_type,
            'initiator_id': sender_id
        }
    )
    
    return event_publisher.publish_event(event, send_push=False)


def publish_message_updated(conversation_id: str, message_id: str, sender_id: str, 
                           content: str, last_updated: str, group_id: str = None):
    """Publish message updated event"""
    event = RealtimeEvent(
        event_type=EventType.MESSAGE_UPDATED,
        group_id=group_id,
        data={
            'message_id': message_id,
            'conversation_id': conversation_id,
            'sender_id': sender_id,
            'content': content,
            'last_updated': last_updated
        }
    )
    
    return event_publisher.publish_event(event, send_push=False)  # Don't push for edits


# ============================================================================
# Infrastructure services for chat realtime & push
# ============================================================================


class ChatRealtimePublisher:
    """Publishes chat messages to WebSocket channels."""

    def send_message(self, message: Any) -> None:
        """Broadcast a chat message to the conversation's WebSocket channel."""
        try:
            from channels.layers import get_channel_layer
            from asgiref.sync import async_to_sync
            from planpals.chat.presentation.serializers import ChatMessageSerializer
            from planpals.shared.events import ChannelGroups

            channel_layer = get_channel_layer()
            if not channel_layer:
                return

            serializer = ChatMessageSerializer(message)
            message_data = serializer.data

            group_name = ChannelGroups.conversation(str(message.conversation.id))
            async_to_sync(channel_layer.group_send)(
                group_name,
                {
                    'type': 'chat_message',
                    'data': message_data,
                },
            )
        except Exception as e:
            logger.error(f"Error sending realtime message: {e}", exc_info=True)


class ChatPushNotificationPublisher:
    """Sends push notifications for new chat messages via Celery (async)."""

    def send_notification(self, message: Any) -> None:
        """Dispatch notification fan-out into the unified notification pipeline."""
        try:
            from planpals.notifications.domain.entities import NotificationType
            from planpals.notifications.infrastructure.tasks import (
                fanout_group_notification_task,
            )

            if not message.sender:
                return

            sender_name = (
                message.sender.get_full_name() or message.sender.username
            )
            group_name = (
                message.conversation.group.name
                if message.conversation.group
                else None
            )
            content_preview = (message.content or '')[:100]
            recipient_ids = list(
                message.conversation.participants.exclude(id=message.sender.id).values_list(
                    'id',
                    flat=True,
                )
            )
            conversation_name = group_name
            if message.conversation.conversation_type == 'direct':
                other_user = message.conversation.get_other_participant(message.sender)
                conversation_name = other_user.get_full_name() or other_user.username if other_user else None

            fanout_group_notification_task.delay(
                notification_type=NotificationType.NEW_MESSAGE.value,
                recipient_user_ids=[str(user_id) for user_id in recipient_ids],
                exclude_user_ids=[str(message.sender.id)],
                data={
                    'message_id': str(message.id),
                    'conversation_id': str(message.conversation.id),
                    'conversation_name': conversation_name,
                    'conversation_type': message.conversation.conversation_type or 'direct',
                    'sender_id': str(message.sender.id),
                    'sender_name': sender_name,
                    'preview': content_preview,
                    'message_type': message.message_type or 'text',
                    'group_name': group_name,
                    'actor_name': sender_name,
                },
                send_push=True,
            )

        except Exception as e:
            logger.error(f"Error dispatching chat push task: {e}", exc_info=True)
