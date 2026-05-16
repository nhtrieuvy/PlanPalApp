"""
Groups Domain - Pure Python Entities, Value Objects & Constants.

This file is the innermost layer of Clean Architecture.
NO Django imports, NO ORM, NO REST framework.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from enum import Enum
from uuid import UUID


class MembershipRole(str, Enum):
    ADMIN = 'admin'
    PLAN_CREATOR = 'plan_creator'
    MEMBER = 'member'

    CHOICES = [
        ('admin', 'Administrator'),
        ('plan_creator', 'Plan creator'),
        ('member', 'Member'),
    ]


class GroupVisibility(str, Enum):
    PUBLIC = 'public'
    PRIVATE = 'private'


class GroupJoinRequestStatus(str, Enum):
    PENDING = 'pending'
    APPROVED = 'approved'
    REJECTED = 'rejected'


@dataclass(frozen=True)
class GroupInvite:
    id: UUID
    group_id: UUID
    token: str
    created_by_user_id: UUID
    expires_at: datetime | None
    max_uses: int | None
    current_uses: int
    is_active: bool
    created_at: datetime
    updated_at: datetime | None = None

    @property
    def remaining_uses(self) -> int | None:
        if self.max_uses is None:
            return None
        return max(self.max_uses - self.current_uses, 0)


@dataclass(frozen=True)
class GroupJoinRequest:
    id: UUID
    group_id: UUID
    user_id: UUID
    invite_id: UUID | None
    status: str
    reviewed_by_user_id: UUID | None
    reviewed_at: datetime | None
    created_at: datetime
    updated_at: datetime | None = None
