"""
Chat Domain — Domain Events

Pure data objects representing things that happened in the chat domain.
These are raised by command handlers and consumed by infrastructure
(WebSocket publishers, push notifications, etc.)

Domain events must NOT depend on Django or any infrastructure framework.
"""
from dataclasses import dataclass
from typing import Optional

from planpals.shared.interfaces import DomainEvent


@dataclass(frozen=True)
class MessageSent(DomainEvent):
    """A new message was sent in a conversation."""
    conversation_id: str
    message_id: str
    sender_id: str
    sender_name: str = ''
    content: str = ''
    message_type: str = 'text'
    group_id: Optional[str] = None
    is_direct: bool = False


@dataclass(frozen=True)
class MessageEdited(DomainEvent):
    """A message was edited."""
    conversation_id: str
    message_id: str
    editor_id: str
    new_content: str = ''


@dataclass(frozen=True)
class MessageDeleted(DomainEvent):
    """A message was soft-deleted."""
    conversation_id: str
    message_id: str
    deleted_by_id: str


@dataclass(frozen=True)
class MessagesRead(DomainEvent):
    """Messages were marked as read by a user."""
    conversation_id: str
    user_id: str
    count: int = 0


@dataclass(frozen=True)
class ConversationCreated(DomainEvent):
    """A new conversation was created."""
    conversation_id: str
    conversation_type: str  # 'direct' or 'group'
    group_id: Optional[str] = None
    user_a_id: Optional[str] = None
    user_b_id: Optional[str] = None
