"""
Django signals for chat message real-time event publishing.
"""
import logging
from django.db import transaction
from django.db.models.signals import post_save
from django.dispatch import receiver

from planpals.chat.infrastructure.models import ChatMessage
from planpals.chat.infrastructure.publishers import publish_message_sent

logger = logging.getLogger(__name__)


@receiver(post_save, sender=ChatMessage)
def chat_message_post_save(sender, instance, created, **kwargs):
    """Publish chat message events"""
    try:
        if created and not instance.is_deleted:
            # New message sent
            def _publish_message_sent():
                publish_message_sent(
                    conversation_id=str(instance.conversation_id),
                    message_id=str(instance.id),
                    sender_id=str(instance.sender_id),
                    sender_username=instance.sender.username,
                    content=instance.content,
                    timestamp=instance.created_at.isoformat()
                )
            transaction.on_commit(_publish_message_sent)
            
    except Exception as e:
        logger.error(f"Error publishing chat message event: {e}")
