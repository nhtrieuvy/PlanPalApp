"""
Chat Application — Command DTOs

Immutable command objects for mutations in the chat bounded context.
"""
from dataclasses import dataclass, field
from typing import Optional, Dict, Any, List
from uuid import UUID


@dataclass(frozen=True)
class SendMessageCommand:
    """Send a message within a conversation."""
    conversation_id: UUID
    sender_id: UUID
    content: str = ''
    message_type: str = 'text'
    attachment: Optional[Any] = None
    attachment_name: str = ''
    attachment_size: Optional[int] = None
    latitude: Optional[Any] = None
    longitude: Optional[Any] = None
    location_name: str = ''
    reply_to_id: Optional[UUID] = None


@dataclass(frozen=True)
class SendDirectMessageCommand:
    """Send a direct message to another user (conversation auto-resolved)."""
    sender_id: UUID
    recipient_id: UUID
    content: str = ''
    message_type: str = 'text'
    attachment: Optional[Any] = None
    attachment_name: str = ''
    attachment_size: Optional[int] = None


@dataclass(frozen=True)
class SendGroupMessageCommand:
    """Send a message in a group conversation (conversation auto-resolved)."""
    sender_id: UUID
    group_id: UUID
    content: str = ''
    message_type: str = 'text'
    attachment: Optional[Any] = None
    attachment_name: str = ''
    attachment_size: Optional[int] = None


@dataclass(frozen=True)
class CreateSystemMessageCommand:
    """Create a system message (no sender)."""
    conversation_id: Optional[UUID] = None
    group_id: Optional[UUID] = None
    content: str = ''


@dataclass(frozen=True)
class EditMessageCommand:
    message_id: UUID
    editor_id: UUID
    new_content: str = ''


@dataclass(frozen=True)
class DeleteMessageCommand:
    message_id: UUID
    deleted_by_id: UUID


@dataclass(frozen=True)
class MarkMessagesReadCommand:
    conversation_id: UUID
    user_id: UUID
    message_ids: tuple = ()  # tuple for frozen dataclass
