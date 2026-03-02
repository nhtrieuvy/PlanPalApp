"""
Group-specific real-time event publishers.
"""
from planpals.shared.events import RealtimeEvent, EventType, EventPriority
from planpals.shared.realtime_publisher import event_publisher


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
