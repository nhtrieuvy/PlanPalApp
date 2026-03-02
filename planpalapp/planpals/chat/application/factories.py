"""
Chat Application — Handler Factories
"""
from planpals.shared.infrastructure import ChannelsDomainEventPublisher
from planpals.chat.infrastructure.repositories import (
    DjangoConversationRepository,
    DjangoChatMessageRepository,
)
from planpals.chat.application.handlers import (
    SendMessageHandler,
    CreateSystemMessageHandler,
    EditMessageHandler,
    DeleteMessageHandler,
    MarkMessagesReadHandler,
)


def _conversation_repo():
    return DjangoConversationRepository()


def _message_repo():
    return DjangoChatMessageRepository()


def _event_publisher():
    return ChannelsDomainEventPublisher()


def get_send_message_handler() -> SendMessageHandler:
    return SendMessageHandler(
        conversation_repo=_conversation_repo(),
        message_repo=_message_repo(),
        event_publisher=_event_publisher(),
    )


def get_create_system_message_handler() -> CreateSystemMessageHandler:
    return CreateSystemMessageHandler(
        conversation_repo=_conversation_repo(),
        message_repo=_message_repo(),
    )


def get_edit_message_handler() -> EditMessageHandler:
    return EditMessageHandler(
        message_repo=_message_repo(),
    )


def get_delete_message_handler() -> DeleteMessageHandler:
    return DeleteMessageHandler(
        message_repo=_message_repo(),
        conversation_repo=_conversation_repo(),
    )


def get_mark_messages_read_handler() -> MarkMessagesReadHandler:
    return MarkMessagesReadHandler(
        conversation_repo=_conversation_repo(),
        message_repo=_message_repo(),
    )
