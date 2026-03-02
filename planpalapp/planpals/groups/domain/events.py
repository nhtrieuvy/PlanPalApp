"""
Groups Domain — Domain Events
"""
from dataclasses import dataclass
from typing import Optional

from planpals.shared.interfaces import DomainEvent


@dataclass(frozen=True)
class GroupMemberAdded(DomainEvent):
    group_id: str
    user_id: str
    username: str
    role: str
    group_name: Optional[str] = None
    added_by: Optional[str] = None


@dataclass(frozen=True)
class GroupMemberRemoved(DomainEvent):
    group_id: str
    user_id: str
    username: str
    group_name: Optional[str] = None


@dataclass(frozen=True)
class GroupRoleChanged(DomainEvent):
    group_id: str
    user_id: str
    username: str
    new_role: str
    group_name: Optional[str] = None
