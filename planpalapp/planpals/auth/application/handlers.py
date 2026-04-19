"""
Auth Application — Command Handlers

Each handler encapsulates a single use-case for auth mutations.
Handlers depend on repository interfaces (not ORM) and publish
domain events via the event publisher abstraction.
"""
import datetime
import logging
from typing import Tuple, Any

from django.db import transaction

from planpals.shared.interfaces import BaseCommandHandler, DomainEventPublisher
from planpals.auth.domain.repositories import UserRepository, FriendshipRepository
from planpals.auth.domain.entities import (
    FriendshipStatus,
    REJECTION_COOLDOWN_HOURS,
    MAX_REJECTION_COUNT,
    EXTENDED_COOLDOWN_DAYS,
    can_resend_after_rejection,
)
from planpals.auth.domain.events import (
    FriendRequestSent,
    FriendRequestAccepted,
    UserOnline,
    UserOffline,
)
from planpals.auth.application.commands import (
    SendFriendRequestCommand,
    AcceptFriendRequestCommand,
    RejectFriendRequestCommand,
    CancelFriendRequestCommand,
    BlockUserCommand,
    UnblockUserCommand,
    UnfriendCommand,
    SetOnlineStatusCommand,
    UpdateFCMTokenCommand,
)

logger = logging.getLogger(__name__)


class SendFriendRequestHandler(BaseCommandHandler[SendFriendRequestCommand, Tuple[bool, str]]):
    """
    Send a friend request, respecting cooldown and block rules.
    """

    def __init__(
        self,
        user_repo: UserRepository,
        friendship_repo: FriendshipRepository,
        event_publisher: DomainEventPublisher,
    ):
        self.user_repo = user_repo
        self.friendship_repo = friendship_repo
        self.event_publisher = event_publisher

    @transaction.atomic
    def handle(self, command: SendFriendRequestCommand) -> Tuple[bool, str]:
        if command.from_user_id == command.to_user_id:
            return False, "Cannot send friend request to yourself"

        from_user = self.user_repo.get_by_id(command.from_user_id)
        to_user = self.user_repo.get_by_id(command.to_user_id)
        if not from_user or not to_user:
            return False, "User not found"

        existing = self.friendship_repo.get_friendship(
            command.from_user_id, command.to_user_id
        )

        if existing:
            return self._handle_existing(existing, from_user, to_user)

        return self._create_new(from_user, to_user)

    # ------------------------------------------------------------------
    def _handle_existing(self, friendship, from_user, to_user) -> Tuple[bool, str]:
        if friendship.status == FriendshipStatus.ACCEPTED:
            return False, "Already friends"
        if friendship.status == FriendshipStatus.PENDING:
            return False, "Friend request already sent"
        if friendship.status == FriendshipStatus.BLOCKED:
            if friendship.initiator_id == to_user.id:
                return False, "Cannot send friend request - you have been blocked"
            return False, "Cannot send friend request - you have blocked this user"

        if friendship.status == FriendshipStatus.REJECTED:
            return self._handle_rejected_resend(friendship, from_user, to_user)

        return False, "Unknown friendship state"

    def _handle_rejected_resend(self, friendship, from_user, to_user) -> Tuple[bool, str]:
        rejection_count = friendship.get_rejection_count()
        last_rejection = friendship.get_last_rejection()

        if last_rejection:
            can_resend, reason = can_resend_after_rejection(
                rejection_count, last_rejection.created_at, datetime.datetime.now(datetime.timezone.utc)
            )
            if not can_resend:
                return False, reason

        # Cooldown passed — re-open as pending via repo
        self.friendship_repo.reopen_as_pending(friendship.id, from_user.id)

        self._publish_friend_request_event(from_user, to_user)
        return True, "Friend request sent successfully"

    def _create_new(self, from_user, to_user) -> Tuple[bool, str]:
        self.friendship_repo.create_friendship(
            from_user.id, to_user.id, from_user.id
        )
        self._publish_friend_request_event(from_user, to_user)

        return True, "Friend request sent successfully"

    def _publish_friend_request_event(self, from_user, to_user):
        event = FriendRequestSent(
            user_id=str(to_user.id),
            from_user_id=str(from_user.id),
            from_name=from_user.get_full_name() or from_user.username,
        )
        self.event_publisher.publish(event)


class AcceptFriendRequestHandler(BaseCommandHandler[AcceptFriendRequestCommand, Tuple[bool, str]]):
    """
    Accept an incoming friend request  auto-create direct conversation.
    """

    def __init__(
        self,
        user_repo: UserRepository,
        friendship_repo: FriendshipRepository,
        event_publisher: DomainEventPublisher,
        conversation_creator=None,  # callable(user1, user2) -> conversation
    ):
        self.user_repo = user_repo
        self.friendship_repo = friendship_repo
        self.event_publisher = event_publisher
        self.conversation_creator = conversation_creator

    @transaction.atomic
    def handle(self, command: AcceptFriendRequestCommand) -> Tuple[bool, str]:
        friendship = self.friendship_repo.get_friendship(
            command.from_user_id, command.current_user_id
        )
        if not friendship:
            return False, "Friend request not found"
        if friendship.status != FriendshipStatus.PENDING:
            return False, f"Friend request is not pending (status: {friendship.status})"
        if friendship.initiator_id != command.from_user_id:
            return False, "You can only accept requests sent to you"

        current_user = self.user_repo.get_by_id(command.current_user_id)

        self.friendship_repo.update_status(friendship.id, FriendshipStatus.ACCEPTED)

        # Auto-create direct conversation
        if self.conversation_creator:
            try:
                self.conversation_creator(command.current_user_id, command.from_user_id)
            except Exception:
                logger.exception("Failed to create conversation after friend acceptance")

        event = FriendRequestAccepted(
            user_id=str(command.from_user_id),
            accepter_id=str(command.current_user_id),
            accepter_name=(
                current_user.get_full_name() or current_user.username
                if current_user else str(command.current_user_id)
            ),
        )
        self.event_publisher.publish(event)

        return True, "Friend request accepted"


