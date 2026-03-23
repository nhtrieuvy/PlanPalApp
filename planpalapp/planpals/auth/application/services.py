import logging
from typing import Dict, List, Optional, Tuple, Any
from uuid import UUID

from planpals.shared.base_service import BaseService
from planpals.shared.cache import CacheKeys, CacheTTL

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
    def get_user_with_counts(cls, user_id: UUID):
        return auth_factories.get_user_repo().get_by_id_with_counts(user_id)

    @classmethod
    def get_user_profile_cached(cls, user_id: UUID):
        """Return user profile data as a cacheable dict.

        On cache hit the dict is returned directly.
        On cache miss the repo data is fetched, serialized to a dict,
        cached, and returned.  The view should return this dict
        as the response payload instead of running a serializer.
        """
        cache_svc = auth_factories.get_cache_service()
        key = CacheKeys.user_profile(user_id)

        def compute():
            user = auth_factories.get_user_repo().get_by_id_with_counts(user_id)
            if not user:
                return None
            return cls._user_to_dict(user)

        return cache_svc.get_or_set(key, compute, CacheTTL.USER_PROFILE)

    @staticmethod
    def _user_to_dict(user) -> dict:
        """Lightweight dict conversion (no DRF serializer dependency)."""
        full_name = user.get_full_name() or user.username
        if user.first_name and user.last_name:
            initials = f"{user.first_name[0]}{user.last_name[0]}".upper()
        elif user.first_name:
            initials = user.first_name[0].upper()
        else:
            initials = user.username[0].upper() if user.username else "U"

        return {
            'id': str(user.id),
            'username': user.username,
            'email': user.email,
            'first_name': user.first_name,
            'last_name': user.last_name,
            'full_name': full_name,
            'initials': initials,
            'phone_number': getattr(user, 'phone_number', ''),
            'avatar': getattr(user, 'avatar', None) and str(user.avatar) or None,
            'avatar_url': getattr(user, 'avatar_url', ''),
            'has_avatar': getattr(user, 'has_avatar', False),
            'date_of_birth': str(user.date_of_birth) if getattr(user, 'date_of_birth', None) else None,
            'bio': getattr(user, 'bio', ''),
            'is_online': getattr(user, 'is_online', False),
            'last_seen': user.last_seen.isoformat() if getattr(user, 'last_seen', None) else None,
            'is_recently_online': getattr(user, 'is_recently_online', False),
            'online_status': getattr(user, 'online_status', 'offline'),
            'plans_count': getattr(user, 'plans_count', 0),
            'personal_plans_count': getattr(user, 'personal_plans_count', 0),
            'group_plans_count': getattr(user, 'group_plans_count', 0),
            'groups_count': getattr(user, 'groups_count', 0),
            'friends_count': getattr(user, 'friends_count', 0),
            'unread_messages_count': getattr(user, 'unread_messages_count', 0),
            'date_joined': user.date_joined.isoformat() if user.date_joined else None,
            'is_active': user.is_active,
        }
    
    @classmethod
    def get_friendship_status(cls, current_user, target_user) -> Dict[str, Any]:
        if current_user == target_user:
            return {'status': 'self'}

        friendship_repo = auth_factories.get_friendship_repo()
        friendship = friendship_repo.get_friendship(current_user.id, target_user.id)

        if not friendship:
            return {'status': 'none'}

        status = friendship.status
        if status == 'accepted':
            return {'status': 'friends', 'since': friendship.created_at}
        if status == 'pending':
            direction = 'pending_sent' if friendship.initiator_id == current_user.id else 'pending_received'
            result = {'status': direction, 'created_at': friendship.created_at}
            if direction == 'pending_received':
                result['friendship_id'] = str(friendship.id)
            return result
        if status == 'rejected':
            return {'status': 'rejected', 'rejected_at': friendship.updated_at}
        if status == 'blocked':
            if friendship.initiator_id == current_user.id:
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
    def send_friend_request(cls, from_user, to_user) -> Tuple[bool, str]:
        """Delegate to SendFriendRequestHandler."""
        cmd = SendFriendRequestCommand(
            from_user_id=from_user.id,
            to_user_id=to_user.id,
        )
        handler = auth_factories.get_send_friend_request_handler()
        return handler.handle(cmd)
    
    @classmethod
    def logout_user(cls, user, token_string: str = None) -> Tuple[bool, str, bool]:
        revoked = False
        online_set = False

        if token_string:
            try:
                token_repo = auth_factories.get_token_repo()
                revoked = token_repo.revoke_access_token(token_string, user.id)
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
    def search_users(cls, query: str, current_user, limit: int = 20):
        return auth_factories.get_user_repo().search(query, exclude_user_id=current_user.id)
    
    @classmethod
    def update_user_profile(cls, user, data: Dict[str, Any]) -> Tuple[Any, bool]:
        user_repo = auth_factories.get_user_repo()
        user, success = user_repo.update_profile(user.id, data)
        if success:
            cls._invalidate_user_cache(user.id)
            cls.log_operation("user_profile_updated", {'user_id': user.id})
        else:
            cls.log_operation("user_profile_update_failed", {'user_id': user.id})
        return user, success
    
    @classmethod
    def get_user_plans(cls, user, plan_type: str = 'all'):
        return auth_factories.get_user_repo().get_user_plans(user.id, plan_type)
    
    @classmethod
    def get_user_groups(cls, user):
        return auth_factories.get_user_repo().get_user_groups(user.id)
    
    @classmethod
    def get_user_activities(cls, user):
        return auth_factories.get_user_repo().get_user_activities(user.id)
    
    @classmethod
    def set_user_online_status(cls, user, is_online: bool) -> bool:
        """Delegate to SetOnlineStatusHandler."""
        cmd = SetOnlineStatusCommand(
            user_id=user.id,
            is_online=is_online,
        )
        handler = auth_factories.get_set_online_status_handler()
        return handler.handle(cmd)
    
    @classmethod
    def get_friendship_stats(cls, user) -> Dict[str, Any]:
        user_with_counts = auth_factories.get_user_repo().get_by_id_with_counts(user.id)
        return {
            'friends_count': user_with_counts.friends_count,
            'pending_sent_count': user_with_counts.pending_sent_count,
            'pending_received_count': user_with_counts.pending_received_count,
            'blocked_count': user_with_counts.blocked_count
        }
    
    @classmethod
    def get_recent_conversations(cls, user):
        return auth_factories.get_user_repo().get_recent_conversations(user.id)
    
    @classmethod
    def get_unread_count(cls, user) -> int:
        return auth_factories.get_user_repo().get_unread_messages_count(user.id)
    
    @classmethod
    def unblock_user(cls, current_user, target_user) -> Tuple[bool, str]:
        """Delegate to UnblockUserHandler."""
        cmd = UnblockUserCommand(
            blocker_id=current_user.id,
            target_id=target_user.id,
        )
        handler = auth_factories.get_unblock_user_handler()
        return handler.handle(cmd)
    
    @classmethod
    def join_group(cls, user, group_id: str) -> Tuple[bool, str, Optional[Any]]:
        from planpals.groups.application.services import GroupService
        group_repo = auth_factories.get_auth_group_repo()
        try:
            group = group_repo.get_by_id(group_id)
            
            if group is None:
                return False, "Group not found", None
            
            success, message, joined_group = GroupService.join_group(user=user, group_id=group_id)
            
            if success:
                return True, message, joined_group
            else:
                return False, message, None
                
        except Exception as e:
            return False, str(e), None
    
    @classmethod
    def accept_friend_request(cls, current_user, from_user) -> Tuple[bool, str]:
        """Delegate to AcceptFriendRequestHandler."""
        cmd = AcceptFriendRequestCommand(
            current_user_id=current_user.id,
            from_user_id=from_user.id,
        )
        handler = auth_factories.get_accept_friend_request_handler()
        result = handler.handle(cmd)
        # Both users' friend counts change
        cls._invalidate_user_cache(current_user.id)
        cls._invalidate_user_cache(from_user.id)
        return result
    
    @classmethod
    def reject_friend_request(cls, current_user, from_user) -> Tuple[bool, str]:
        """Delegate to RejectFriendRequestHandler."""
        cmd = RejectFriendRequestCommand(
            current_user_id=current_user.id,
            from_user_id=from_user.id,
        )
        handler = auth_factories.get_reject_friend_request_handler()
        return handler.handle(cmd)
    
    @classmethod
    def cancel_friend_request(cls, current_user, to_user) -> Tuple[bool, str]:
        """Delegate to CancelFriendRequestHandler."""
        cmd = CancelFriendRequestCommand(
            current_user_id=current_user.id,
            to_user_id=to_user.id,
        )
        handler = auth_factories.get_cancel_friend_request_handler()
        return handler.handle(cmd)

    @classmethod
    def block_user(cls, current_user, target_user) -> Tuple[bool, str]:
        """Delegate to BlockUserHandler."""
        cmd = BlockUserCommand(
            blocker_id=current_user.id,
            target_id=target_user.id,
        )
        handler = auth_factories.get_block_user_handler()
        return handler.handle(cmd)
    
    @classmethod
    def unfriend_user(cls, current_user, target_user) -> Tuple[bool, str]:
        """Delegate to UnfriendHandler."""
        cmd = UnfriendCommand(
            current_user_id=current_user.id,
            target_user_id=target_user.id,
        )
        handler = auth_factories.get_unfriend_handler()
        result = handler.handle(cmd)
        cls._invalidate_user_cache(current_user.id)
        cls._invalidate_user_cache(target_user.id)
        return result
    
    @classmethod
    def is_group_member(cls, user, group) -> bool:
        return group.is_member(user)
    
    @classmethod
    def can_view_profile(cls, current_user, target_user) -> bool:
        if current_user == target_user:
            return True
        
        friendship_repo = auth_factories.get_friendship_repo()
        friendship = friendship_repo.get_friendship(current_user.id, target_user.id)
        if friendship and friendship.status == 'blocked':
            if friendship.initiator_id == target_user.id:
                return False
        
        if getattr(target_user, 'is_profile_public', True):
            return True
        
        return friendship_repo.are_friends(current_user.id, target_user.id)
    
    @classmethod
    def get_block_status(cls, current_user, target_user) -> Dict[str, Any]:
        if current_user == target_user:
            return {'status': 'self'}
        
        friendship_repo = auth_factories.get_friendship_repo()
        friendship = friendship_repo.get_friendship(current_user.id, target_user.id)
        
        if not friendship or friendship.status != 'blocked':
            return {'status': 'not_blocked'}
        
        if friendship.initiator_id == current_user.id:
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
    def is_blocked_by(cls, current_user, target_user) -> bool:
        friendship_repo = auth_factories.get_friendship_repo()
        friendship = friendship_repo.get_friendship(current_user.id, target_user.id)
        return (
            friendship and 
            friendship.status == 'blocked' and 
            friendship.initiator_id == target_user.id
        )
    
    @classmethod 
    def has_blocked(cls, current_user, target_user) -> bool:
        friendship_repo = auth_factories.get_friendship_repo()
        friendship = friendship_repo.get_friendship(current_user.id, target_user.id)
        return (
            friendship and 
            friendship.status == 'blocked' and 
            friendship.initiator_id == current_user.id
        )

    @classmethod
    def validate_search_query(cls, query: str, min_length: int = 2) -> Tuple[bool, str]:
        if not query:
            return False, 'Search query (q) parameter required'
        
        if len(query) < min_length:
            return False, f'Search query must be at least {min_length} characters'
        
        return True, 'Valid query'

    # ------------------------------------------------------------------
    # Cache invalidation helper
    # ------------------------------------------------------------------
    @classmethod
    def _invalidate_user_cache(cls, user_id) -> None:
        try:
            cache_svc = auth_factories.get_cache_service()
            cache_svc.delete(CacheKeys.user_profile(user_id))
        except Exception as e:
            logger.warning("Failed to invalidate user cache for %s: %s", user_id, e)
