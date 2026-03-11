"""
Chat Application — Handler Factories
"""
from planpals.shared.infrastructure import ChannelsDomainEventPublisher
from planpals.chat.infrastructure.repositories import (
    DjangoConversationRepository,
    DjangoChatMessageRepository,
)
from planpals.chat.application.handlers import (
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


def get_create_system_message_handler() -> CreateSystemMessageHandler:
    return CreateSystemMessageHandler(
        conversation_repo=_conversation_repo(),
        message_repo=_message_repo(),
        group_query_repo=get_group_query_repo(),
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


# --- Repo / infrastructure service factories for service layer ---

def get_conversation_repo():
    return DjangoConversationRepository()


def get_message_repo():
    return DjangoChatMessageRepository()


def get_friendship_query_repo():
    from planpals.chat.infrastructure.repositories import DjangoChatFriendshipQueryRepository
    return DjangoChatFriendshipQueryRepository()


def get_group_query_repo():
    from planpals.chat.infrastructure.repositories import DjangoChatGroupQueryRepository
    return DjangoChatGroupQueryRepository()


def get_realtime_publisher():
    from planpals.chat.infrastructure.publishers import ChatRealtimePublisher
    return ChatRealtimePublisher()


def get_push_publisher():
    from planpals.chat.infrastructure.publishers import ChatPushNotificationPublisher
    return ChatPushNotificationPublisher()


def get_user_repo():
    from planpals.auth.infrastructure.repositories import DjangoUserRepository
    return DjangoUserRepository()