class RejectFriendRequestHandler(BaseCommandHandler[RejectFriendRequestCommand, Tuple[bool, str]]):

    def __init__(self, friendship_repo: FriendshipRepository):
        self.friendship_repo = friendship_repo

    @transaction.atomic
    def handle(self, command: RejectFriendRequestCommand) -> Tuple[bool, str]:
        friendship = self.friendship_repo.get_friendship(
            command.from_user_id, command.current_user_id
        )
        if not friendship:
            return False, "Friend request not found"
        if friendship.status != FriendshipStatus.PENDING:
            return False, f"Friend request is not pending (status: {friendship.status})"
        if friendship.initiator_id != command.from_user_id:
            return False, "You can only reject requests sent to you"

        self.friendship_repo.create_rejection(friendship.id, command.current_user_id)
        self.friendship_repo.update_status(friendship.id, FriendshipStatus.REJECTED)

        return True, "Friend request rejected"


class CancelFriendRequestHandler(BaseCommandHandler[CancelFriendRequestCommand, Tuple[bool, str]]):

    def __init__(self, friendship_repo: FriendshipRepository):
        self.friendship_repo = friendship_repo

    def handle(self, command: CancelFriendRequestCommand) -> Tuple[bool, str]:
        friendship = self.friendship_repo.get_friendship(
            command.current_user_id, command.to_user_id
        )
        if not friendship:
            return False, "Friend request not found"
        if friendship.status != FriendshipStatus.PENDING:
            return False, "Friend request is not pending"
        if friendship.initiator_id != command.current_user_id:
            return False, "You can only cancel requests you sent"

        self.friendship_repo.delete_friendship(friendship.id)
        return True, "Friend request cancelled"


class BlockUserHandler(BaseCommandHandler[BlockUserCommand, Tuple[bool, str]]):

    def __init__(self, friendship_repo: FriendshipRepository):
        self.friendship_repo = friendship_repo

    @transaction.atomic
    def handle(self, command: BlockUserCommand) -> Tuple[bool, str]:
        if command.blocker_id == command.target_id:
            return False, "Cannot block yourself"

        friendship = self.friendship_repo.get_friendship(
            command.blocker_id, command.target_id
        )

        if friendship:
            if friendship.status == FriendshipStatus.BLOCKED:
                if friendship.initiator_id == command.blocker_id:
                    return False, "User is already blocked"
                return False, "You cannot block this user as they have blocked you"

            self.friendship_repo.block_friendship(friendship.id, command.blocker_id)
        else:
            self.friendship_repo.create_blocked_friendship(
                command.blocker_id, command.target_id, command.blocker_id
            )

        return True, "User blocked successfully"


class UnblockUserHandler(BaseCommandHandler[UnblockUserCommand, Tuple[bool, str]]):

    def __init__(self, friendship_repo: FriendshipRepository):
        self.friendship_repo = friendship_repo

    def handle(self, command: UnblockUserCommand) -> Tuple[bool, str]:
        friendship = self.friendship_repo.get_friendship(
            command.blocker_id, command.target_id
        )
        if not friendship or friendship.status != FriendshipStatus.BLOCKED:
            return False, "User is not blocked"
        if friendship.initiator_id != command.blocker_id:
            return False, "Only the person who blocked can unblock"

        self.friendship_repo.delete_friendship(friendship.id)
        return True, "User unblocked successfully"


class UnfriendHandler(BaseCommandHandler[UnfriendCommand, Tuple[bool, str]]):

    def __init__(self, friendship_repo: FriendshipRepository):
        self.friendship_repo = friendship_repo

    def handle(self, command: UnfriendCommand) -> Tuple[bool, str]:
        friendship = self.friendship_repo.get_friendship(
            command.current_user_id, command.target_user_id
        )
        if not friendship or friendship.status != FriendshipStatus.ACCEPTED:
            return False, "Not friends"

        self.friendship_repo.delete_friendship(friendship.id)
        return True, "Unfriended successfully"


class SetOnlineStatusHandler(BaseCommandHandler[SetOnlineStatusCommand, bool]):

    def __init__(
        self,
        user_repo: UserRepository,
        event_publisher: DomainEventPublisher,
    ):
        self.user_repo = user_repo
        self.event_publisher = event_publisher

    def handle(self, command: SetOnlineStatusCommand) -> bool:
        user = self.user_repo.get_by_id(command.user_id)
        if not user:
            return False

        success = self.user_repo.set_online_status(command.user_id, command.is_online)
        if success:
            username = getattr(user, 'username', str(command.user_id))
            last_seen = getattr(user, 'last_seen', None)
            last_seen_str = last_seen.isoformat() if last_seen else None

            if command.is_online:
                event = UserOnline(
                    user_id=str(command.user_id),
                    username=username,
                    last_seen=last_seen_str,
                )
            else:
                event = UserOffline(
                    user_id=str(command.user_id),
                    username=username,
                    last_seen=last_seen_str,
                )
            self.event_publisher.publish(event)
        return success


class UpdateFCMTokenHandler(BaseCommandHandler[UpdateFCMTokenCommand, bool]):

    def __init__(self, user_repo: UserRepository):
        self.user_repo = user_repo

    def handle(self, command: UpdateFCMTokenCommand) -> bool:
        return self.user_repo.update_fcm_token(command.user_id, command.token)
