"""
Chat-specific realtime event publishers.
"""
from planpals.shared.events import RealtimeEvent, EventType, EventPriority
from planpals.shared.realtime_publisher import event_publisher


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
