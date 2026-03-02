"""
Groups Domain — Repository Interfaces
"""
from abc import ABC, abstractmethod
from typing import Optional, Any, List
from uuid import UUID


class GroupRepository(ABC):
    """Repository interface for Group aggregate root."""

    @abstractmethod
    def get_by_id(self, group_id: UUID) -> Optional[Any]:
        ...

    @abstractmethod
    def get_by_id_with_stats(self, group_id: UUID) -> Optional[Any]:
        ...

    @abstractmethod
    def exists(self, group_id: UUID) -> bool:
        ...

    @abstractmethod
    def save(self, group: Any) -> Any:
        ...

    @abstractmethod
    def delete(self, group_id: UUID) -> bool:
        ...

    @abstractmethod
    def get_user_groups(self, user_id: UUID) -> Any:
        """Get all groups where user is a member."""
        ...

    @abstractmethod
    def get_groups_created_by(self, user_id: UUID) -> Any:
        """Get groups created (admin) by a user."""
        ...

    @abstractmethod
    def search_groups(self, query: str, user_id: UUID) -> Any:
        """Search groups the user is a member of."""
        ...

    @abstractmethod
    def get_by_invite_code(self, invite_code: str) -> Optional[Any]:
        """Find a group by its invite code."""
        ...


class GroupMembershipRepository(ABC):
    """Repository interface for GroupMembership entities."""

    @abstractmethod
    def add_member(self, group_id: UUID, user_id: UUID, role: str = 'member') -> Any:
        """Add a user to a group."""
        ...

    @abstractmethod
    def remove_member(self, group_id: UUID, user_id: UUID) -> bool:
        """Remove a user from a group."""
        ...

    @abstractmethod
    def is_member(self, group_id: UUID, user_id: UUID) -> bool:
        ...

    @abstractmethod
    def is_admin(self, group_id: UUID, user_id: UUID) -> bool:
        ...

    @abstractmethod
    def get_role(self, group_id: UUID, user_id: UUID) -> Optional[str]:
        ...

    @abstractmethod
    def set_role(self, group_id: UUID, user_id: UUID, role: str) -> bool:
        """Change a member's role."""
        ...

    @abstractmethod
    def get_members(self, group_id: UUID) -> Any:
        """Get all members of a group."""
        ...

    @abstractmethod
    def get_admin_count(self, group_id: UUID) -> int:
        """Count admins in a group (for last-admin protection)."""
        ...

    @abstractmethod
    def get_membership(self, group_id: UUID, user_id: UUID) -> Optional[Any]:
        ...
