"""
Auth-related realtime event publishers for user online/offline and friend requests.
"""
import logging
from planpals.shared.events import RealtimeEvent, EventType, EventPriority
from planpals.shared.realtime_publisher import event_publisher

logger = logging.getLogger(__name__)


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
