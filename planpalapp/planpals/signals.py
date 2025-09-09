"""
Django signals for automatic real-time event publishing
"""
import logging
from django.db.models.signals import post_save, post_delete, pre_save
from django.dispatch import receiver
from django.contrib.auth import get_user_model
from .models import Plan, PlanActivity, Group, GroupMembership, ChatMessage
from .events import RealtimeEvent, EventType
from .realtime_publisher import (
    event_publisher, 
    publish_plan_status_changed, 
    publish_activity_completed,
    publish_group_member_added
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
            event = RealtimeEvent(
                event_type=EventType.PLAN_CREATED,
                plan_id=str(instance.id),
                user_id=str(instance.creator_id),
                group_id=str(instance.group_id) if instance.group_id else None,
                data={
                    'plan_id': str(instance.id),
                    'title': instance.title,
                    'plan_type': instance.plan_type,
                    'status': instance.status,
                    'creator_id': str(instance.creator_id),
                    'group_id': str(instance.group_id) if instance.group_id else None,
                    'is_public': instance.is_public,
                    'start_date': instance.start_date.isoformat() if instance.start_date else None,
                    'end_date': instance.end_date.isoformat() if instance.end_date else None
                }
            )
            event_publisher.publish_event(event, send_push=False)  # Don't spam for new plans
            
        else:
            # Plan updated
            old_status = getattr(instance, '_old_status', None)
            
            # Check if status changed
            if old_status and old_status != instance.status:
                publish_plan_status_changed(
                    plan_id=str(instance.id),
                    old_status=old_status,
                    new_status=instance.status,
                    title=instance.title
                )
            
            # General plan update event (for non-status changes)
            elif not old_status or old_status == instance.status:
                event = RealtimeEvent(
                    event_type=EventType.PLAN_UPDATED,
                    plan_id=str(instance.id),
                    data={
                        'plan_id': str(instance.id),
                        'title': instance.title,
                        'status': instance.status,
                        'last_updated': instance.updated_at.isoformat()
                    }
                )
                event_publisher.publish_event(event, send_push=False)
                
    except Exception as e:
        logger.error(f"Error publishing plan event: {e}")


@receiver(post_delete, sender=Plan)
def plan_post_delete(sender, instance, **kwargs):
    """Publish plan deletion event"""
    try:
        event = RealtimeEvent(
            event_type=EventType.PLAN_DELETED,
            plan_id=str(instance.id),
            data={
                'plan_id': str(instance.id),
                'title': instance.title
            }
        )
        event_publisher.publish_event(event)
        
    except Exception as e:
        logger.error(f"Error publishing plan deletion event: {e}")


@receiver(post_save, sender=PlanActivity)
def activity_post_save(sender, instance, created, **kwargs):
    """Publish activity events after save"""
    try:
        if created:
            # New activity created
            event = RealtimeEvent(
                event_type=EventType.ACTIVITY_CREATED,
                plan_id=str(instance.plan_id),
                data={
                    'activity_id': str(instance.id),
                    'plan_id': str(instance.plan_id),
                    'title': instance.title,
                    'activity_type': instance.activity_type,
                    'start_time': instance.start_time.isoformat() if instance.start_time else None,
                    'end_time': instance.end_time.isoformat() if instance.end_time else None,
                    'location_name': instance.location_name,
                    'estimated_cost': float(instance.estimated_cost) if instance.estimated_cost else None
                }
            )
            event_publisher.publish_event(event, send_push=False)
            
        else:
            # Activity updated
            # Check if completion status changed
            if hasattr(instance, '_state') and instance._state.adding is False:
                try:
                    old_instance = PlanActivity.objects.get(pk=instance.pk)
                    if not old_instance.is_completed and instance.is_completed:
                        # Activity just completed
                        publish_activity_completed(
                            plan_id=str(instance.plan_id),
                            activity_id=str(instance.id),
                            title=instance.title
                        )
                        return
                except PlanActivity.DoesNotExist:
                    pass
            
            # General activity update
            event = RealtimeEvent(
                event_type=EventType.ACTIVITY_UPDATED,
                plan_id=str(instance.plan_id),
                data={
                    'activity_id': str(instance.id),
                    'plan_id': str(instance.plan_id),
                    'title': instance.title,
                    'is_completed': instance.is_completed,
                    'last_updated': instance.updated_at.isoformat()
                }
            )
            event_publisher.publish_event(event, send_push=False)
            
    except Exception as e:
        logger.error(f"Error publishing activity event: {e}")


@receiver(post_delete, sender=PlanActivity)
def activity_post_delete(sender, instance, **kwargs):
    """Publish activity deletion event"""
    try:
        event = RealtimeEvent(
            event_type=EventType.ACTIVITY_DELETED,
            plan_id=str(instance.plan_id),
            data={
                'activity_id': str(instance.id),
                'plan_id': str(instance.plan_id),
                'title': instance.title
            }
        )
        event_publisher.publish_event(event)
        
    except Exception as e:
        logger.error(f"Error publishing activity deletion event: {e}")


@receiver(post_save, sender=GroupMembership)
def group_membership_post_save(sender, instance, created, **kwargs):
    """Publish group membership events"""
    try:
        if created:
            # New member added
            publish_group_member_added(
                group_id=str(instance.group_id),
                member_id=str(instance.user_id),
                member_name=instance.user.get_full_name() or instance.user.username,
                group_name=instance.group.name
            )
        else:
            # Role changed
            event = RealtimeEvent(
                event_type=EventType.GROUP_ROLE_CHANGED,
                group_id=str(instance.group_id),
                data={
                    'member_id': str(instance.user_id),
                    'member_name': instance.user.get_full_name() or instance.user.username,
                    'group_name': instance.group.name,
                    'new_role': instance.role
                }
            )
            event_publisher.publish_event(event)
            
    except Exception as e:
        logger.error(f"Error publishing group membership event: {e}")


@receiver(post_delete, sender=GroupMembership)
def group_membership_post_delete(sender, instance, **kwargs):
    """Publish group member removal event"""
    try:
        event = RealtimeEvent(
            event_type=EventType.GROUP_MEMBER_REMOVED,
            group_id=str(instance.group_id),
            data={
                'member_id': str(instance.user_id),
                'member_name': instance.user.get_full_name() or instance.user.username,
                'group_name': instance.group.name
            }
        )
        event_publisher.publish_event(event)
        
    except Exception as e:
        logger.error(f"Error publishing group member removal event: {e}")


@receiver(post_save, sender=ChatMessage)
def chat_message_post_save(sender, instance, created, **kwargs):
    """Publish chat message events"""
    try:
        if created and not instance.is_deleted:
            # New message sent
            event = RealtimeEvent(
                event_type=EventType.MESSAGE_SENT,
                group_id=str(instance.conversation.group_id) if hasattr(instance.conversation, 'group_id') else None,
                data={
                    'message_id': str(instance.id),
                    'conversation_id': str(instance.conversation_id),
                    'sender_id': str(instance.sender_id),
                    'sender_name': instance.sender.get_full_name() or instance.sender.username,
                    'content': instance.content[:100],  # Truncate for privacy
                    'timestamp': instance.created_at.isoformat(),
                    'message_type': getattr(instance, 'message_type', 'text')
                }
            )
            event_publisher.publish_event(event)
            
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
                event_type = EventType.USER_ONLINE if new_online else EventType.USER_OFFLINE
                event = RealtimeEvent(
                    event_type=event_type,
                    user_id=str(instance.id),
                    data={
                        'user_id': str(instance.id),
                        'username': instance.username,
                        'is_online': new_online,
                        'last_seen': instance.last_seen.isoformat() if instance.last_seen else None
                    }
                )
                
                # Broadcast to user's friends and groups
                event_publisher.publish_event(event, send_push=False)
                
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
