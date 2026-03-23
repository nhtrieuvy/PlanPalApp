"""
Chat Domain — Repository Interfaces
"""
from abc import ABC, abstractmethod
from typing import Optional, Any, List, Dict, Tuple
from uuid import UUID


class ConversationRepository(ABC):
    """Repository interface for Conversation aggregate root."""

    @abstractmethod
    def get_by_id(self, conversation_id: UUID) -> Optional[Any]:
        ...

    @abstractmethod
    def get_user_conversations(self, user_id: UUID) -> Any:
        """Get all conversations for a user, with last_message annotation."""
        ...

    @abstractmethod
    def search_conversations(self, user_id: UUID, query: str) -> Any:
        ...

    @abstractmethod
    def get_direct_conversation(self, user1_id: UUID, user2_id: UUID) -> Optional[Any]:
        """Find existing direct conversation between two users."""
        ...

    @abstractmethod
    def create_direct_conversation(self, user1_id: UUID, user2_id: UUID) -> Any:
        ...

    @abstractmethod
    def create_group_conversation(self, group: Any) -> Any:
        ...

    @abstractmethod
    def get_group_conversation(self, group_id: UUID) -> Optional[Any]:
        ...

    @abstractmethod
    def can_user_access(self, conversation_id: UUID, user_id: UUID) -> bool:
        ...

    @abstractmethod
    def update_last_message_time(self, conversation_id: UUID, timestamp: Any = None) -> None:
        """Update the last_message_at timestamp for a conversation."""
        ...


class ChatMessageRepository(ABC):
    """Repository interface for ChatMessage entities."""

    @abstractmethod
    def get_by_id(self, message_id: UUID) -> Optional[Any]:
        ...

    @abstractmethod
    def get_conversation_messages(
        self, conversation_id: UUID, limit: int = 50, before_id: UUID = None,
    ) -> Dict[str, Any]:
        """Get paginated messages for a conversation."""
        ...

    @abstractmethod
    def create_message(self, conversation: Any, sender: Any, data: Dict) -> Any:
        ...

    @abstractmethod
    def soft_delete(self, message_id: UUID) -> bool:
        ...

    @abstractmethod
    def update_content(self, message_id: UUID, new_content: str) -> Any:
        ...

    @abstractmethod
    def mark_as_read(self, message_ids: List[UUID], user_id: UUID) -> int:
        """Mark messages as read. Returns count of newly marked."""
        ...

    @abstractmethod
    def bulk_mark_read_for_conversation(
        self, conversation_id: UUID, user_id: UUID, up_to_message_id: UUID = None
    ) -> int:
        """Mark all unread messages in a conversation as read for a user."""
        ...

    @abstractmethod
    def get_unread_count(self, conversation_id: UUID, user_id: UUID) -> int:
        ...

    @abstractmethod
    def get_valid_reply_message(
        self, message_id: UUID, conversation_id: UUID
    ) -> Optional[Any]:
        """Get a non-deleted message in a conversation (for reply validation)."""
        ...


class FriendshipQueryRepository(ABC):
    """Cross-context query interface for friendship checks needed by chat."""

    @abstractmethod
    def are_friends(self, user1_id: UUID, user2_id: UUID) -> bool:
        ...


class GroupQueryRepository(ABC):
    """Cross-context query interface for group checks needed by chat."""

    @abstractmethod
    def get_by_id(self, group_id: UUID) -> Optional[Any]:
        ...

    @abstractmethod
    def is_member(self, group_id: UUID, user_id: UUID) -> bool:
        ...
