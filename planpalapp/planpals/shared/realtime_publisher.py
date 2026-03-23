
import json
import logging
from typing import List, Optional, Dict, Any
from django.core.cache import cache
from django.conf import settings
from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from planpals.shared.events import RealtimeEvent, EventType, ChannelGroups, EventPriority

logger = logging.getLogger(__name__)


class RealtimeEventPublisher:    
    def __init__(self):
        self.channel_layer = get_channel_layer()
        
    def publish_event(self, event: RealtimeEvent, 
                     channel_groups: List[str] = None,
                     priority: EventPriority = EventPriority.NORMAL,
                     send_push: bool = True) -> bool:
        try:
            if channel_groups is None:
                channel_groups = self._get_default_channels(event)
                
            success = True
            
            for group_name in channel_groups:
                ws_success = self._send_to_websocket(group_name, event)
                if not ws_success:
                    success = False
                    
            if send_push and self._should_send_push(event):
                push_success = self._send_push_notification(event)
                if not push_success:
                    logger.warning(f"Push notification failed for event {event.event_id}")
                    
            self._cache_event_for_offline_users(event, channel_groups)
            
            self._log_event(event, channel_groups, success)
            
            return success
            
        except Exception as e:
            logger.error(f"Failed to publish event {event.event_id}: {e}")
            return False
            
    def _get_default_channels(self, event: RealtimeEvent) -> List[str]:
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
        if event.data.get('priority') == EventPriority.HIGH.value:
            return True
            
        important_events = [
            EventType.PLAN_CREATED,
            EventType.PLAN_UPDATED,
            EventType.PLAN_STATUS_CHANGED,
            EventType.ACTIVITY_CREATED,
            EventType.ACTIVITY_UPDATED,
            EventType.ACTIVITY_COMPLETED,
            EventType.ACTIVITY_DELETED,
            EventType.GROUP_MEMBER_ADDED,
            EventType.GROUP_MEMBER_REMOVED,
            EventType.MESSAGE_SENT,
            EventType.FRIEND_REQUEST,
            EventType.FRIEND_REQUEST_ACCEPTED
        ]
        
        return event.event_type in important_events
        
    def _send_push_notification(self, event: RealtimeEvent) -> bool:
        """Dispatch push notification via Celery task (async, off hot path)."""
        try:
            from planpals.shared.tasks import send_event_push_notification_task

            # Serialize event to plain dict — Celery tasks only accept
            # JSON-serialisable primitives.
            send_event_push_notification_task.delay(event.to_dict())
            return True

        except Exception as e:
            logger.error(f"Failed to dispatch push notification task: {e}")
            return False
            
    def _cache_event_for_offline_users(self, event: RealtimeEvent, channel_groups: List[str]):
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

# Plan Event Helpers
def publish_plan_created(plan_id: str, title: str, plan_type: str, status: str,
                        creator_id: str, group_id: str = None, is_public: bool = False,
                        start_date: str = None, end_date: str = None):
    """Publish plan created event"""
    event = RealtimeEvent(
        event_type=EventType.PLAN_CREATED,
        plan_id=plan_id,
        user_id=creator_id,
        group_id=group_id,
        data={
            'plan_id': plan_id,
            'title': title,
            'plan_type': plan_type,
            'status': status,
            'creator_id': creator_id,
            'group_id': group_id,
            'is_public': is_public,
            'start_date': start_date,
            'end_date': end_date,
            'initiator_id': creator_id
        }
    )
    
    return event_publisher.publish_event(event, send_push=False)  # Don't spam for new plans


def publish_plan_updated(plan_id: str, title: str, status: str, last_updated: str):
    """Publish plan updated event"""
    event = RealtimeEvent(
        event_type=EventType.PLAN_UPDATED,
        plan_id=plan_id,
        data={
            'plan_id': plan_id,
            'title': title,
            'status': status,
            'last_updated': last_updated
        }
    )
    
    return event_publisher.publish_event(event, send_push=False)


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


def publish_plan_deleted(plan_id: str, title: str):
    """Publish plan deleted event"""
    event = RealtimeEvent(
        event_type=EventType.PLAN_DELETED,
        plan_id=plan_id,
        data={
            'plan_id': plan_id,
            'title': title
        }
    )
    
    return event_publisher.publish_event(event)


