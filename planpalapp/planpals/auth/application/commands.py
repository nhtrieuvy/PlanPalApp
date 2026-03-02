"""
Auth Application — Command DTOs

Immutable command objects that represent user-initiated mutations
in the auth bounded context.
"""
from dataclasses import dataclass
from typing import Optional
from uuid import UUID


@dataclass(frozen=True)
class SendFriendRequestCommand:
    from_user_id: UUID
    to_user_id: UUID


@dataclass(frozen=True)
class AcceptFriendRequestCommand:
    current_user_id: UUID
    from_user_id: UUID


@dataclass(frozen=True)
class RejectFriendRequestCommand:
    current_user_id: UUID
    from_user_id: UUID


@dataclass(frozen=True)
class CancelFriendRequestCommand:
    current_user_id: UUID
    to_user_id: UUID


@dataclass(frozen=True)
class BlockUserCommand:
    blocker_id: UUID
    target_id: UUID


@dataclass(frozen=True)
class UnblockUserCommand:
    blocker_id: UUID
    target_id: UUID


@dataclass(frozen=True)
class UnfriendCommand:
    current_user_id: UUID
    target_user_id: UUID


@dataclass(frozen=True)
class SetOnlineStatusCommand:
    user_id: UUID
    is_online: bool


@dataclass(frozen=True)
class UpdateFCMTokenCommand:
    user_id: UUID
    token: Optional[str]
