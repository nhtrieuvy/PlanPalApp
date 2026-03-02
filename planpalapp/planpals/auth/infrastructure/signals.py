"""
Django signals for user-related real-time event publishing
"""
import logging
from django.db import transaction
from django.db.models.signals import post_save, pre_save
from django.dispatch import receiver
from django.contrib.auth import get_user_model
from planpals.shared.realtime_publisher import (
    publish_user_online,
    publish_user_offline
)

logger = logging.getLogger(__name__)
User = get_user_model()


# Signal to track user online status changes
@receiver(pre_save, sender=User)
def user_pre_save(sender, instance, **kwargs):
    """Track old online status"""
    if instance.pk:
        try:
            old_instance = User.objects.only('is_online').get(pk=instance.pk)
            instance._old_is_online = old_instance.is_online
        except User.DoesNotExist:
            instance._old_is_online = None
    else:
        instance._old_is_online = None


# User online/offline status updates
@receiver(post_save, sender=User)
def user_post_save(sender, instance, **kwargs):
    """Publish user status updates"""
    try:
        # Check if online status changed
        if hasattr(instance, '_old_is_online'):
            old_online = instance._old_is_online
            new_online = instance.is_online
            
            if old_online != new_online:
                if new_online:
                    # User came online
                    def _publish_user_online():
                        publish_user_online(
                            user_id=str(instance.id),
                            username=instance.username
                        )
                    transaction.on_commit(_publish_user_online)
                else:
                    # User went offline
                    def _publish_user_offline():
                        publish_user_offline(
                            user_id=str(instance.id),
                            username=instance.username,
                            last_seen=instance.last_seen.isoformat() if instance.last_seen else None
                        )
                    transaction.on_commit(_publish_user_offline)
                
    except Exception as e:
        logger.error(f"Error publishing user status event: {e}")
