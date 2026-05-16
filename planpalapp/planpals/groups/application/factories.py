"""
Groups Application — Handler Factories
"""
from planpals.audit.application.factories import get_audit_log_service
from planpals.shared.infrastructure import ChannelsDomainEventPublisher
from planpals.groups.infrastructure.repositories import (
    DjangoGroupRepository,
    DjangoGroupInviteRepository,
    DjangoGroupJoinRequestRepository,
    DjangoGroupMembershipRepository,
)
from planpals.groups.application.handlers import (
    CreateGroupHandler,
    UpdateGroupHandler,
    AddMemberHandler,
    RemoveMemberHandler,
    JoinGroupHandler,
    LeaveGroupHandler,
    DeleteGroupHandler,
    PromoteMemberHandler,
    DemoteMemberHandler,
    SetMemberRoleHandler,
    CreateGroupInviteHandler,
    JoinGroupViaInviteHandler,
    RevokeInviteHandler,
    ApproveGroupJoinRequestHandler,
    RejectGroupJoinRequestHandler,
)


def _group_repo():
    return DjangoGroupRepository()


def _membership_repo():
    return DjangoGroupMembershipRepository()


def _invite_repo():
    return DjangoGroupInviteRepository()


def _join_request_repo():
    return DjangoGroupJoinRequestRepository()


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


def _group_conversation_deleter():
    """Returns a callable(group_id) -> deleted conversation count."""
    from planpals.chat.infrastructure.repositories import DjangoConversationRepository
    repo = DjangoConversationRepository()
    return repo.delete_group_conversation


def _group_cache_invalidator():
    from planpals.groups.infrastructure.cache import invalidate_group_detail_cache
    return invalidate_group_detail_cache


def get_create_group_handler() -> CreateGroupHandler:
    return CreateGroupHandler(
        group_repo=_group_repo(),
        membership_repo=_membership_repo(),
        event_publisher=_event_publisher(),
        friendship_checker=_friendship_checker(),
        conversation_creator=_conversation_creator(),
        audit_service=get_audit_log_service(),
    )


def get_update_group_handler() -> UpdateGroupHandler:
    return UpdateGroupHandler(
        group_repo=_group_repo(),
        membership_repo=_membership_repo(),
        event_publisher=_event_publisher(),
        audit_service=get_audit_log_service(),
    )


def get_add_member_handler() -> AddMemberHandler:
    return AddMemberHandler(
        group_repo=_group_repo(),
        membership_repo=_membership_repo(),
        event_publisher=_event_publisher(),
        friendship_checker=_friendship_checker(),
        audit_service=get_audit_log_service(),
    )


def get_remove_member_handler() -> RemoveMemberHandler:
    return RemoveMemberHandler(
        group_repo=_group_repo(),
        membership_repo=_membership_repo(),
        event_publisher=_event_publisher(),
        audit_service=get_audit_log_service(),
    )


def get_join_group_handler() -> JoinGroupHandler:
    return JoinGroupHandler(
        group_repo=_group_repo(),
        membership_repo=_membership_repo(),
        event_publisher=_event_publisher(),
        audit_service=get_audit_log_service(),
    )


def get_leave_group_handler() -> LeaveGroupHandler:
    return LeaveGroupHandler(
        group_repo=_group_repo(),
        membership_repo=_membership_repo(),
        event_publisher=_event_publisher(),
        audit_service=get_audit_log_service(),
    )


def get_delete_group_handler() -> DeleteGroupHandler:
    return DeleteGroupHandler(
        group_repo=_group_repo(),
        membership_repo=_membership_repo(),
        audit_service=get_audit_log_service(),
        group_conversation_deleter=_group_conversation_deleter(),
    )


def get_promote_member_handler() -> PromoteMemberHandler:
    return PromoteMemberHandler(
        membership_repo=_membership_repo(),
        event_publisher=_event_publisher(),
        audit_service=get_audit_log_service(),
        group_cache_invalidator=_group_cache_invalidator(),
    )


def get_demote_member_handler() -> DemoteMemberHandler:
    return DemoteMemberHandler(
        membership_repo=_membership_repo(),
        event_publisher=_event_publisher(),
        audit_service=get_audit_log_service(),
        group_cache_invalidator=_group_cache_invalidator(),
    )


def get_set_member_role_handler() -> SetMemberRoleHandler:
    return SetMemberRoleHandler(
        membership_repo=_membership_repo(),
        event_publisher=_event_publisher(),
        audit_service=get_audit_log_service(),
        group_cache_invalidator=_group_cache_invalidator(),
    )


def get_create_group_invite_handler() -> CreateGroupInviteHandler:
    return CreateGroupInviteHandler(
        group_repo=_group_repo(),
        membership_repo=_membership_repo(),
        invite_repo=_invite_repo(),
        audit_service=get_audit_log_service(),
    )


def get_join_group_via_invite_handler() -> JoinGroupViaInviteHandler:
    return JoinGroupViaInviteHandler(
        group_repo=_group_repo(),
        membership_repo=_membership_repo(),
        invite_repo=_invite_repo(),
        join_request_repo=_join_request_repo(),
        event_publisher=_event_publisher(),
        audit_service=get_audit_log_service(),
        group_cache_invalidator=_group_cache_invalidator(),
    )


def get_revoke_invite_handler() -> RevokeInviteHandler:
    return RevokeInviteHandler(
        group_repo=_group_repo(),
        membership_repo=_membership_repo(),
        invite_repo=_invite_repo(),
        audit_service=get_audit_log_service(),
    )


def get_approve_group_join_request_handler() -> ApproveGroupJoinRequestHandler:
    return ApproveGroupJoinRequestHandler(
        group_repo=_group_repo(),
        membership_repo=_membership_repo(),
        invite_repo=_invite_repo(),
        join_request_repo=_join_request_repo(),
        event_publisher=_event_publisher(),
        audit_service=get_audit_log_service(),
        group_cache_invalidator=_group_cache_invalidator(),
    )


def get_reject_group_join_request_handler() -> RejectGroupJoinRequestHandler:
    return RejectGroupJoinRequestHandler(
        group_repo=_group_repo(),
        membership_repo=_membership_repo(),
        join_request_repo=_join_request_repo(),
        audit_service=get_audit_log_service(),
    )


# --- Repo factories for service layer ---

def get_group_repo():
    return DjangoGroupRepository()


def get_membership_repo():
    return DjangoGroupMembershipRepository()


def get_invite_repo():
    return DjangoGroupInviteRepository()


def get_join_request_repo():
    return DjangoGroupJoinRequestRepository()


def get_user_repo():
    from planpals.auth.infrastructure.repositories import DjangoUserRepository
    return DjangoUserRepository()


def get_cache_service():
    from planpals.shared.cache_infrastructure import DjangoCacheService
    return DjangoCacheService()
