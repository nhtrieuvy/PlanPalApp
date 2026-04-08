"""
Chat Infrastructure — Celery Tasks (Fan-out Push Notifications)

Offloads per-participant push notification delivery from the synchronous
request cycle.  A single ``fanout_chat_push_notification_task`` resolves
conversation participants, builds the notification payload, and dispatches
a batch FCM call.

Queue: high_priority
Design:
  • Idempotent — FCM deduplicates by message ID.
  • Only serialisable primitives as arguments (message_id, conversation_id).
  • Retry with exponential back-off on transient FCM / DB failures.
"""
import logging
from typing import Any, Dict

from celery import shared_task
from celery.exceptions import SoftTimeLimitExceeded

logger = logging.getLogger(__name__)


@shared_task(
    bind=True,
    name='planpals.chat.infrastructure.tasks.fanout_chat_push_notification_task',
    max_retries=3,
    default_retry_delay=10,
    autoretry_for=(Exception,),
    retry_backoff=True,
    retry_backoff_max=120,
    retry_jitter=True,
    soft_time_limit=60,
    rate_limit='200/m',
    acks_late=True,
)
def fanout_chat_push_notification_task(
    self,
    message_id: str,
    conversation_id: str,
    sender_id: str,
    sender_name: str,
    content_preview: str,
    message_type: str = 'text',
    group_name: str | None = None,
    conversation_type: str = 'direct',
) -> Dict[str, Any]:
    """
    Fan-out push notifications for a chat message to all conversation
    participants (excluding the sender).

    Instead of the old synchronous loop that called FCM one-by-one per
    participant, this task:
      1. Queries participants in one DB call.
      2. Builds a single batch FCM request.
      3. Sends via ``NotificationService.send_push_notification_batch()``.

    Args:
        message_id: UUID of the chat message (for deduplication data).
        conversation_id: UUID of the conversation.
        sender_id: UUID of the sender (excluded from recipients).
        sender_name: Display name of the sender.
        content_preview: First 100 chars of message content (pre-truncated).
        message_type: 'text' | 'image' | 'location' | 'file'.
        group_name: Name of the group (for group conversations).
        conversation_type: 'direct' | 'group'.
    """
    try:
        from planpals.models import Conversation
        from planpals.integrations.notification_service import NotificationService
        from planpals.notifications.infrastructure.models import UserDeviceToken

        # --- Build notification text -----------------------------------------
        title = _build_chat_title(sender_name, conversation_type, group_name)
        body = _build_chat_body(content_preview, message_type)

        # --- Resolve FCM tokens in ONE query ---------------------------------
        participant_ids = list(
            Conversation.objects.get(id=conversation_id)
            .participants
            .exclude(id=sender_id)
            .values_list('id', flat=True)
        )
        fcm_tokens = list(
            UserDeviceToken.objects.filter(
                user_id__in=participant_ids,
                is_active=True,
            ).values_list('token', flat=True)
        )

        if not fcm_tokens:
            return {'status': 'skipped', 'reason': 'no_tokens'}

        # --- Send batch FCM -------------------------------------------------
        service = NotificationService()
        success_count, total_count = service.send_push_notification_batch(
            fcm_tokens=fcm_tokens,
            title=title,
            body=body,
            data={
                'action': 'new_message',
                'conversation_id': conversation_id,
                'message_id': message_id,
                'sender_id': sender_id,
            },
        )

        logger.info(
            f"Chat fan-out push: {success_count}/{total_count} for "
            f"conversation={conversation_id} (task_id={self.request.id})"
        )
        return {
            'status': 'sent',
            'success_count': success_count,
            'total_count': total_count,
            'task_id': self.request.id,
        }

    except SoftTimeLimitExceeded:
        logger.error(
            f"Chat fan-out timed out for conversation={conversation_id} "
            f"(task_id={self.request.id})"
        )
        return {'status': 'timeout', 'task_id': self.request.id}

    except Exception as exc:
        logger.error(
            f"Chat fan-out failed for conversation={conversation_id}: {exc} "
            f"(task_id={self.request.id})"
        )
        raise


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _build_chat_title(sender_name: str, conversation_type: str,
                      group_name: str | None) -> str:
    if conversation_type == 'direct':
        return f"Tin nhắn từ {sender_name}"
    return f"{sender_name} trong {group_name or 'Nhóm'}"


def _build_chat_body(content_preview: str, message_type: str) -> str:
    type_map = {
        'text': content_preview,
        'image': "📷 Đã gửi một hình ảnh",
        'location': "📍 Đã chia sẻ vị trí",
        'file': "📎 Đã gửi file",
    }
    return type_map.get(message_type, "Đã gửi một tin nhắn")
