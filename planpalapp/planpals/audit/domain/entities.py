"""
Audit Domain - Pure Python entities and constants.

This module stays free of Django and DRF dependencies.
"""
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Any, Dict, Optional
from uuid import UUID


class AuditAction(str, Enum):
    CREATE_GROUP = 'CREATE_GROUP'
    UPDATE_GROUP = 'UPDATE_GROUP'
    CREATE_PLAN = 'CREATE_PLAN'
    UPDATE_PLAN = 'UPDATE_PLAN'
    DELETE_PLAN = 'DELETE_PLAN'
    COMPLETE_PLAN = 'COMPLETE_PLAN'
    CREATE_ACTIVITY = 'CREATE_ACTIVITY'
    UPDATE_ACTIVITY = 'UPDATE_ACTIVITY'
    CREATE_AVAILABILITY_POLL = 'CREATE_AVAILABILITY_POLL'
    CREATE_GROUP_POLL = 'CREATE_GROUP_POLL'
    CLOSE_GROUP_POLL = 'CLOSE_GROUP_POLL'
    START_LIVE_LOCATION = 'START_LIVE_LOCATION'
    STOP_LIVE_LOCATION = 'STOP_LIVE_LOCATION'
    CREATE_WORK_ITEM = 'CREATE_WORK_ITEM'
    UPDATE_WORK_ITEM = 'UPDATE_WORK_ITEM'
    CREATE_COMMENT = 'CREATE_COMMENT'
    PIN_COMMENT = 'PIN_COMMENT'
    UNPIN_COMMENT = 'UNPIN_COMMENT'
    CLONE_PLAN = 'CLONE_PLAN'
    UPDATE_BUDGET = 'UPDATE_BUDGET'
    CREATE_EXPENSE = 'CREATE_EXPENSE'
    UPDATE_EXPENSE = 'UPDATE_EXPENSE'
    DELETE_EXPENSE = 'DELETE_EXPENSE'
    SETTLEMENT_REQUESTED = 'SETTLEMENT_REQUESTED'
    SETTLEMENT_COMPLETED = 'SETTLEMENT_COMPLETED'
    SETTLEMENT_REJECTED = 'SETTLEMENT_REJECTED'
    JOIN_GROUP = 'JOIN_GROUP'
    LEAVE_GROUP = 'LEAVE_GROUP'
    ADD_MEMBER = 'ADD_MEMBER'
    REMOVE_MEMBER = 'REMOVE_MEMBER'
    CHANGE_ROLE = 'CHANGE_ROLE'
    GROUP_INVITE_CREATED = 'GROUP_INVITE_CREATED'
    GROUP_INVITE_REVOKED = 'GROUP_INVITE_REVOKED'
    GROUP_JOINED_VIA_INVITE = 'GROUP_JOINED_VIA_INVITE'
    GROUP_INVITE_FAILED = 'GROUP_INVITE_FAILED'
    GROUP_JOIN_REQUESTED = 'GROUP_JOIN_REQUESTED'
    GROUP_JOIN_REQUEST_APPROVED = 'GROUP_JOIN_REQUEST_APPROVED'
    GROUP_JOIN_REQUEST_REJECTED = 'GROUP_JOIN_REQUEST_REJECTED'
    DELETE_GROUP = 'DELETE_GROUP'
    NOTIFICATION_OPENED = 'NOTIFICATION_OPENED'

    @classmethod
    def values(cls) -> tuple[str, ...]:
        return tuple(action.value for action in cls)

    @classmethod
    def choices(cls) -> list[tuple[str, str]]:
        return [(action.value, action.value.replace('_', ' ').title()) for action in cls]


class AuditResourceType(str, Enum):
    PLAN = 'plan'
    ACTIVITY = 'activity'
    GROUP = 'group'
    MEMBERSHIP = 'membership'
    INVITE = 'invite'
    NOTIFICATION = 'notification'
    BUDGET = 'budget'
    EXPENSE = 'expense'
    CONVERSATION = 'conversation'

    @classmethod
    def values(cls) -> tuple[str, ...]:
        return tuple(resource_type.value for resource_type in cls)


@dataclass(frozen=True)
class AuditLog:
    id: UUID
    user_id: Optional[UUID]
    action: str
    resource_type: str
    resource_id: Optional[UUID]
    metadata: Dict[str, Any] = field(default_factory=dict)
    created_at: Optional[datetime] = None
