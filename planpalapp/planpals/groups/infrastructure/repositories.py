"""
Groups Infrastructure — Django ORM Repository Implementations
"""
import logging
from typing import Optional, Any, List
from uuid import UUID

from django.db.models import F, Q
from django.utils import timezone

from planpals.groups.domain.repositories import (
    GroupInviteRepository,
    GroupJoinRequestRepository,
    GroupMembershipRepository,
    GroupRepository,
)
from planpals.groups.infrastructure.models import (
    Group,
    GroupInvite,
    GroupJoinRequest,
    GroupMembership,
)

logger = logging.getLogger(__name__)


class DjangoGroupRepository(GroupRepository):
    """Django ORM implementation of GroupRepository."""

    def get_by_id(self, group_id: UUID) -> Optional[Group]:
        try:
            return Group.objects.select_related('admin').get(id=group_id)
        except Group.DoesNotExist:
            return None

    def get_by_id_with_stats(self, group_id: UUID) -> Optional[Group]:
        try:
            return (
                Group.objects
                .select_related('admin')
                .prefetch_related('memberships__user')
                .with_full_stats()
                .get(id=group_id)
            )
        except Group.DoesNotExist:
            return None

    def exists(self, group_id: UUID) -> bool:
        return Group.objects.filter(id=group_id).exists()

    def save(self, group: Group) -> Group:
        group.save()
        return group

    def save_new(self, command) -> Group:
        """Create a new Group from a CreateGroupCommand.

        NOTE: We bypass Group.save() auto-membership creation because the
        handler manages membership explicitly.
        """
        group = Group(
            name=command.name,
            description=command.description,
            visibility=command.visibility,
            admin_id=command.admin_id,
            avatar=command.avatar,
            cover_image=command.cover_image,
        )
        group.save()
        return group

    def delete(self, group_id: UUID) -> bool:
        deleted_count, _ = Group.objects.filter(id=group_id).delete()
        return deleted_count > 0

    def get_user_groups(self, user_id: UUID) -> Any:
        return (
            Group.objects
            .filter(members=user_id)
            .select_related('admin')
            .prefetch_related('memberships__user')
            .with_full_stats()
            .order_by('-created_at')
        )

    def get_groups_created_by(self, user_id: UUID) -> Any:
        return (
            Group.objects
            .filter(admin_id=user_id)
            .select_related('admin')
            .with_full_stats()
            .order_by('-created_at')
        )

    def search_groups(self, query: str, user_id: UUID) -> Any:
        return (
            Group.objects
            .filter(members=user_id)
            .filter(
                Q(name__icontains=query) | Q(description__icontains=query)
            )
            .select_related('admin')
            .prefetch_related('members', 'memberships__user')
            .with_full_stats()
        )

    def get_group_plans(self, group_id: UUID) -> Any:
        from planpals.plans.infrastructure.models import Plan
        return (
            Plan.objects
            .filter(group_id=group_id)
            .select_related('creator', 'group')
            .prefetch_related('activities')
            .order_by('-created_at')
        )

    def get_by_id_for_detail(self, group_id: UUID) -> Optional[Group]:
        try:
            return (
                Group.objects
                .select_related('admin')
                .prefetch_related('memberships__user')
                .with_full_stats()
                .get(id=group_id)
            )
        except Group.DoesNotExist:
            return None


class DjangoGroupMembershipRepository(GroupMembershipRepository):
    """Django ORM implementation of GroupMembershipRepository."""

    def add_member(self, group_id: UUID, user_id: UUID, role: str = 'member') -> GroupMembership:
        membership = GroupMembership(
            group_id=group_id,
            user_id=user_id,
            role=role,
        )
        membership.full_clean()
        membership.save()
        return membership

    def remove_member(self, group_id: UUID, user_id: UUID) -> bool:
        deleted_count, _ = GroupMembership.objects.filter(
            group_id=group_id, user_id=user_id,
        ).delete()
        return deleted_count > 0

    def is_member(self, group_id: UUID, user_id: UUID) -> bool:
        return GroupMembership.objects.filter(
            group_id=group_id, user_id=user_id,
        ).exists()

    def is_admin(self, group_id: UUID, user_id: UUID) -> bool:
        return GroupMembership.objects.filter(
            group_id=group_id, user_id=user_id, role=GroupMembership.ADMIN,
        ).exists()

    def get_role(self, group_id: UUID, user_id: UUID) -> Optional[str]:
        try:
            membership = GroupMembership.objects.get(
                group_id=group_id, user_id=user_id,
            )
            return membership.role
        except GroupMembership.DoesNotExist:
            return None

    def set_role(self, group_id: UUID, user_id: UUID, role: str) -> bool:
        updated = GroupMembership.objects.filter(
            group_id=group_id, user_id=user_id,
        ).update(role=role)
        return updated > 0

    def get_members(self, group_id: UUID) -> Any:
        return GroupMembership.objects.filter(
            group_id=group_id,
        ).select_related('user').order_by('role', 'created_at')

    def get_admin_count(self, group_id: UUID) -> int:
        return GroupMembership.objects.filter(
            group_id=group_id, role=GroupMembership.ADMIN,
        ).count()

    def get_membership(self, group_id: UUID, user_id: UUID) -> Optional[GroupMembership]:
        try:
            return GroupMembership.objects.select_related('user').get(
                group_id=group_id, user_id=user_id,
            )
        except GroupMembership.DoesNotExist:
            return None


