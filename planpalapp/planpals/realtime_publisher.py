"""
Event publisher service for broadcasting real-time events
"""
import json
import logging
from typing import List, Optional, Dict, Any
from django.core.cache import cache
from django.conf import settings
from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from .events import RealtimeEvent, EventType, ChannelGroups, EventPriority
from .integrations.notification_service import NotificationService

logger = logging.getLogger(__name__)


class RealtimeEventPublisher:
    """Service for publishing real-time events to WebSocket clients and push notifications"""
    
    def __init__(self):
        self.channel_layer = get_channel_layer()
        self.notification_service = NotificationService()
        
    def publish_event(self, event: RealtimeEvent, 
                     channel_groups: List[str] = None,
                     priority: EventPriority = EventPriority.NORMAL,
                     send_push: bool = True) -> bool:
        """
        Publish event to specified channel groups and optionally send push notifications
        
        Args:
            event: The event to publish
            channel_groups: List of channel groups to send to
            priority: Event priority level
            send_push: Whether to send push notifications
            
        Returns:
            bool: Success status
        """
        try:
            # Default channel groups based on event context
            if channel_groups is None:
                channel_groups = self._get_default_channels(event)
                
            success = True
            
            # Send to WebSocket channels
            for group_name in channel_groups:
                ws_success = self._send_to_websocket(group_name, event)
                if not ws_success:
                    success = False
                    
            # Send push notifications if enabled
            if send_push and self._should_send_push(event):
                push_success = self._send_push_notification(event)
                if not push_success:
                    logger.warning(f"Push notification failed for event {event.event_id}")
                    
            # Cache event for offline users
            self._cache_event_for_offline_users(event, channel_groups)
            
            # Log event for monitoring
            self._log_event(event, channel_groups, success)
            
            return success
            
        except Exception as e:
            logger.error(f"Failed to publish event {event.event_id}: {e}")
            return False
            
    def _get_default_channels(self, event: RealtimeEvent) -> List[str]:
        """Get default channel groups based on event context"""
        channels = []
        
        # Plan-specific events
        if event.plan_id:
            channels.append(ChannelGroups.plan(event.plan_id))
            
        # Group-specific events
        if event.group_id:
            channels.append(ChannelGroups.group(event.group_id))
            
        # User-specific events
        if event.user_id:
            channels.append(ChannelGroups.user(event.user_id))
            
        # System-wide events
        if event.event_type in [EventType.SYSTEM_MAINTENANCE, EventType.SYSTEM_NOTIFICATION]:
            channels.append(ChannelGroups.system())
            
        return channels
        
    def _send_to_websocket(self, group_name: str, event: RealtimeEvent) -> bool:
        """Send event to WebSocket channel group"""
        try:
            if not self.channel_layer:
                logger.warning("Channel layer not available, skipping WebSocket broadcast")
                return False
                
            # Send event to channel group
            async_to_sync(self.channel_layer.group_send)(
                group_name,
                {
                    'type': 'event.message',
                    'data': event.to_dict()
                }
            )
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to send WebSocket event to {group_name}: {e}")
            return False
            
    def _should_send_push(self, event: RealtimeEvent) -> bool:
        """Determine if event should trigger push notifications"""
        # High priority events should always send push
        if event.data.get('priority') == EventPriority.HIGH.value:
            return True
            
        # Send push for important plan and activity events
        important_events = [
            EventType.PLAN_STATUS_CHANGED,
            EventType.ACTIVITY_CREATED,
            EventType.ACTIVITY_UPDATED,
            EventType.ACTIVITY_COMPLETED,
            EventType.ACTIVITY_DELETED,
            EventType.GROUP_MEMBER_ADDED,
            EventType.MESSAGE_SENT,
            EventType.FRIEND_REQUEST
        ]
        
        return event.event_type in important_events
        
    def _send_push_notification(self, event: RealtimeEvent) -> bool:
        """Send push notification for event"""
        try:
            # Get notification details based on event type
            notification_data = self._get_notification_data(event)
            if not notification_data:
                return True  # No notification needed
                
            # Get target users for notification
            target_users = self._get_notification_targets(event)
            if not target_users:
                return True  # No targets
                
            # Get FCM tokens for target users
            fcm_tokens = self._get_fcm_tokens(target_users)
            if not fcm_tokens:
                return True  # No valid tokens
                
            # Send push notification
            success = self.notification_service.send_push_notification(
                fcm_tokens=fcm_tokens,
                title=notification_data['title'],
                body=notification_data['body'],
                data={
                    'event_type': event.event_type.value,
                    'event_id': event.event_id,
                    'plan_id': event.plan_id,
                    'group_id': event.group_id,
                    **notification_data.get('extra_data', {})
                }
            )
            
            return success
            
        except Exception as e:
            logger.error(f"Failed to send push notification: {e}")
            return False
            
    def _get_notification_data(self, event: RealtimeEvent) -> Optional[Dict[str, Any]]:
        """Get notification title and body based on event type"""
        event_data = event.data
        
        notification_map = {
            EventType.PLAN_STATUS_CHANGED: {
                'title': f"Plan Status Updated",
                'body': f"'{event_data.get('title', 'Your plan')}' is now {event_data.get('new_status', 'updated')}"
            },
            EventType.ACTIVITY_CREATED: {
                'title': f"New Activity Added",
                'body': f"{event_data.get('created_by', 'Someone')} added '{event_data.get('activity_title', 'an activity')}' to {event_data.get('plan_title', 'the plan')}"
            },
            EventType.ACTIVITY_UPDATED: {
                'title': f"Activity Updated",
                'body': f"{event_data.get('updated_by', 'Someone')} updated '{event_data.get('activity_title', 'an activity')}' in {event_data.get('plan_title', 'the plan')}"
            },
            EventType.ACTIVITY_COMPLETED: {
                'title': f"Activity Completed",
                'body': f"{event_data.get('completed_by', 'Someone')} completed '{event_data.get('activity_title', 'an activity')}' in {event_data.get('plan_title', 'the plan')}"
            },
            EventType.ACTIVITY_DELETED: {
                'title': f"Activity Removed",
                'body': f"{event_data.get('deleted_by', 'Someone')} removed '{event_data.get('activity_title', 'an activity')}' from {event_data.get('plan_title', 'the plan')}"
            },
            EventType.GROUP_MEMBER_ADDED: {
                'title': f"New Group Member",
                'body': f"{event_data.get('member_name', 'Someone')} joined {event_data.get('group_name', 'the group')}"
            },
            EventType.MESSAGE_SENT: {
                'title': f"New Message",
                'body': f"{event_data.get('sender_name', 'Someone')}: {event_data.get('content', 'Sent a message')[:50]}..."
            },
            EventType.FRIEND_REQUEST: {
                'title': f"Friend Request",
                'body': f"{event_data.get('from_name', 'Someone')} sent you a friend request"
            }
        }
        
        return notification_map.get(event.event_type)
        
    def _get_notification_targets(self, event: RealtimeEvent) -> List[str]:
        """Get list of user IDs that should receive notifications"""
        from .models import Plan, Group, User  # Import here to avoid circular imports
        
        target_users = []
        
        try:
            # Plan events - notify all plan members except the initiator
            if event.plan_id:
                plan = Plan.objects.get(id=event.plan_id)
                if plan.plan_type == 'personal':
                    target_users.append(str(plan.creator_id))
                elif plan.group:
                    target_users.extend([str(uid) for uid in plan.group.members.values_list('id', flat=True)])
                    
            # Group events - notify all group members
            elif event.group_id:
                group = Group.objects.get(id=event.group_id)
                target_users.extend([str(uid) for uid in group.members.values_list('id', flat=True)])
                
            # User events - notify specific user
            elif event.user_id:
                target_users.append(event.user_id)
                
            # Remove the event initiator from notifications (they already know)
            event_initiator = event.data.get('initiator_id')
            if event_initiator and event_initiator in target_users:
                target_users.remove(event_initiator)
                
        except Exception as e:
            logger.error(f"Failed to get notification targets: {e}")
            
        return list(set(target_users))  # Remove duplicates
        
    def _get_fcm_tokens(self, user_ids: List[str]) -> List[str]:
        """Get FCM tokens for list of user IDs"""
        from .models import User  # Import here to avoid circular imports
        
        try:
            tokens = User.objects.filter(
                id__in=user_ids,
                fcm_token__isnull=False
            ).exclude(fcm_token='').values_list('fcm_token', flat=True)
            
            return list(tokens)
            
        except Exception as e:
            logger.error(f"Failed to get FCM tokens: {e}")
            return []
            
    def _cache_event_for_offline_users(self, event: RealtimeEvent, channel_groups: List[str]):
        """Cache event for users who are offline"""
        try:
            # For user-specific events, cache for offline users
            if event.user_id:
                cache_key = f"offline_events:{event.user_id}"
                cached_events = cache.get(cache_key, [])
                cached_events.append(event.to_dict())
                
                # Keep only last 50 events per user
                if len(cached_events) > 50:
                    cached_events = cached_events[-50:]
                    
                cache.set(cache_key, cached_events, timeout=86400)  # 24 hours
                
        except Exception as e:
            logger.error(f"Failed to cache event for offline users: {e}")
            
    def _log_event(self, event: RealtimeEvent, channel_groups: List[str], success: bool):
        """Log event for monitoring and debugging"""
        logger.info(
            f"Event published: {event.event_type.value} "
            f"(ID: {event.event_id}, Success: {success}) "
            f"to groups: {', '.join(channel_groups)}"
        )
        
        # Optionally send to monitoring service
        if hasattr(settings, 'MONITORING_ENABLED') and settings.MONITORING_ENABLED:
            # Send metrics to monitoring service
            pass