# Activity Event Helpers
def publish_activity_created(plan_id: str, activity_id: str, title: str, activity_type: str,
                           start_time: str = None, end_time: str = None, 
                           location_name: str = None, estimated_cost: float = None):
    """Publish activity created event"""
    event = RealtimeEvent(
        event_type=EventType.ACTIVITY_CREATED,
        plan_id=plan_id,
        data={
            'activity_id': activity_id,
            'plan_id': plan_id,
            'title': title,
            'activity_type': activity_type,
            'start_time': start_time,
            'end_time': end_time,
            'location_name': location_name,
            'estimated_cost': estimated_cost
        }
    )
    
    return event_publisher.publish_event(event)


def publish_activity_updated(plan_id: str, activity_id: str, title: str, 
                           is_completed: bool, last_updated: str):
    """Publish activity updated event"""
    event = RealtimeEvent(
        event_type=EventType.ACTIVITY_UPDATED,
        plan_id=plan_id,
        data={
            'activity_id': activity_id,
            'plan_id': plan_id,
            'title': title,
            'is_completed': is_completed,
            'last_updated': last_updated
        }
    )
    
    return event_publisher.publish_event(event)


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


def publish_activity_deleted(plan_id: str, activity_id: str, title: str):
    """Publish activity deleted event"""
    event = RealtimeEvent(
        event_type=EventType.ACTIVITY_DELETED,
        plan_id=plan_id,
        data={
            'activity_id': activity_id,
            'plan_id': plan_id,
            'title': title
        }
    )
    
    return event_publisher.publish_event(event)


# Group Event Helpers
def publish_group_member_added(group_id: str, user_id: str, username: str, role: str,
                               group_name: str = None, added_by: str = None):
    """Publish group member added event"""
    event = RealtimeEvent(
        event_type=EventType.GROUP_MEMBER_ADDED,
        group_id=group_id,
        data={
            'group_id': group_id,
            'user_id': user_id,
            'username': username,
            'role': role,
            'group_name': group_name,
            'added_by': added_by,
            'initiator_id': added_by
        }
    )
    
    return event_publisher.publish_event(event)


def publish_group_member_removed(group_id: str, user_id: str, username: str, 
                                group_name: str = None):
    """Publish group member removed event"""
    event = RealtimeEvent(
        event_type=EventType.GROUP_MEMBER_REMOVED,
        group_id=group_id,
        data={
            'group_id': group_id,
            'user_id': user_id,
            'username': username,
            'group_name': group_name
        }
    )
    
    return event_publisher.publish_event(event)


def publish_group_role_changed(group_id: str, user_id: str, username: str, 
                              new_role: str, group_name: str = None):
    """Publish group role changed event"""
    event = RealtimeEvent(
        event_type=EventType.GROUP_ROLE_CHANGED,
        group_id=group_id,
        data={
            'group_id': group_id,
            'user_id': user_id,
            'username': username,
            'new_role': new_role,
            'group_name': group_name
        }
    )
    
    return event_publisher.publish_event(event)


# Chat Event Helpers
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


# User Event Helpers
def publish_user_online(user_id: str, username: str, last_seen: str = None):
    """Publish user online event"""
    event = RealtimeEvent(
        event_type=EventType.USER_ONLINE,
        user_id=user_id,
        data={
            'user_id': user_id,
            'username': username,
            'is_online': True,
            'last_seen': last_seen
        }
    )
    
    return event_publisher.publish_event(event, send_push=False)


def publish_user_offline(user_id: str, username: str, last_seen: str = None):
    """Publish user offline event"""
    event = RealtimeEvent(
        event_type=EventType.USER_OFFLINE,
        user_id=user_id,
        data={
            'user_id': user_id,
            'username': username,
            'is_online': False,
            'last_seen': last_seen
        }
    )
    
    return event_publisher.publish_event(event, send_push=False)


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


def publish_friend_request_accepted(user_id: str, accepter_id: str, accepter_name: str):
    """Publish friend request accepted event"""
    event = RealtimeEvent(
        event_type=EventType.FRIEND_REQUEST_ACCEPTED,
        user_id=user_id,
        data={
            'accepter_id': accepter_id,
            'accepter_name': accepter_name,
            'initiator_id': accepter_id
        }
    )
    
    return event_publisher.publish_event(event, priority=EventPriority.HIGH)
