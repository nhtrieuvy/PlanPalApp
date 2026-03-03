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
    """Sends push notifications for new chat messages."""

    def send_notification(self, message: Any) -> None:
        """Send push notifications to all participants except the sender."""
        try:
            from planpals.integrations.notification_service import NotificationService

            if not message.sender:
                return

            notification_service = NotificationService()
            participants = message.conversation.participants.exclude(id=message.sender.id)

            for participant in participants:
                if not (hasattr(participant, 'fcm_token') and participant.fcm_token):
                    continue

                title = self._build_title(message)
                body = self._build_body(message)
                data = {
                    'action': 'new_message',
                    'conversation_id': str(message.conversation.id),
                    'message_id': str(message.id),
                    'sender_id': str(message.sender.id),
                }

                notification_service.send_push_notification(
                    [participant.fcm_token], title, body, data,
                )

        except Exception as e:
            logger.error(f"Error sending push notification: {e}", exc_info=True)

    def _build_title(self, message: Any) -> str:
        sender_name = message.sender.get_full_name() or message.sender.username
        if message.conversation.conversation_type == 'direct':
            return f"Tin nhắn từ {sender_name}"
        group_name = (
            message.conversation.group.name if message.conversation.group else "Nhóm"
        )
        return f"{sender_name} trong {group_name}"

    def _build_body(self, message: Any) -> str:
        type_map = {
            'text': lambda m: m.content[:100],
            'image': lambda _: "📷 Đã gửi một hình ảnh",
            'location': lambda m: f"📍 Đã chia sẻ vị trí: {m.location_name or 'Vị trí'}",
            'file': lambda m: f"📎 Đã gửi file: {m.attachment_name or 'File'}",
        }
        formatter = type_map.get(message.message_type, lambda _: "Đã gửi một tin nhắn")
        return formatter(message)
