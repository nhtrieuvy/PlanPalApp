"""
Django signals for automatic real-time event publishing
"""
import logging
from django.db import transaction
from django.db.models.signals import post_save, post_delete, pre_save
from django.dispatch import receiver
from django.contrib.auth import get_user_model
from .models import Plan, PlanActivity, Group, GroupMembership, ChatMessage
from .events import EventType
from .realtime_publisher import (
    publish_plan_created,
    publish_plan_updated, 
    publish_plan_status_changed,
    publish_plan_deleted,
    publish_activity_created,
    publish_activity_updated,
    publish_activity_completed,
    publish_activity_deleted,
    publish_group_member_added,
    publish_group_member_removed,
    publish_group_role_changed,
    publish_message_sent,
    publish_user_online,
    publish_user_offline
)

logger = logging.getLogger(__name__)
User = get_user_model()


@receiver(pre_save, sender=Plan)
def plan_pre_save(sender, instance, **kwargs):
    """Capture old plan status before saving"""
    if instance.pk:
        try:
            old_instance = Plan.objects.get(pk=instance.pk)
            instance._old_status = old_instance.status
        except Plan.DoesNotExist:
            instance._old_status = None
    else:
        instance._old_status = None


@receiver(post_save, sender=Plan)
def plan_post_save(sender, instance, created, **kwargs):
    """Publish plan events after save"""
    try:
        if created:
            # New plan created
            def _publish_plan_created():
                publish_plan_created(
                    plan_id=str(instance.id),
                    title=instance.title,
                    plan_type=instance.plan_type,
                    status=instance.status,
                    creator_id=str(instance.creator_id),
                    group_id=str(instance.group_id) if instance.group_id else None,
                    is_public=instance.is_public,
                    start_date=instance.start_date.isoformat() if instance.start_date else None,
                    end_date=instance.end_date.isoformat() if instance.end_date else None
                )
            transaction.on_commit(_publish_plan_created)
            
        else:
            # Plan updated
            old_status = getattr(instance, '_old_status', None)
            
            # Check if status changed
            if old_status and old_status != instance.status:
                def _publish_status_change():
                    publish_plan_status_changed(
                        plan_id=str(instance.id),
                        old_status=old_status,
                        new_status=instance.status,
                        title=instance.title
                    )
                transaction.on_commit(_publish_status_change)
            
            # General plan update event (for non-status changes)
            elif not old_status or old_status == instance.status:
                def _publish_plan_update():
                    publish_plan_updated(
                        plan_id=str(instance.id),
                        title=instance.title,
                        status=instance.status,
                        last_updated=instance.updated_at.isoformat()
                    )
                transaction.on_commit(_publish_plan_update)
                
    except Exception as e:
        logger.error(f"Error publishing plan event: {e}")


@receiver(post_delete, sender=Plan)
def plan_post_delete(sender, instance, **kwargs):
    """Publish plan deletion event"""
    try:
        def _publish_plan_deleted():
            publish_plan_deleted(
                plan_id=str(instance.id),
                title=instance.title
            )
        transaction.on_commit(_publish_plan_deleted)
        
    except Exception as e:
        logger.error(f"Error publishing plan deletion event: {e}")


@receiver(post_save, sender=PlanActivity)
def activity_post_save(sender, instance, created, **kwargs):
    """Publish activity events after save"""
    try:
        if created:
            # New activity created
            def _publish_activity_created():
                publish_activity_created(
                    plan_id=str(instance.plan_id),
                    activity_id=str(instance.id),
                    title=instance.title,
                    activity_type=instance.activity_type,
                    start_time=instance.start_time.isoformat() if instance.start_time else None,
                    end_time=instance.end_time.isoformat() if instance.end_time else None,
                    location_name=instance.location_name,
                    estimated_cost=float(instance.estimated_cost) if instance.estimated_cost else None
                )
            transaction.on_commit(_publish_activity_created)
            
        else:
            # Activity updated
            # Check if completion status changed
            if hasattr(instance, '_state') and instance._state.adding is False:
                try:
                    old_instance = PlanActivity.objects.get(pk=instance.pk)
                    if not old_instance.is_completed and instance.is_completed:
                        # Activity just completed
                        def _publish_activity_completed():
                            publish_activity_completed(
                                plan_id=str(instance.plan_id),
                                activity_id=str(instance.id),
                                title=instance.title
                            )
                        transaction.on_commit(_publish_activity_completed)
                        return
                except PlanActivity.DoesNotExist:
                    pass
            
            # General activity update
            def _publish_activity_updated():
                publish_activity_updated(
                    plan_id=str(instance.plan_id),
                    activity_id=str(instance.id),
                    title=instance.title,
                    is_completed=instance.is_completed,
                    last_updated=instance.updated_at.isoformat()
                )
            transaction.on_commit(_publish_activity_updated)
            
    except Exception as e:
        logger.error(f"Error publishing activity event: {e}")


@receiver(post_delete, sender=PlanActivity)
def activity_post_delete(sender, instance, **kwargs):
    """Publish activity deletion event"""
    try:
        def _publish_activity_deleted():
            publish_activity_deleted(
                plan_id=str(instance.plan_id),
                activity_id=str(instance.id),
                title=instance.title
            )
        transaction.on_commit(_publish_activity_deleted)
        
    except Exception as e:
        logger.error(f"Error publishing activity deletion event: {e}")


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
