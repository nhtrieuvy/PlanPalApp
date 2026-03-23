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
    
    return event_publisher.publish_event(event)


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
        """Dispatch a fan-out Celery task instead of looping participants synchronously."""
        try:
            from planpals.chat.infrastructure.tasks import (
                fanout_chat_push_notification_task,
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

            fanout_chat_push_notification_task.delay(
                message_id=str(message.id),
                conversation_id=str(message.conversation.id),
                sender_id=str(message.sender.id),
                sender_name=sender_name,
                content_preview=content_preview,
                message_type=message.message_type or 'text',
                group_name=group_name,
                conversation_type=message.conversation.conversation_type or 'direct',
            )

        except Exception as e:
            logger.error(f"Error dispatching chat push task: {e}", exc_info=True)
