"""
Auth Domain — Repository Interfaces
"""
from abc import ABC, abstractmethod
from typing import Optional, Any, List, Tuple, Dict
from uuid import UUID


class UserRepository(ABC):
    """Repository interface for User aggregate root."""

    @abstractmethod
    def get_by_id(self, user_id: UUID) -> Optional[Any]:
        ...

    @abstractmethod
    def get_by_id_with_counts(self, user_id: UUID) -> Optional[Any]:
        """Get user with annotated counts (friends, plans, groups)."""
        ...

    @abstractmethod
    def exists(self, user_id: UUID) -> bool:
        ...

    @abstractmethod
    def save(self, user: Any) -> Any:
        ...

    @abstractmethod
    def update_profile(self, user_id: UUID, data: Dict[str, Any]) -> Tuple[Any, bool]:
        """Update user profile fields. Returns (user, success)."""
        ...

    @abstractmethod
    def search(self, query: str, exclude_user_id: UUID = None) -> Any:
        """Search users by username, first_name, last_name, email."""
        ...

    @abstractmethod
    def get_friends_of(self, user_id: UUID) -> Any:
        """Get all friends of a user."""
        ...

    @abstractmethod
    def set_online_status(self, user_id: UUID, is_online: bool) -> bool:
        ...

    @abstractmethod
    def update_fcm_token(self, user_id: UUID, token: Optional[str]) -> bool:
        ...

    @abstractmethod
    def get_user_plans(self, user_id: UUID, plan_type: str = 'all') -> Any:
        """Get plans accessible to a user."""
        ...

    @abstractmethod
    def get_user_activities(self, user_id: UUID) -> Any:
        """Get activities from plans the user can view."""
        ...

    @abstractmethod
    def get_user_groups(self, user_id: UUID) -> Any:
        """Get groups the user is a member of, with stats."""
        ...

    @abstractmethod
    def get_recent_conversations(self, user_id: UUID) -> Any:
        """Get recent conversations for the user."""
        ...

    @abstractmethod
    def get_unread_messages_count(self, user_id: UUID) -> int:
        """Get total unread message count for a user."""
        ...


class FriendshipRepository(ABC):
    """Repository interface for Friendship aggregate."""

    @abstractmethod
    def get_friendship(self, user1_id: UUID, user2_id: UUID) -> Optional[Any]:
        """Get the friendship record between two users (if exists)."""
        ...

    @abstractmethod
    def create_friendship(self, user1_id: UUID, user2_id: UUID, initiator_id: UUID) -> Any:
        """Create a new friendship (pending state)."""
        ...

    @abstractmethod
    def update_status(self, friendship_id: UUID, new_status: str) -> Any:
        ...

    @abstractmethod
    def delete_friendship(self, friendship_id: UUID) -> bool:
        ...

    @abstractmethod
    def are_friends(self, user1_id: UUID, user2_id: UUID) -> bool:
        ...

    @abstractmethod
    def is_blocked(self, user1_id: UUID, user2_id: UUID) -> bool:
        """Check if either user has blocked the other."""
        ...

    @abstractmethod
    def get_pending_requests_for(self, user_id: UUID) -> Any:
        """Get pending friend requests received by a user."""
        ...

    @abstractmethod
    def get_sent_requests(self, user_id: UUID) -> Any:
        """Get pending friend requests sent by a user."""
        ...

    @abstractmethod
    def get_rejection_count(self, user1_id: UUID, user2_id: UUID) -> int:
        """Get number of times a friendship has been rejected (for cooldown)."""
        ...

    @abstractmethod
    def create_rejection(self, friendship_id: UUID, rejected_by_id: UUID) -> Any:
        """Create a FriendshipRejection record (validates and saves)."""
        ...

    @abstractmethod
    def reopen_as_pending(self, friendship_id: UUID, initiator_id: UUID) -> Any:
        """Set a rejected friendship back to pending with a new initiator."""
        ...

    @abstractmethod
    def block_friendship(self, friendship_id: UUID, blocker_id: UUID) -> Any:
        """Set an existing friendship to blocked status."""
        ...

    @abstractmethod
    def create_blocked_friendship(
        self, user1_id: UUID, user2_id: UUID, blocker_id: UUID
    ) -> Any:
        """Create a new friendship record with blocked status."""
        ...


class TokenRepository(ABC):
    """Repository interface for OAuth2 token management."""

    @abstractmethod
    def revoke_access_token(self, token_string: str, user_id: UUID) -> bool:
        """Revoke an access token and its associated refresh tokens. Returns True if revoked."""
        ...


class GroupRepository(ABC):
    """Cross-context repository for group queries used by auth service."""

    @abstractmethod
    def get_by_id(self, group_id: UUID) -> Optional[Any]:
        ...
