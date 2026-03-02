"""
Auth Infrastructure — Django ORM Repository Implementations
"""
import logging
from typing import Optional, Any
from uuid import UUID

from django.contrib.auth import get_user_model
from django.db.models import Q
from django.utils import timezone

from planpals.auth.domain.repositories import UserRepository, FriendshipRepository
from planpals.auth.infrastructure.models import Friendship, FriendshipRejection

logger = logging.getLogger(__name__)

User = get_user_model()


class DjangoUserRepository(UserRepository):
    """Django ORM implementation of UserRepository."""

    def get_by_id(self, user_id: UUID) -> Optional[Any]:
        try:
            return User.objects.get(id=user_id)
        except User.DoesNotExist:
            return None

    def get_by_id_with_counts(self, user_id: UUID) -> Optional[Any]:
        try:
            return User.objects.with_counts().get(id=user_id)
        except User.DoesNotExist:
            return None

    def exists(self, user_id: UUID) -> bool:
        return User.objects.filter(id=user_id).exists()

    def save(self, user: Any) -> Any:
        user.save()
        return user

    def search(self, query: str, exclude_user_id: UUID = None) -> Any:
        qs = User.objects.filter(
            Q(username__icontains=query)
            | Q(first_name__icontains=query)
            | Q(last_name__icontains=query)
            | Q(email__icontains=query)
        ).filter(is_active=True)
        if exclude_user_id:
            qs = qs.exclude(id=exclude_user_id)
        return qs.order_by('username')

    def get_friends_of(self, user_id: UUID) -> Any:
        return User.objects.friends_of(user_id).order_by('username')

    def set_online_status(self, user_id: UUID, is_online: bool) -> bool:
        updates = {'is_online': is_online}
        if not is_online:
            updates['last_seen'] = timezone.now()
        updated = User.objects.filter(id=user_id).update(**updates)
        return updated > 0

    def update_fcm_token(self, user_id: UUID, token: Optional[str]) -> bool:
        updated = User.objects.filter(id=user_id).update(fcm_token=token or '')
        return updated > 0


class DjangoFriendshipRepository(FriendshipRepository):
    """Django ORM implementation of FriendshipRepository."""

    def get_friendship(self, user1_id: UUID, user2_id: UUID) -> Optional[Friendship]:
        return Friendship.objects.between_users(user1_id, user2_id).select_related(
            'user_a', 'user_b', 'initiator',
        ).first()

    def create_friendship(self, user1_id: UUID, user2_id: UUID, initiator_id: UUID) -> Friendship:
        friendship = Friendship(
            user_a_id=user1_id,
            user_b_id=user2_id,
            initiator_id=initiator_id,
            status=Friendship.PENDING,
        )
        friendship.save()  # canonical ordering handled in Friendship.save()
        return friendship

    def update_status(self, friendship_id: UUID, new_status: str) -> Friendship:
        friendship = Friendship.objects.select_related(
            'user_a', 'user_b', 'initiator',
        ).get(id=friendship_id)
        friendship.status = new_status
        friendship.save(update_fields=['status', 'updated_at'])
        return friendship

    def delete_friendship(self, friendship_id: UUID) -> bool:
        deleted_count, _ = Friendship.objects.filter(id=friendship_id).delete()
        return deleted_count > 0

    def are_friends(self, user1_id: UUID, user2_id: UUID) -> bool:
        return Friendship.are_friends(user1_id, user2_id)

    def is_blocked(self, user1_id: UUID, user2_id: UUID) -> bool:
        return Friendship.is_blocked(user1_id, user2_id)

    def get_pending_requests_for(self, user_id: UUID) -> Any:
        return Friendship.get_pending_requests(user_id)

    def get_sent_requests(self, user_id: UUID) -> Any:
        return Friendship.get_sent_requests(user_id)

    def get_rejection_count(self, user1_id: UUID, user2_id: UUID) -> int:
        friendship = Friendship.objects.between_users(user1_id, user2_id).first()
        if not friendship:
            return 0
        return friendship.get_rejection_count()

    def create_rejection(self, friendship_id: UUID, rejected_by_id: UUID) -> FriendshipRejection:
        friendship = Friendship.objects.get(id=friendship_id)
        rejection = FriendshipRejection(
            friendship=friendship,
            rejected_by_id=rejected_by_id,
        )
        rejection.full_clean()
        rejection.save()
        return rejection

    def reopen_as_pending(self, friendship_id: UUID, initiator_id: UUID) -> Friendship:
        friendship = Friendship.objects.get(id=friendship_id)
        friendship.status = Friendship.PENDING
        friendship.initiator_id = initiator_id
        friendship.save(update_fields=['status', 'initiator', 'updated_at'])
        return friendship

    def block_friendship(self, friendship_id: UUID, blocker_id: UUID) -> Friendship:
        friendship = Friendship.objects.get(id=friendship_id)
        friendship.status = Friendship.BLOCKED
        friendship.initiator_id = blocker_id
        friendship.save(update_fields=['status', 'initiator', 'updated_at'])
        return friendship

    def create_blocked_friendship(
        self, user1_id: UUID, user2_id: UUID, blocker_id: UUID
    ) -> Friendship:
        friendship = Friendship(
            user_a_id=user1_id,
            user_b_id=user2_id,
            initiator_id=blocker_id,
            status=Friendship.BLOCKED,
        )
        friendship.save()
        return friendship
