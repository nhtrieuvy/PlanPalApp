"""
Django signals for group membership real-time event publishing.
"""
import logging
from django.db import transaction
from django.db.models.signals import post_save, post_delete
from django.dispatch import receiver

from planpals.groups.infrastructure.models import GroupMembership
from planpals.groups.infrastructure.publishers import (
    publish_group_member_added,
    publish_group_member_removed,
    publish_group_role_changed,
)

logger = logging.getLogger(__name__)


@receiver(post_save, sender=GroupMembership)
def group_membership_post_save(sender, instance, created, **kwargs):
    """Publish group membership events"""
    try:
        if created:
            # New member added
            def _publish_member_added():
                publish_group_member_added(
                    group_id=str(instance.group_id),
                    user_id=str(instance.user_id),
                    username=instance.user.username,
                    role=instance.role,
                    group_name=instance.group.name if hasattr(instance, 'group') else None
                )
            transaction.on_commit(_publish_member_added)
        else:
            # Role changed
            def _publish_role_changed():
                publish_group_role_changed(
                    group_id=str(instance.group_id),
                    user_id=str(instance.user_id),
                    username=instance.user.username,
                    new_role=instance.role,
                    group_name=instance.group.name if hasattr(instance, 'group') else None
                )
            transaction.on_commit(_publish_role_changed)
            
    except Exception as e:
        logger.error(f"Error publishing group membership event: {e}")


@receiver(post_delete, sender=GroupMembership)
def group_membership_post_delete(sender, instance, **kwargs):
    """Publish group member removal event"""
    try:
        def _publish_member_removed():
            publish_group_member_removed(
                group_id=str(instance.group_id),
                user_id=str(instance.user_id),
                username=instance.user.username,
                group_name=instance.group.name if hasattr(instance, 'group') else None
            )
        transaction.on_commit(_publish_member_removed)
        
    except Exception as e:
        logger.error(f"Error publishing group member removal event: {e}")
