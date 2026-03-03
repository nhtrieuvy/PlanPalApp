"""
Chat Application — Command Handlers

Each handler encapsulates a single use-case for chat mutations.
Handlers depend on repository interfaces and publish domain events.
"""
import datetime
import logging
from typing import Tuple, Any

from planpals.shared.interfaces import BaseCommandHandler, DomainEventPublisher
from planpals.chat.domain.repositories import ConversationRepository, ChatMessageRepository
from planpals.chat.application.commands import (
    SendMessageCommand,
    EditMessageCommand,
    DeleteMessageCommand,
    MarkMessagesReadCommand,
    CreateSystemMessageCommand,
)

logger = logging.getLogger(__name__)


class SendMessageHandler(BaseCommandHandler[SendMessageCommand, Any]):
    """
    Create a new message in a conversation.
    Validates access, creates message, publishes events.
    """

    def __init__(
        self,
        conversation_repo: ConversationRepository,
        message_repo: ChatMessageRepository,
        event_publisher: DomainEventPublisher,
        user_repo=None,
    ):
        self.conversation_repo = conversation_repo
        self.message_repo = message_repo
        self.event_publisher = event_publisher
        self.user_repo = user_repo

    def handle(self, command: SendMessageCommand) -> Any:
        conversation = self.conversation_repo.get_by_id(command.conversation_id)
        if not conversation:
            raise ValueError("Conversation not found")

        if not self.conversation_repo.can_user_access(
            command.conversation_id, command.sender_id
        ):
            raise ValueError("Access denied to this conversation")

        # Validate reply_to
        reply_to_id = command.reply_to_id
        if reply_to_id:
            reply_msg = self.message_repo.get_by_id(reply_to_id)
            if not reply_msg or reply_msg.conversation_id != conversation.id or reply_msg.is_deleted:
                raise ValueError("Reply message not found in this conversation")

        # Build data dict for repository
        data = {
            'message_type': command.message_type,
            'content': command.content,
            'attachment': command.attachment,
            'attachment_name': command.attachment_name,
            'attachment_size': command.attachment_size,
            'latitude': command.latitude,
            'longitude': command.longitude,
            'location_name': command.location_name,
            'reply_to_id': str(reply_to_id) if reply_to_id else None,
        }

        # Look up sender entity via repository
        sender = self.user_repo.get_by_id(command.sender_id) if self.user_repo else None

        message = self.message_repo.create_message(conversation, sender, data)

        return message


class CreateSystemMessageHandler(BaseCommandHandler[CreateSystemMessageCommand, Any]):
    """Create a system message (no sender)."""

    def __init__(
        self,
        conversation_repo: ConversationRepository,
        message_repo: ChatMessageRepository,
        group_query_repo=None,
    ):
        self.conversation_repo = conversation_repo
        self.message_repo = message_repo
        self.group_query_repo = group_query_repo

    def handle(self, command: CreateSystemMessageCommand) -> Any:
        conversation = None
        if command.conversation_id:
            conversation = self.conversation_repo.get_by_id(command.conversation_id)
        elif command.group_id:
            conversation = self.conversation_repo.get_group_conversation(command.group_id)
            if not conversation and self.group_query_repo:
                # Auto-create group conversation
                group = self.group_query_repo.get_by_id(command.group_id)
                if group:
                    conversation = self.conversation_repo.create_group_conversation(group)
        
        if not conversation:
            raise ValueError("No conversation found or could be created")

        data = {
            'message_type': 'system',
            'content': command.content,
        }

        message = self.message_repo.create_message(conversation, None, data)

        return message


class EditMessageHandler(BaseCommandHandler[EditMessageCommand, Tuple[bool, str]]):
    """
    Edit message content — only the sender can edit, within 15 minutes.
    """

    def __init__(self, message_repo: ChatMessageRepository):
        self.message_repo = message_repo

    def handle(self, command: EditMessageCommand) -> Tuple[bool, str]:
        message = self.message_repo.get_by_id(command.message_id)
        if not message:
            return False, "Message not found"

        if message.sender_id != command.editor_id:
            return False, "Can only edit your own messages"

        if message.message_type == 'system':
            return False, "Cannot edit system messages"

        edit_deadline = message.created_at + datetime.timedelta(minutes=15)
        if datetime.datetime.now(datetime.timezone.utc) > edit_deadline:
            return False, "Message edit time expired (15 minutes limit)"

        self.message_repo.update_content(command.message_id, command.new_content)
        return True, "Message edited successfully"


class DeleteMessageHandler(BaseCommandHandler[DeleteMessageCommand, Tuple[bool, str]]):
    """
    Soft-delete a message — sender or group admin may delete.
    """

    def __init__(
        self,
        message_repo: ChatMessageRepository,
        conversation_repo: ConversationRepository,
    ):
        self.message_repo = message_repo
        self.conversation_repo = conversation_repo

    def handle(self, command: DeleteMessageCommand) -> Tuple[bool, str]:
        message = self.message_repo.get_by_id(command.message_id)
        if not message:
            return False, "Message not found"

        is_sender = message.sender_id == command.deleted_by_id
        is_group_admin = False

        if message.conversation and message.conversation.group:
            is_group_admin = message.conversation.group.is_admin(command.deleted_by_id)

        if not (is_sender or is_group_admin):
            return False, "Permission denied. Only sender or group admin can delete messages"

        self.message_repo.soft_delete(command.message_id)
        return True, "Message deleted successfully"


class MarkMessagesReadHandler(BaseCommandHandler[MarkMessagesReadCommand, Tuple[bool, str]]):
    """
    Mark a batch of messages as read for a user.
    """

    def __init__(
        self,
        conversation_repo: ConversationRepository,
        message_repo: ChatMessageRepository,
    ):
        self.conversation_repo = conversation_repo
        self.message_repo = message_repo

    def handle(self, command: MarkMessagesReadCommand) -> Tuple[bool, str]:
        if not self.conversation_repo.can_user_access(
            command.conversation_id, command.user_id
        ):
            return False, "Access denied to this conversation"

        count = self.message_repo.mark_as_read(
            list(command.message_ids), command.user_id
        )
        return True, f"Marked {count} messages as read"
