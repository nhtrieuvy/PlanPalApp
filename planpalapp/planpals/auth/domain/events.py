"""
Auth Domain — Domain Events
"""
from dataclasses import dataclass
from typing import Optional

from planpals.shared.interfaces import DomainEvent


@dataclass(frozen=True)
class UserOnline(DomainEvent):
    user_id: str
    username: str
    last_seen: Optional[str] = None


@dataclass(frozen=True)
class UserOffline(DomainEvent):
    user_id: str
    username: str
    last_seen: Optional[str] = None


@dataclass(frozen=True)
class FriendRequestSent(DomainEvent):
    user_id: str  # target (who receives the request)
    from_user_id: str
    from_name: str


@dataclass(frozen=True)
class FriendRequestAccepted(DomainEvent):
    user_id: str  # original requester (who gets notified)
    accepter_id: str
    accepter_name: str
