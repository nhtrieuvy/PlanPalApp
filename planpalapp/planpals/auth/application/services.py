import logging
from typing import Dict, List, Optional, Tuple, Any
from uuid import UUID

from planpals.shared.base_service import BaseService

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
    def join_group(cls, user, group_id: str = None, invite_code: str = None) -> Tuple[bool, str, Optional[Any]]:
        from planpals.groups.application.services import GroupService
        group_repo = auth_factories.get_auth_group_repo()
        try:
            if invite_code:
                group = group_repo.get_by_invite_code(invite_code)
            else:
                group = group_repo.get_public_by_id(group_id)
            
            if not group:
                return False, "Group not found or not accessible", None
            
            success, message = GroupService.join_group_by_invite(group, user)
            
            if success:
                return True, message, group
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
        return handler.handle(cmd)
    
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
        return handler.handle(cmd)
    
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
