import logging
from typing import Dict, Optional, Tuple, Any
from uuid import UUID

from planpals.shared.base_service import BaseService
from planpals.shared.cache import CacheKeys, CacheTTL

# Commands & factories — thin delegation layer
from planpals.groups.application.commands import (
    CreateGroupCommand,
    UpdateGroupCommand,
    AddMemberCommand,
    RemoveMemberCommand,
    JoinGroupCommand,
    LeaveGroupCommand,
    DeleteGroupCommand,
    PromoteMemberCommand,
    DemoteMemberCommand,
    SetMemberRoleCommand,
    CreateGroupInviteCommand,
    JoinGroupViaInviteCommand,
    RevokeInviteCommand,
    ApproveGroupJoinRequestCommand,
    RejectGroupJoinRequestCommand,
)
from planpals.groups.application import factories as group_factories

logger = logging.getLogger(__name__)


class GroupService(BaseService):    
    @staticmethod
    def _normalize_member_id(member) -> UUID | None:
        raw_id = getattr(member, 'id', member)
        if raw_id is None:
            return None
        if isinstance(raw_id, UUID):
            return raw_id
        return UUID(str(raw_id))

    @classmethod
    def create_group(
        cls,
        creator,
        name: str,
        description: str = "",
        visibility: str = "private",
        initial_members=None,
        avatar=None,
        cover_image=None,
    ):
        """Delegate to CreateGroupHandler."""
        creator_id = creator.id
        initial_member_ids = tuple(
            member_id
            for member_id in (
                cls._normalize_member_id(member)
                for member in (initial_members or [])
            )
            if member_id and member_id != creator_id
        )
        cmd = CreateGroupCommand(
            admin_id=creator.id,
            name=name,
            description=description,
            visibility=visibility,
            initial_member_ids=initial_member_ids,
            avatar=avatar,
            cover_image=cover_image,
        )
        handler = group_factories.get_create_group_handler()
        return handler.handle(cmd)
    
    @classmethod
    def add_member(cls, group, user, role: str = None, added_by=None) -> Tuple[bool, str]:
        """Delegate to AddMemberHandler."""
        actor = added_by or group.admin
        cmd = AddMemberCommand(
            group_id=group.id,
            user_id=actor.id,
            target_user_id=user.id,
        )
        handler = group_factories.get_add_member_handler()
        handler.handle(cmd)
        cls._invalidate_group_cache(group.id)
        return True, "Member added successfully"
    
    @classmethod
    def add_member_by_id(cls, group, user_id: str, added_by=None) -> Tuple[bool, str]:
        user_repo = group_factories.get_user_repo()
        target_user = user_repo.get_by_id(user_id)
        if not target_user:
            return False, "User not found"
        
        return cls.add_member(group, target_user, added_by=added_by)

    @classmethod
    def update_group(cls, group, user, **fields):
        """Update group details through the application handler so audit/cache stay consistent."""
        cmd = UpdateGroupCommand(
            group_id=group.id,
            user_id=user.id,
            name=fields.get('name'),
            description=fields.get('description'),
            visibility=fields.get('visibility'),
            avatar=fields.get('avatar'),
            cover_image=fields.get('cover_image'),
        )
        handler = group_factories.get_update_group_handler()
        updated_group = handler.handle(cmd)
        cls._invalidate_group_cache(group.id)
        return updated_group
    
    @classmethod
    def remove_member_from_group(cls, group, user, 
                                removed_by) -> Tuple[bool, str]:
        """Delegate to RemoveMemberHandler."""
        cmd = RemoveMemberCommand(
            group_id=group.id,
            user_id=removed_by.id,
            target_user_id=user.id,
        )
        handler = group_factories.get_remove_member_handler()
        handler.handle(cmd)
        cls._invalidate_group_cache(group.id)
        return True, "Member removed successfully"
    
    @classmethod
    def join_group(cls, user, group_id: str) -> Tuple[bool, str, Optional[Any]]:
        """Delegate to JoinGroupHandler."""
        cmd = JoinGroupCommand(
            user_id=user.id,
            group_id=group_id,
        )
        handler = group_factories.get_join_group_handler()
        try:
            handler.handle(cmd)
            group_repo = group_factories.get_group_repo()
            group = group_repo.get_by_id_for_detail(group_id)
            cls._invalidate_group_cache(group_id)
            return True, "Joined group successfully", group
        except Exception as e:
            return False, str(e), None

    @classmethod
    def create_invite(
        cls,
        group,
        user,
        *,
        expires_at=None,
        max_uses: int | None = None,
    ):
        cmd = CreateGroupInviteCommand(
            group_id=group.id,
            user_id=user.id,
            expires_at=expires_at,
            max_uses=max_uses,
        )
        handler = group_factories.get_create_group_invite_handler()
        return handler.handle(cmd)

    @classmethod
    def list_invites(cls, group, user):
        membership_repo = group_factories.get_membership_repo()
        if not membership_repo.is_admin(group.id, user.id):
            from planpals.shared.domain_exceptions import NotGroupAdminException
            raise NotGroupAdminException()
        return group_factories.get_invite_repo().list_for_group(group.id)

    @classmethod
    def list_join_requests(cls, group, user, *, status: str | None = 'pending'):
        membership_repo = group_factories.get_membership_repo()
        if not membership_repo.is_admin(group.id, user.id):
            from planpals.shared.domain_exceptions import NotGroupAdminException
            raise NotGroupAdminException()
        return group_factories.get_join_request_repo().list_for_group(
            group.id,
            status=status,
        )

    @classmethod
    def revoke_invite(cls, invite_id, user) -> bool:
        cmd = RevokeInviteCommand(invite_id=invite_id, user_id=user.id)
        handler = group_factories.get_revoke_invite_handler()
        return handler.handle(cmd)

    @classmethod
    def join_group_via_invite(cls, user, token: str):
        cmd = JoinGroupViaInviteCommand(token=token, user_id=user.id)
        handler = group_factories.get_join_group_via_invite_handler()
        result = handler.handle(cmd)
        group_repo = group_factories.get_group_repo()
        group = group_repo.get_by_id_for_detail(result.group.id)
        if result.status == 'joined':
            cls._invalidate_group_cache(result.group.id)
        return group, result.membership, result.join_request, result.status

    @classmethod
    def approve_join_request(cls, request_id, user):
        cmd = ApproveGroupJoinRequestCommand(request_id=request_id, user_id=user.id)
        handler = group_factories.get_approve_group_join_request_handler()
        result = handler.handle(cmd)
        cls._invalidate_group_cache(result.group.id)
        return result

    @classmethod
    def reject_join_request(cls, request_id, user):
        cmd = RejectGroupJoinRequestCommand(request_id=request_id, user_id=user.id)
        handler = group_factories.get_reject_group_join_request_handler()
        return handler.handle(cmd)
    
    @classmethod
    def leave_group(cls, group, user) -> Tuple[bool, str]:
        """Delegate to LeaveGroupHandler."""
        cmd = LeaveGroupCommand(group_id=group.id, user_id=user.id)
        handler = group_factories.get_leave_group_handler()
        handler.handle(cmd)
        cls._invalidate_group_cache(group.id)
        return True, "Left group successfully"

    @classmethod
    def delete_group(cls, group, user) -> bool:
        cmd = DeleteGroupCommand(
            group_id=group.id,
            user_id=user.id,
        )
        handler = group_factories.get_delete_group_handler()
        deleted = handler.handle(cmd)
        cls._invalidate_group_cache(group.id)
        return deleted
    
    @classmethod
    def can_manage_members(cls, group, user) -> bool:
        return group.is_admin(user)
    
    @classmethod
    def can_edit_group(cls, group, user) -> bool:
        return group.is_admin(user)

    @classmethod
    def can_create_group_plan(cls, group, user) -> bool:
        return group.can_create_plans(user)
    
    
    @classmethod
    def promote_member(cls, group, user_to_promote, actor) -> Tuple[bool, str]:
        """Delegate to PromoteMemberHandler."""
        cmd = PromoteMemberCommand(
            group_id=group.id,
            user_id=actor.id,
            target_user_id=user_to_promote.id,
        )
        handler = group_factories.get_promote_member_handler()
        handler.handle(cmd)
        cls._invalidate_group_cache(group.id)
        return True, "Member promoted successfully"

    @classmethod
    def demote_member(cls, group, user_to_demote, actor) -> Tuple[bool, str]:
        """Delegate to DemoteMemberHandler."""
        cmd = DemoteMemberCommand(
            group_id=group.id,
            user_id=actor.id,
            target_user_id=user_to_demote.id,
        )
        handler = group_factories.get_demote_member_handler()
        handler.handle(cmd)
        cls._invalidate_group_cache(group.id)
        return True, "Member demoted successfully"

    @classmethod
    def change_member_role(cls, group, target_user, role: str, actor) -> Tuple[bool, str]:
        normalized_role = (role or '').strip().lower()
        cmd = SetMemberRoleCommand(
            group_id=group.id,
            user_id=actor.id,
            target_user_id=target_user.id,
            role=normalized_role,
        )
        handler = group_factories.get_set_member_role_handler()
        handler.handle(cmd)
        cls._invalidate_group_cache(group.id)
        return True, f"Member role changed to {normalized_role}"
    
    @classmethod
    def search_user_groups(cls, user, query: str):        
        return group_factories.get_group_repo().search_groups(query, user.id)
    
    @classmethod
    def get_group_plans(cls, group, user) -> Dict[str, Any]:
        group_repo = group_factories.get_group_repo()
        plans = group_repo.get_group_plans(group.id)
        
        return {
            'plans': plans,
            'group_id': str(group.id),
            'group_name': group.name,
            'count': len(plans),
            'can_create_plan': cls.can_create_group_plan(group, user)
        }

    # ------------------------------------------------------------------
    # Cached reads
    # ------------------------------------------------------------------
    @classmethod
    def get_group_detail_cached(cls, group_id, user_id, serializer_fn):
        """Return group detail dict, backed by cache.

        *serializer_fn* is a ``callable(group) -> dict`` provided by the
        view so that the service layer never imports DRF serializers.
        """
        cache_svc = group_factories.get_cache_service()
        version = cls._get_group_cache_version(group_id)
        key = CacheKeys.group_detail(group_id, user_id, version=version)

        def compute():
            group_repo = group_factories.get_group_repo()
            group = group_repo.get_by_id_for_detail(group_id)
            if not group:
                return None
            return serializer_fn(group)

        return cache_svc.get_or_set(key, compute, CacheTTL.GROUP_DETAIL)

    # ------------------------------------------------------------------
    # Cache invalidation helper
    # ------------------------------------------------------------------
    @classmethod
    def _invalidate_group_cache(cls, group_id) -> None:
        try:
            cache_svc = group_factories.get_cache_service()
            version_key = CacheKeys.group_detail_version(group_id)
            current_version = cls._get_group_cache_version(group_id)
            cache_svc.set(version_key, current_version + 1)
            cache_svc.delete_pattern(CacheKeys.group_detail_pattern(group_id))
        except Exception as e:
            logger.warning("Failed to invalidate group cache for %s: %s", group_id, e)

    @classmethod
    def _get_group_cache_version(cls, group_id) -> int:
        cache_svc = group_factories.get_cache_service()
        version_key = CacheKeys.group_detail_version(group_id)
        raw_version = cache_svc.get(version_key)
        try:
            version = int(raw_version)
        except (TypeError, ValueError):
            version = 1
            cache_svc.set(version_key, version)
        return max(version, 1)
