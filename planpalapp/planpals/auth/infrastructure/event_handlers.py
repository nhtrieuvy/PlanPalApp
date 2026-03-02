"""
Auth Infrastructure — Domain Event Handler Registration
"""
from planpals.shared._event_registry import register_event_handler

from planpals.auth.domain.events import (
    UserOnline,
    UserOffline,
    FriendRequestSent,
    FriendRequestAccepted,
)


def _handle_user_online(event: UserOnline):
    from planpals.shared.realtime_publisher import publish_user_online
    publish_user_online(
        user_id=event.user_id,
        username=event.username,
        last_seen=event.last_seen,
    )


def _handle_user_offline(event: UserOffline):
    from planpals.shared.realtime_publisher import publish_user_offline
    publish_user_offline(
        user_id=event.user_id,
        username=event.username,
        last_seen=event.last_seen,
    )


def _handle_friend_request_sent(event: FriendRequestSent):
    from planpals.shared.realtime_publisher import publish_friend_request
    publish_friend_request(
        user_id=event.user_id,
        from_user_id=event.from_user_id,
        from_name=event.from_name,
    )


def _handle_friend_request_accepted(event: FriendRequestAccepted):
    from planpals.shared.realtime_publisher import publish_friend_request_accepted
    publish_friend_request_accepted(
        user_id=event.user_id,
        accepter_id=event.accepter_id,
        accepter_name=event.accepter_name,
    )


def register_auth_event_handlers():
    """Register all auth domain event handlers. Call from PlanPalsConfig.ready()."""
    register_event_handler(UserOnline, _handle_user_online)
    register_event_handler(UserOffline, _handle_user_offline)
    register_event_handler(FriendRequestSent, _handle_friend_request_sent)
    register_event_handler(FriendRequestAccepted, _handle_friend_request_accepted)
