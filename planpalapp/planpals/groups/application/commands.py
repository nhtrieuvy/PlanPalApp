"""
Groups Application — Commands

Immutable data transfer objects for group mutations.
"""
from dataclasses import dataclass
from typing import Optional
from uuid import UUID

from planpals.shared.interfaces import BaseCommand


@dataclass(frozen=True)
class CreateGroupCommand(BaseCommand):
    admin_id: UUID
    name: str
    description: str = ''
    initial_member_ids: tuple = ()  # frozen needs immutable types
    avatar: Optional[str] = None
    cover_image: Optional[str] = None


@dataclass(frozen=True)
class UpdateGroupCommand(BaseCommand):
    group_id: UUID
    user_id: UUID
    name: Optional[str] = None
    description: Optional[str] = None
    avatar: Optional[str] = None
    cover_image: Optional[str] = None


@dataclass(frozen=True)
class AddMemberCommand(BaseCommand):
    group_id: UUID
    user_id: UUID  # who is adding
    target_user_id: UUID  # who is being added


@dataclass(frozen=True)
class RemoveMemberCommand(BaseCommand):
    group_id: UUID
    user_id: UUID  # who is removing
    target_user_id: UUID  # who is being removed


@dataclass(frozen=True)
class JoinGroupCommand(BaseCommand):
    """Command for a user to join a group by explicit group ID."""
    group_id: UUID
    user_id: UUID


@dataclass(frozen=True)
class LeaveGroupCommand(BaseCommand):
    group_id: UUID
    user_id: UUID


@dataclass(frozen=True)
class PromoteMemberCommand(BaseCommand):
    group_id: UUID
    user_id: UUID  # admin performing the action
    target_user_id: UUID


@dataclass(frozen=True)
class DemoteMemberCommand(BaseCommand):
    group_id: UUID
    user_id: UUID
    target_user_id: UUID