# Singleton instance for easy importing
event_publisher = RealtimeEventPublisher()


# Convenience functions for common event types
def publish_plan_status_changed(plan_id: str, old_status: str, new_status: str, 
                               title: str, initiator_id: str = None):
    """Publish plan status change event"""
    event = RealtimeEvent(
        event_type=EventType.PLAN_STATUS_CHANGED,
        plan_id=plan_id,
        data={
            'plan_id': plan_id,
            'title': title,
            'old_status': old_status,
            'new_status': new_status,
            'initiator_id': initiator_id
        }
    )
    
    return event_publisher.publish_event(event, priority=EventPriority.HIGH)


def publish_activity_completed(plan_id: str, activity_id: str, title: str, 
                              completed_by: str = None):
    """Publish activity completion event"""
    event = RealtimeEvent(
        event_type=EventType.ACTIVITY_COMPLETED,
        plan_id=plan_id,
        data={
            'activity_id': activity_id,
            'title': title,
            'completed_by': completed_by,
            'initiator_id': completed_by
        }
    )
    
    return event_publisher.publish_event(event, priority=EventPriority.NORMAL)


def publish_group_member_added(group_id: str, member_id: str, member_name: str,
                               group_name: str, added_by: str = None):
    """Publish group member added event"""
    event = RealtimeEvent(
        event_type=EventType.GROUP_MEMBER_ADDED,
        group_id=group_id,
        data={
            'member_id': member_id,
            'member_name': member_name,
            'group_name': group_name,
            'added_by': added_by,
            'initiator_id': added_by
        }
    )
    
    return event_publisher.publish_event(event, priority=EventPriority.NORMAL)


