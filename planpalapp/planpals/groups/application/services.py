import logging
from typing import Dict, List, Optional, Tuple, Any

from django.db import transaction, models
from django.core.exceptions import ValidationError
from django.contrib.auth import get_user_model

from planpals.shared.base_service import BaseService
from planpals.groups.infrastructure.models import Group, GroupMembership
from planpals.models import User, Friendship, Plan

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

User = get_user_model()
logger = logging.getLogger(__name__)


class GroupService(BaseService):    
    @classmethod
    def create_group(cls, creator: User, name: str, description: str = "", 
                    is_public: bool = False, initial_members: List[User] = None) -> Group:
        """Delegate to CreateGroupHandler."""
        cmd = CreateGroupCommand(
            admin_id=creator.id,
            name=name,
            description=description,
            is_public=is_public,
            initial_member_ids=tuple(u.id for u in (initial_members or []) if u != creator),
        )
        handler = group_factories.get_create_group_handler()
        return handler.handle(cmd)
    
    @classmethod
    def add_member(cls, group: Group, user: User, 
                           role: str = None, added_by: User = None) -> Tuple[bool, str]:
        """Delegate to AddMemberHandler."""
        cmd = AddMemberCommand(
            group_id=group.id,
            user_id=user.id,
            added_by_id=added_by.id if added_by else None,
            role=role or GroupMembership.MEMBER,
        )
        handler = group_factories.get_add_member_handler()
        return handler.handle(cmd)
    
    @classmethod
    def add_member_by_id(cls, group: Group, user_id: str, added_by: User = None) -> Tuple[bool, str]:
        try:
            target_user = User.objects.get(id=user_id)
        except User.DoesNotExist:
            return False, "User not found"
        
        return cls.add_member(group, target_user, added_by=added_by)
    
    @classmethod
    def remove_member_from_group(cls, group: Group, user: User, 
                                removed_by: User) -> Tuple[bool, str]:
        """Delegate to RemoveMemberHandler."""
        cmd = RemoveMemberCommand(
            group_id=group.id,
            user_id=user.id,
            removed_by_id=removed_by.id,
        )
        handler = group_factories.get_remove_member_handler()
        return handler.handle(cmd)
    
    @classmethod
    def join_group_by_invite(cls, group: Group, user: User) -> Tuple[bool, str]:
        """Delegate to JoinGroupHandler."""
        cmd = JoinGroupCommand(group_id=group.id, user_id=user.id)
        handler = group_factories.get_join_group_handler()
        return handler.handle(cmd)
    
    @classmethod
    def join_group(cls, user: User, group_id: str = None, invite_code: str = None) -> Tuple[bool, str, Optional[Group]]:
        """Delegate to JoinGroupHandler."""
        cmd = JoinGroupCommand(
            user_id=user.id,
            group_id=group_id,
            invite_code=invite_code,
        )
        handler = group_factories.get_join_group_handler()
        try:
            result = handler.handle(cmd)
            if isinstance(result, tuple) and len(result) == 2:
                success, message = result
                if success:
                    # Resolve group for caller
                    from planpals.groups.infrastructure.repositories import DjangoGroupRepository
                    repo = DjangoGroupRepository()
                    group = repo.get_by_id(group_id) if group_id else repo.get_by_invite_code(invite_code)
                    return True, message, group
                return False, message, None
            return False, "Unexpected handler result", None
        except Exception as e:
            return False, str(e), None
    
    @classmethod
    @transaction.atomic  
    def leave_group(cls, group: Group, user: User) -> Tuple[bool, str]:
        """Delegate to LeaveGroupHandler."""
        cmd = LeaveGroupCommand(group_id=group.id, user_id=user.id)
        handler = group_factories.get_leave_group_handler()
        return handler.handle(cmd)
    
    @classmethod
    def can_manage_members(cls, group: Group, user: User) -> bool:
        return group.is_admin(user)
    
    @classmethod
    def can_edit_group(cls, group: Group, user: User) -> bool:
        return group.is_admin(user)
    
    
    @classmethod
    @transaction.atomic
    def promote_member(cls, group: Group, user_to_promote: User, actor: User) -> Tuple[bool, str]:
        """Delegate to PromoteMemberHandler."""
        cmd = PromoteMemberCommand(
            group_id=group.id,
            user_id=user_to_promote.id,
            promoted_by_id=actor.id,
        )
        handler = group_factories.get_promote_member_handler()
        return handler.handle(cmd)

    @classmethod
    @transaction.atomic
    def demote_member(cls, group: Group, user_to_demote: User, actor: User) -> Tuple[bool, str]:
        """Delegate to DemoteMemberHandler."""
        cmd = DemoteMemberCommand(
            group_id=group.id,
            user_id=user_to_demote.id,
            demoted_by_id=actor.id,
        )
        handler = group_factories.get_demote_member_handler()
        return handler.handle(cmd)
    
    @classmethod
    def search_user_groups(cls, user: User, query: str):        
        return Group.objects.filter(
            members=user
        ).filter(
            models.Q(name__icontains=query) |
            models.Q(description__icontains=query)
    ).select_related('admin').prefetch_related('members', 'memberships__user').with_full_stats()
    
    @classmethod
    def get_group_plans(cls, group: Group, user: User) -> Dict[str, Any]:
        plans = Plan.objects.filter(group=group).select_related(
            'creator', 'group'
        ).prefetch_related('activities').order_by('-created_at')
        
        return {
            'plans': plans,
            'group_id': str(group.id),
            'group_name': group.name,
            'count': len(plans),
            'can_create_plan': group.is_admin(user)
        }
