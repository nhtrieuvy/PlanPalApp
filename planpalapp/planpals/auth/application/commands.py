"""
Auth Application — Command DTOs

Immutable command objects that represent user-initiated mutations
in the auth bounded context.
"""
from dataclasses import dataclass
from typing import Optional
from uuid import UUID

from planpals.shared.interfaces import BaseCommand


@dataclass(frozen=True)
class SendFriendRequestCommand(BaseCommand):
    from_user_id: UUID
    to_user_id: UUID


@dataclass(frozen=True)
class AcceptFriendRequestCommand(BaseCommand):
    current_user_id: UUID
    from_user_id: UUID


@dataclass(frozen=True)
class RejectFriendRequestCommand(BaseCommand):
    current_user_id: UUID
    from_user_id: UUID


@dataclass(frozen=True)
class CancelFriendRequestCommand(BaseCommand):
    current_user_id: UUID
    to_user_id: UUID


@dataclass(frozen=True)
class BlockUserCommand(BaseCommand):
    blocker_id: UUID
    target_id: UUID


@dataclass(frozen=True)
class UnblockUserCommand(BaseCommand):
    blocker_id: UUID
    target_id: UUID


@dataclass(frozen=True)
class UnfriendCommand(BaseCommand):
    current_user_id: UUID
    target_user_id: UUID


@dataclass(frozen=True)
class SetOnlineStatusCommand(BaseCommand):
    user_id: UUID
    is_online: bool


@dataclass(frozen=True)
class UpdateFCMTokenCommand(BaseCommand):
    user_id: UUID
    token: Optional[str]
