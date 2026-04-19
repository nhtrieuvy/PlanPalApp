"""
Notification domain entities.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from enum import Enum
from typing import Any
from uuid import UUID


class NotificationType(str, Enum):
    PLAN_REMINDER = 'PLAN_REMINDER'
    GROUP_JOIN = 'GROUP_JOIN'
    GROUP_INVITE = 'GROUP_INVITE'
    ROLE_CHANGED = 'ROLE_CHANGED'
    PLAN_UPDATED = 'PLAN_UPDATED'
    NEW_MESSAGE = 'NEW_MESSAGE'
    BUDGET_ALERT = 'BUDGET_ALERT'
    LARGE_EXPENSE = 'LARGE_EXPENSE'

    @classmethod
    def values(cls) -> list[str]:
        return [member.value for member in cls]

    @classmethod
    def choices(cls) -> list[tuple[str, str]]:
        return [(member.value, member.value.replace('_', ' ').title()) for member in cls]


@dataclass(frozen=True)
class Notification:
    id: UUID
    user_id: UUID
    type: str
    title: str
    message: str
    data: dict[str, Any]
    is_read: bool
    created_at: datetime
