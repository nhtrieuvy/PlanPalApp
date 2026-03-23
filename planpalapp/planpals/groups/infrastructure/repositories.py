"""
Groups Infrastructure — Django ORM Repository Implementations
"""
import logging
from typing import Optional, Any, List
from uuid import UUID

from django.db.models import Q

from planpals.groups.domain.repositories import GroupRepository, GroupMembershipRepository
from planpals.groups.infrastructure.models import Group, GroupMembership

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
