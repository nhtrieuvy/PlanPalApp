"""
Event definitions and constants for real-time system
"""
from enum import Enum
from dataclasses import dataclass
from typing import Dict, Any, Optional
from django.utils import timezone
import uuid


class EventType(Enum):
    """Event types for real-time system"""
    
    # Plan Events
    PLAN_STATUS_CHANGED = 'plan.status_changed'
    PLAN_CREATED = 'plan.created'
    PLAN_UPDATED = 'plan.updated'
    PLAN_DELETED = 'plan.deleted'
    
    # Activity Events
    ACTIVITY_CREATED = 'activity.created'
    ACTIVITY_UPDATED = 'activity.updated'
    ACTIVITY_COMPLETED = 'activity.completed'
    ACTIVITY_DELETED = 'activity.deleted'
    
    # Group Events
    GROUP_MEMBER_ADDED = 'group.member_added'
    GROUP_MEMBER_REMOVED = 'group.member_removed'
    GROUP_ROLE_CHANGED = 'group.role_changed'
    
    # Chat Events
    MESSAGE_SENT = 'chat.message_sent'
    MESSAGE_UPDATED = 'chat.message_updated'
    MESSAGE_DELETED = 'chat.message_deleted'
    
    # User Events
    USER_ONLINE = 'user.online'
    USER_OFFLINE = 'user.offline'
    FRIEND_REQUEST = 'user.friend_request'
    
    # System Events
    SYSTEM_MAINTENANCE = 'system.maintenance'
    SYSTEM_NOTIFICATION = 'system.notification'


@dataclass
class RealtimeEvent:
    """Standardized event structure for real-time communications"""
    
    event_type: EventType
    data: Dict[str, Any]
    timestamp: str = None
    event_id: str = None
    user_id: str = None
    plan_id: str = None
    group_id: str = None
    
    def __post_init__(self):
        if self.timestamp is None:
            self.timestamp = timezone.now().isoformat()
        if self.event_id is None:
            self.event_id = str(uuid.uuid4())
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert event to dictionary for JSON serialization"""
        return {
            'event_type': self.event_type.value,
            'event_id': self.event_id,
            'timestamp': self.timestamp,
            'user_id': self.user_id,
            'plan_id': self.plan_id,
            'group_id': self.group_id,
            'data': self.data
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'RealtimeEvent':
        """Create event from dictionary"""
        return cls(
            event_type=EventType(data['event_type']),
            data=data['data'],
            timestamp=data.get('timestamp'),
            event_id=data.get('event_id'),
            user_id=data.get('user_id'),
            plan_id=data.get('plan_id'),
            group_id=data.get('group_id')
        )


# Channel group naming conventions
class ChannelGroups:
    """Standard channel group names for different types of updates"""
    
    @staticmethod
    def plan(plan_id: str) -> str:
        """Channel group for specific plan updates"""
        return f"plan_{plan_id}"
    
    @staticmethod
    def group(group_id: str) -> str:
        """Channel group for specific group updates"""
        return f"group_{group_id}"
    
    @staticmethod
    def user(user_id: str) -> str:
        """Channel group for specific user updates"""
        return f"user_{user_id}"
    
    @staticmethod
    def notifications() -> str:
        """Channel group for general notifications"""
        return "notifications"
    
    @staticmethod
    def system() -> str:
        """Channel group for system-wide announcements"""
        return "system"


# Event priority levels
class EventPriority(Enum):
    """Priority levels for events - affects delivery guarantees"""
    LOW = 'low'          # Best effort, can be dropped if queue full
    NORMAL = 'normal'    # Standard delivery 
    HIGH = 'high'        # Important updates, retry on failure
    CRITICAL = 'critical' # Must be delivered, persist until acknowledged
