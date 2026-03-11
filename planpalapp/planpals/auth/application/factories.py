"""
Auth Application — Handler Factories
"""
from planpals.shared.infrastructure import ChannelsDomainEventPublisher
from planpals.auth.infrastructure.repositories import (
    DjangoUserRepository,
    DjangoFriendshipRepository,
)
from planpals.auth.application.handlers import (
    SendFriendRequestHandler,
    AcceptFriendRequestHandler,
    RejectFriendRequestHandler,
    CancelFriendRequestHandler,
    BlockUserHandler,
    UnblockUserHandler,
    UnfriendHandler,
    SetOnlineStatusHandler,
    UpdateFCMTokenHandler,
)


def _user_repo():
    return DjangoUserRepository()


def _friendship_repo():
    return DjangoFriendshipRepository()


def _event_publisher():
    return ChannelsDomainEventPublisher()


def _conversation_creator():
    """Returns a callable(user1_id, user2_id) that auto-creates a direct conversation."""
    from planpals.chat.infrastructure.repositories import DjangoConversationRepository
    repo = DjangoConversationRepository()

    def create_if_needed(user1_id, user2_id):
        existing = repo.get_direct_conversation(user1_id, user2_id)
        if not existing:
            repo.create_direct_conversation(user1_id, user2_id)

    return create_if_needed


def get_send_friend_request_handler() -> SendFriendRequestHandler:
    return SendFriendRequestHandler(
        user_repo=_user_repo(),
        friendship_repo=_friendship_repo(),
        event_publisher=_event_publisher(),
    )


def get_accept_friend_request_handler() -> AcceptFriendRequestHandler:
    return AcceptFriendRequestHandler(
        user_repo=_user_repo(),
        friendship_repo=_friendship_repo(),
        event_publisher=_event_publisher(),
        conversation_creator=_conversation_creator(),
    )


def get_reject_friend_request_handler() -> RejectFriendRequestHandler:
    return RejectFriendRequestHandler(
        friendship_repo=_friendship_repo(),
    )


def get_cancel_friend_request_handler() -> CancelFriendRequestHandler:
    return CancelFriendRequestHandler(
        friendship_repo=_friendship_repo(),
    )


def get_block_user_handler() -> BlockUserHandler:
    return BlockUserHandler(
        friendship_repo=_friendship_repo(),
    )


def get_unblock_user_handler() -> UnblockUserHandler:
    return UnblockUserHandler(
        friendship_repo=_friendship_repo(),
    )


def get_unfriend_handler() -> UnfriendHandler:
    return UnfriendHandler(
        friendship_repo=_friendship_repo(),
    )


def get_set_online_status_handler() -> SetOnlineStatusHandler:
    return SetOnlineStatusHandler(
        user_repo=_user_repo(),
        event_publisher=_event_publisher(),
    )


def get_update_fcm_token_handler() -> UpdateFCMTokenHandler:
    return UpdateFCMTokenHandler(
        user_repo=_user_repo(),
    )


# --- Repo / infrastructure service factories for service layer ---

def get_user_repo():
    return DjangoUserRepository()


def get_friendship_repo():
    return DjangoFriendshipRepository()


def get_token_repo():
    from planpals.auth.infrastructure.repositories import DjangoTokenRepository
    return DjangoTokenRepository()


def get_auth_group_repo():
    from planpals.auth.infrastructure.repositories import DjangoAuthGroupRepository
    return DjangoAuthGroupRepository()


def get_cache_service():
    from planpals.shared.cache_infrastructure import DjangoCacheService
    return DjangoCacheService()
