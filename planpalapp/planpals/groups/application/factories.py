"""
Groups Application — Handler Factories
"""
from planpals.shared.infrastructure import ChannelsDomainEventPublisher
from planpals.groups.infrastructure.repositories import (
    DjangoGroupRepository,
    DjangoGroupMembershipRepository,
)
from planpals.groups.application.handlers import (
    CreateGroupHandler,
    AddMemberHandler,
    RemoveMemberHandler,
    JoinGroupHandler,
    LeaveGroupHandler,
    PromoteMemberHandler,
    DemoteMemberHandler,
)


def _group_repo():
    return DjangoGroupRepository()


def _membership_repo():
    return DjangoGroupMembershipRepository()


def _event_publisher():
    return ChannelsDomainEventPublisher()


def _friendship_checker():
    """Returns a callable(user1_id, user2_id) -> bool."""
    from planpals.auth.infrastructure.repositories import DjangoFriendshipRepository
    repo = DjangoFriendshipRepository()
    return repo.are_friends


def _conversation_creator():
    """Returns a callable(group) -> Conversation."""
    from planpals.chat.infrastructure.repositories import DjangoConversationRepository
    repo = DjangoConversationRepository()
    return repo.create_group_conversation


def get_create_group_handler() -> CreateGroupHandler:
    return CreateGroupHandler(
        group_repo=_group_repo(),
        membership_repo=_membership_repo(),
        event_publisher=_event_publisher(),
        friendship_checker=_friendship_checker(),
        conversation_creator=_conversation_creator(),
    )


def get_add_member_handler() -> AddMemberHandler:
    return AddMemberHandler(
        group_repo=_group_repo(),
        membership_repo=_membership_repo(),
        event_publisher=_event_publisher(),
        friendship_checker=_friendship_checker(),
    )


def get_remove_member_handler() -> RemoveMemberHandler:
    return RemoveMemberHandler(
        group_repo=_group_repo(),
        membership_repo=_membership_repo(),
        event_publisher=_event_publisher(),
    )


def get_join_group_handler() -> JoinGroupHandler:
    return JoinGroupHandler(
        group_repo=_group_repo(),
        membership_repo=_membership_repo(),
        event_publisher=_event_publisher(),
    )


def get_leave_group_handler() -> LeaveGroupHandler:
    return LeaveGroupHandler(
        group_repo=_group_repo(),
        membership_repo=_membership_repo(),
        event_publisher=_event_publisher(),
    )


def get_promote_member_handler() -> PromoteMemberHandler:
    return PromoteMemberHandler(
        group_repo=_group_repo(),
        membership_repo=_membership_repo(),
        event_publisher=_event_publisher(),
    )


def get_demote_member_handler() -> DemoteMemberHandler:
    return DemoteMemberHandler(
        group_repo=_group_repo(),
        membership_repo=_membership_repo(),
        event_publisher=_event_publisher(),
    )
