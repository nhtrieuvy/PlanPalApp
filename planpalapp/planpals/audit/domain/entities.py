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
    CREATE_PLAN = 'CREATE_PLAN'
    UPDATE_PLAN = 'UPDATE_PLAN'
    DELETE_PLAN = 'DELETE_PLAN'
    COMPLETE_PLAN = 'COMPLETE_PLAN'
    UPDATE_BUDGET = 'UPDATE_BUDGET'
    CREATE_EXPENSE = 'CREATE_EXPENSE'
    JOIN_GROUP = 'JOIN_GROUP'
    LEAVE_GROUP = 'LEAVE_GROUP'
    CHANGE_ROLE = 'CHANGE_ROLE'
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
    GROUP = 'group'
    MEMBERSHIP = 'membership'
    NOTIFICATION = 'notification'
    BUDGET = 'budget'
    EXPENSE = 'expense'

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