class DjangoGroupInviteRepository(GroupInviteRepository):
    """Django ORM implementation for secure group invite codes."""

    def create_invite(
        self,
        *,
        group_id: UUID,
        token: str,
        created_by_user_id: UUID,
        expires_at,
        max_uses: int | None,
    ) -> GroupInvite:
        invite = GroupInvite(
            group_id=group_id,
            token=token,
            created_by_id=created_by_user_id,
            expires_at=expires_at,
            max_uses=max_uses,
        )
        invite.full_clean()
        invite.save()
        return invite

    def token_exists(self, token: str) -> bool:
        return GroupInvite.objects.filter(token=token).exists()

    def find_by_token(self, token: str, *, for_update: bool = False) -> Optional[GroupInvite]:
        queryset = GroupInvite.objects.select_related('group', 'created_by')
        if for_update:
            queryset = queryset.select_for_update()
        return queryset.filter(token=token).first()

    def find_by_id(self, invite_id: UUID) -> Optional[GroupInvite]:
        return (
            GroupInvite.objects
            .select_related('group', 'created_by')
            .filter(id=invite_id)
            .first()
        )

    def list_for_group(self, group_id: UUID):
        return (
            GroupInvite.objects
            .filter(group_id=group_id)
            .select_related('created_by', 'group')
            .order_by('-created_at', '-id')
        )

    def increment_usage(self, invite_id: UUID) -> None:
        GroupInvite.objects.filter(id=invite_id).update(
            current_uses=F('current_uses') + 1,
        )

    def revoke_invite(self, invite_id: UUID) -> bool:
        updated = GroupInvite.objects.filter(id=invite_id, is_active=True).update(
            is_active=False,
        )
        return updated > 0

    def validate_invite(self, invite: GroupInvite, *, now=None) -> tuple[bool, str | None]:
        now = now or timezone.now()
        if not invite.is_active:
            return False, 'revoked'
        if invite.expires_at and invite.expires_at <= now:
            return False, 'expired'
        if invite.max_uses is not None and invite.current_uses >= invite.max_uses:
            return False, 'usage_limit'
        return True, None


class DjangoGroupJoinRequestRepository(GroupJoinRequestRepository):
    """Django ORM implementation for private-group join approval requests."""

    def create_or_refresh_request(
        self,
        *,
        group_id: UUID,
        user_id: UUID,
        invite_id: UUID | None,
    ) -> GroupJoinRequest:
        request, _created = GroupJoinRequest.objects.update_or_create(
            group_id=group_id,
            user_id=user_id,
            defaults={
                'invite_id': invite_id,
                'status': GroupJoinRequest.PENDING,
                'reviewed_by_id': None,
                'reviewed_at': None,
                'is_active': True,
            },
        )
        return request

    def find_by_id(
        self,
        request_id: UUID,
        *,
        for_update: bool = False,
    ) -> Optional[GroupJoinRequest]:
        queryset = GroupJoinRequest.objects.select_related(
            'group',
            'invite',
            'user',
            'reviewed_by',
        )
        if for_update:
            queryset = queryset.select_for_update()
        return queryset.filter(id=request_id).first()

    def list_for_group(self, group_id: UUID, *, status: str | None = None):
        queryset = (
            GroupJoinRequest.objects
            .filter(group_id=group_id)
            .select_related('user', 'invite', 'reviewed_by')
            .order_by('-created_at', '-id')
        )
        if status:
            queryset = queryset.filter(status=status)
        return queryset

    def set_status(
        self,
        request_id: UUID,
        *,
        status: str,
        reviewed_by_user_id: UUID,
        reviewed_at,
    ) -> Optional[GroupJoinRequest]:
        updated = GroupJoinRequest.objects.filter(id=request_id).update(
            status=status,
            reviewed_by_id=reviewed_by_user_id,
            reviewed_at=reviewed_at,
        )
        if not updated:
            return None
        return self.find_by_id(request_id)
