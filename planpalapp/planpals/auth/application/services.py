from django.db import transaction, models
from django.db.models import QuerySet
from django.utils import timezone
from django.core.exceptions import ValidationError, PermissionDenied
from django.core.files.uploadedfile import UploadedFile
from typing import Dict, List, Optional, Tuple, Any
import logging
import re
from oauth2_provider.models import AccessToken, RefreshToken
from django.db.models import Q
from uuid import UUID

from planpals.auth.infrastructure.models import User, Friendship, FriendshipRejection
from planpals.shared.base_service import BaseService

from planpals.auth.presentation.serializers import UserSerializer

from channels.layers import get_channel_layer
from asgiref.sync import async_to_sync

# Commands & factories — thin delegation layer
from planpals.auth.application.commands import (
    SendFriendRequestCommand,
    AcceptFriendRequestCommand,
    RejectFriendRequestCommand,
    CancelFriendRequestCommand,
    BlockUserCommand,
    UnblockUserCommand,
    UnfriendCommand,
    SetOnlineStatusCommand,
)
from planpals.auth.application import factories as auth_factories

logger = logging.getLogger(__name__)


class UserService(BaseService):
    @classmethod
    def get_user_with_counts(cls, user_id: UUID) -> User:
        return User.objects.with_counts().get(id=user_id)
    
    @classmethod
    def get_friendship_status(cls, current_user: User, target_user: User) -> Dict[str, Any]:
        if current_user == target_user:
            return {'status': 'self'}

        friendship = Friendship.get_friendship(current_user, target_user)

        if not friendship:
            return {'status': 'none'}

        status = friendship.status
        if status == Friendship.ACCEPTED:
            return {'status': 'friends', 'since': friendship.created_at}
        if status == Friendship.PENDING:
            direction = 'pending_sent' if friendship.is_initiated_by(current_user) else 'pending_received'
            result = {'status': direction, 'created_at': friendship.created_at}
            if direction == 'pending_received':
                result['friendship_id'] = str(friendship.id)
            return result
        if status == Friendship.REJECTED:
            return {'status': 'rejected', 'rejected_at': friendship.updated_at}
        if status == Friendship.BLOCKED:
            if friendship.initiator == current_user:
                return {
                    'status': 'blocked_by_me',
                    'can_unblock': True,
                    'blocked_at': friendship.updated_at
                }
            else:
                return {
                    'status': 'blocked_by_them',
                    'can_unblock': False, 
                    'blocked_at': friendship.updated_at
                }

        return {'status': 'unknown'}
    
    @classmethod
    def send_friend_request(cls, from_user: User, to_user: User) -> Tuple[bool, str]:
        """Delegate to SendFriendRequestHandler."""
        cmd = SendFriendRequestCommand(
            from_user_id=from_user.id,
            to_user_id=to_user.id,
        )
        handler = auth_factories.get_send_friend_request_handler()
        return handler.handle(cmd)
    
    @classmethod
    def logout_user(cls, user: User, token_string: str = None) -> Tuple[bool, str, bool]:
        revoked = False
        online_set = False

        if token_string:
            try:
                with transaction.atomic():
                    at_qs = AccessToken.objects.select_for_update().filter(
                        token=token_string, user=user
                    )
                    if at_qs.exists():
                        at = at_qs.first()
                        try:
                            RefreshToken.objects.filter(access_token=at).delete()
                        except Exception as e:
                            cls.log_error("Failed to delete refresh tokens during logout", e, {'user_id': user.id})
                        at.delete()
                        revoked = True
            except Exception as e:
                cls.log_error("Failed to revoke access token during logout", e, {'user_id': user.id, 'token': token_string})

        # Delegate online-status to handler
        try:
            online_set = cls.set_user_online_status(user, False)
        except Exception as e:
            cls.log_error("Failed to set user offline during logout", e, {'user_id': user.id})

        if revoked or online_set:
            cls.log_operation("user_logout", {
                'user_id': user.id,
                'token_revoked': revoked,
                'offline_set': online_set
            })
            return True, "Logged out successfully", revoked

        cls.log_operation("user_logout_failed", {
            'user_id': user.id,
            'token_revoked': revoked,
            'offline_set': online_set
        })
        return False, "Logout failed: no changes applied", False
    
    @classmethod
    def search_users(cls, query: str, current_user: User, limit: int = 20):
        return User.objects.filter(
            models.Q(username__icontains=query) |
            models.Q(email__icontains=query) |
            models.Q(first_name__icontains=query) |
            models.Q(last_name__icontains=query)
        ).exclude(
            id=current_user.id
        ).only(
            'id', 'username', 'first_name', 'last_name', 
            'avatar', 'is_online', 'last_seen'
        ).order_by('username')
    
    @classmethod
    def update_user_profile(cls, user: User, data: Dict[str, Any]) -> Tuple[User, bool]:
        try:
            with transaction.atomic():

                serializer = UserSerializer(user, data=data, partial=True)
                if serializer.is_valid():
                    user = serializer.save()
                    user.update_last_seen()
                    
                    cls.log_operation("user_profile_updated", {
                        'user_id': user.id
                    })
                    
                    return user, True
                else:
                    return user, False
        except Exception as e:
            cls.log_operation("user_profile_update_failed", {
                'user_id': user.id,
                'error': str(e)
            })
            return user, False
    
    @classmethod
    def get_user_plans(cls, user: User, plan_type: str = 'all'):
        from planpals.models import Plan
        queryset = Plan.objects.for_user(user).with_stats()
        
        if plan_type == 'personal':
            queryset = queryset.filter(plan_type='personal')
        elif plan_type == 'group':
            queryset = queryset.filter(plan_type='group')
        
        return queryset
    
    @classmethod
    def get_user_groups(cls, user: User):
        return user.joined_groups.with_full_stats()
    
    @classmethod
    def get_user_activities(cls, user: User):
        from planpals.models import PlanActivity
        return PlanActivity.objects.filter(
            plan__in=user.viewable_plans
        ).select_related('plan', 'plan__group', 'plan__creator').order_by('-start_time')
    
    @classmethod
    def set_user_online_status(cls, user: User, is_online: bool) -> bool:
        """Delegate to SetOnlineStatusHandler."""
        cmd = SetOnlineStatusCommand(
            user_id=user.id,
            is_online=is_online,
        )
        handler = auth_factories.get_set_online_status_handler()
        return handler.handle(cmd)
    
    @classmethod
    def get_friendship_stats(cls, user: User) -> Dict[str, Any]:
        user = User.objects.with_counts().get(id=user.id)
        return {
            'friends_count': user.friends_count,
            'pending_sent_count': user.pending_sent_count,
            'pending_received_count': user.pending_received_count,
            'blocked_count': user.blocked_count
        }
    
    @classmethod
    def get_recent_conversations(cls, user: User):
        return user.recent_conversations
    
    @classmethod
    def get_unread_count(cls, user: User) -> int:
        return user.unread_messages_count
    
    @classmethod
    def unblock_user(cls, current_user: User, target_user: User) -> Tuple[bool, str]:
        """Delegate to UnblockUserHandler."""
        cmd = UnblockUserCommand(
            blocker_id=current_user.id,
            target_id=target_user.id,
        )
        handler = auth_factories.get_unblock_user_handler()
        return handler.handle(cmd)
    
    @classmethod
    def join_group(cls, user: User, group_id: str = None, invite_code: str = None) -> Tuple[bool, str, Optional[Any]]:
        from planpals.models import Group
        from planpals.groups.application.services import GroupService
        try:
            if invite_code:
                group = Group.objects.get(invite_code=invite_code)
            else:
                group = Group.objects.get(
                    id=group_id, 
                    is_public=True
                )
            
            success, message = GroupService.join_group_by_invite(group, user)
            
            if success:
                return True, message, group
            else:
                return False, message, None
                
        except Group.DoesNotExist:
            return False, "Group not found or not accessible", None
    
    @classmethod
    def accept_friend_request(cls, current_user: User, from_user: User) -> Tuple[bool, str]:
        """Delegate to AcceptFriendRequestHandler."""
        cmd = AcceptFriendRequestCommand(
            current_user_id=current_user.id,
            from_user_id=from_user.id,
        )
        handler = auth_factories.get_accept_friend_request_handler()
        return handler.handle(cmd)
    
    @classmethod
    def reject_friend_request(cls, current_user: User, from_user: User) -> Tuple[bool, str]:
        """Delegate to RejectFriendRequestHandler."""
        cmd = RejectFriendRequestCommand(
            current_user_id=current_user.id,
            from_user_id=from_user.id,
        )
        handler = auth_factories.get_reject_friend_request_handler()
        return handler.handle(cmd)
    
    @classmethod
    def cancel_friend_request(cls, current_user: User, to_user: User) -> Tuple[bool, str]:
        """Delegate to CancelFriendRequestHandler."""
        cmd = CancelFriendRequestCommand(
            current_user_id=current_user.id,
            to_user_id=to_user.id,
        )
        handler = auth_factories.get_cancel_friend_request_handler()
        return handler.handle(cmd)

    @classmethod
    def block_user(cls, current_user: User, target_user: User) -> Tuple[bool, str]:
        """Delegate to BlockUserHandler."""
        cmd = BlockUserCommand(
            blocker_id=current_user.id,
            target_id=target_user.id,
        )
        handler = auth_factories.get_block_user_handler()
        return handler.handle(cmd)
    
    @classmethod
    def unfriend_user(cls, current_user: User, target_user: User) -> Tuple[bool, str]:
        """Delegate to UnfriendHandler."""
        cmd = UnfriendCommand(
            current_user_id=current_user.id,
            target_user_id=target_user.id,
        )
        handler = auth_factories.get_unfriend_handler()
        return handler.handle(cmd)
    
    @classmethod
    def is_group_member(cls, user: User, group) -> bool:
        return group.is_member(user)
    
    @classmethod
    def can_view_profile(cls, current_user: User, target_user: User) -> bool:
        if current_user == target_user:
            return True
        
        friendship = Friendship.get_friendship(current_user, target_user)
        if friendship and friendship.status == Friendship.BLOCKED:
            if friendship.initiator == target_user:
                return False
        
        if getattr(target_user, 'is_profile_public', True):
            return True
        
        return Friendship.are_friends(current_user, target_user)
    
    @classmethod
    def get_block_status(cls, current_user: User, target_user: User) -> Dict[str, Any]:
        if current_user == target_user:
            return {'status': 'self'}
        
        friendship = Friendship.get_friendship(current_user, target_user)
        
        if not friendship or friendship.status != Friendship.BLOCKED:
            return {'status': 'not_blocked'}
        
        if friendship.initiator == current_user:
            return {
                'status': 'blocked_by_me',
                'can_unblock': True,
                'blocked_at': friendship.updated_at
            }
        else:
            return {
                'status': 'blocked_by_them', 
                'can_unblock': False,
                'blocked_at': friendship.updated_at
            }
    
    @classmethod
    def is_blocked_by(cls, current_user: User, target_user: User) -> bool:
        friendship = Friendship.get_friendship(current_user, target_user)
        return (
            friendship and 
            friendship.status == Friendship.BLOCKED and 
            friendship.initiator == target_user
        )
    
    @classmethod 
    def has_blocked(cls, current_user: User, target_user: User) -> bool:
        friendship = Friendship.get_friendship(current_user, target_user)
        return (
            friendship and 
            friendship.status == Friendship.BLOCKED and 
            friendship.initiator == current_user
        )

    @classmethod
    def validate_search_query(cls, query: str, min_length: int = 2) -> Tuple[bool, str]:
        if not query:
            return False, 'Search query (q) parameter required'
        
        if len(query) < min_length:
            return False, f'Search query must be at least {min_length} characters'
        
        return True, 'Valid query'
