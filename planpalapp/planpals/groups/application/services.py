import logging
from typing import Dict, Optional, Tuple, Any

from planpals.shared.base_service import BaseService
from planpals.shared.cache import CacheKeys, CacheTTL

# Commands & factories — thin delegation layer
from planpals.groups.application.commands import (
    CreateGroupCommand,
    AddMemberCommand,
    RemoveMemberCommand,
    JoinGroupCommand,
    LeaveGroupCommand,
    PromoteMemberCommand,
    DemoteMemberCommand,
)
from planpals.groups.application import factories as group_factories

logger = logging.getLogger(__name__)


class GroupService(BaseService):    
    @classmethod
    def create_group(
        cls,
        creator,
        name: str,
        description: str = "",
        initial_members=None,
        avatar=None,
        cover_image=None,
    ):
        """Delegate to CreateGroupHandler."""
        cmd = CreateGroupCommand(
            admin_id=creator.id,
            name=name,
            description=description,
            initial_member_ids=tuple(u.id for u in (initial_members or []) if u != creator),
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
    def leave_group(cls, group, user) -> Tuple[bool, str]:
        """Delegate to LeaveGroupHandler."""
        cmd = LeaveGroupCommand(group_id=group.id, user_id=user.id)
        handler = group_factories.get_leave_group_handler()
        handler.handle(cmd)
        cls._invalidate_group_cache(group.id)
        return True, "Left group successfully"
    
    @classmethod
    def can_manage_members(cls, group, user) -> bool:
        return group.is_admin(user)
    
    @classmethod
    def can_edit_group(cls, group, user) -> bool:
        return group.is_admin(user)
    
    
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
            'can_create_plan': group.is_admin(user)
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
        key = CacheKeys.group_detail(group_id, user_id)

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
            cache_svc.delete_pattern(CacheKeys.group_detail_pattern(group_id))
        except Exception as e:
            logger.warning("Failed to invalidate group cache for %s: %s", group_id, e)