def publish_activity_created(plan_id: str, activity_id: str, activity_title: str, 
                           plan_title: str, created_by: str = None):
    """Publish activity created event"""
    event = RealtimeEvent(
        event_type=EventType.ACTIVITY_CREATED,
        plan_id=plan_id,
        data={
            'activity_id': activity_id,
            'activity_title': activity_title,
            'plan_title': plan_title,
            'created_by': created_by,
            'initiator_id': created_by
        }
    )
    
    return event_publisher.publish_event(event, priority=EventPriority.NORMAL)


def publish_activity_updated(plan_id: str, activity_id: str, activity_title: str,
                           plan_title: str, updated_by: str = None):
    """Publish activity updated event"""
    event = RealtimeEvent(
        event_type=EventType.ACTIVITY_UPDATED,
        plan_id=plan_id,
        data={
            'activity_id': activity_id,
            'activity_title': activity_title,
            'plan_title': plan_title,
            'updated_by': updated_by,
            'initiator_id': updated_by
        }
    )
    
    return event_publisher.publish_event(event, priority=EventPriority.NORMAL)


def publish_activity_deleted(plan_id: str, activity_id: str, activity_title: str,
                           plan_title: str, deleted_by: str = None):
    """Publish activity deleted event"""
    event = RealtimeEvent(
        event_type=EventType.ACTIVITY_DELETED,
        plan_id=plan_id,
        data={
            'activity_id': activity_id,
            'activity_title': activity_title,
            'plan_title': plan_title,
            'deleted_by': deleted_by,
            'initiator_id': deleted_by
        }
    )
    
    return event_publisher.publish_event(event, priority=EventPriority.NORMAL)


def publish_message_sent(group_id: str, message_id: str, content: str,
                        sender_name: str, sender_id: str = None):
    """Publish message sent event"""
    event = RealtimeEvent(
        event_type=EventType.MESSAGE_SENT,
        group_id=group_id,
        data={
            'message_id': message_id,
            'content': content,
            'sender_name': sender_name,
            'sender_id': sender_id,
            'initiator_id': sender_id
        }
    )
    
    return event_publisher.publish_event(event, priority=EventPriority.NORMAL)


def publish_friend_request(user_id: str, from_user_id: str, from_name: str):
    """Publish friend request event"""
    event = RealtimeEvent(
        event_type=EventType.FRIEND_REQUEST,
        user_id=user_id,
        data={
            'from_user_id': from_user_id,
            'from_name': from_name,
            'initiator_id': from_user_id
        }
    )
    
    return event_publisher.publish_event(event, priority=EventPriority.HIGH)
