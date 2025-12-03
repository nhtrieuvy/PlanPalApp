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

from .models import (
    User, Group, Plan, PlanActivity, ChatMessage, Friendship, GroupMembership, FriendshipRejection, Conversation, MessageReadStatus
)
from .events import RealtimeEvent, EventType, ChannelGroups
from .realtime_publisher import RealtimeEventPublisher, publish_friend_request, publish_friend_request_accepted
from .tasks import start_plan_task, complete_plan_task
from celery import current_app
from .paginators import ManualCursorPaginator
from .serializers import UserSerializer,ChatMessageSerializer, PlanActivitySummarySerializer

from channels.layers import get_channel_layer
from asgiref.sync import async_to_sync
from .integrations import NotificationService

logger = logging.getLogger(__name__)

class BaseService:
    @staticmethod
    def log_operation(operation: str, details: Dict[str, Any] = None):
        logger.info(f"Service operation: {operation}", extra=details or {})
    
    @staticmethod
    def log_error(message: str, error: Exception, details: Dict[str, Any] = None):
        logger.error(f"{message}: {str(error)}", extra=details or {}, exc_info=True)
    
    @staticmethod
    def validate_user_permission(user, resource, permission_type: str) -> bool:
        if not user or not user.is_authenticated:
            return False
        return True


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
        if from_user == to_user:
            return False, "Cannot send friend request to yourself"
        
        existing = Friendship.get_friendship(from_user, to_user)
        
        if existing:
            if existing.status == Friendship.ACCEPTED:
                return False, "Already friends"
            elif existing.status == Friendship.PENDING:
                return False, "Friend request already sent"
            elif existing.status == Friendship.BLOCKED:
                # Check who blocked whom
                if existing.initiator == to_user:
                    return False, "Cannot send friend request - you have been blocked"
                else:
                    return False, "Cannot send friend request - you have blocked this user"
            elif existing.status == Friendship.REJECTED:
                rejection_count = existing.get_rejection_count()
                last_rejection = existing.get_last_rejection()
                
                if last_rejection:
                    time_since_rejection = timezone.now() - last_rejection.created_at
                    
                    if rejection_count >= Friendship.MAX_REJECTION_COUNT:
                        cooldown_period = timezone.timedelta(days=Friendship.EXTENDED_COOLDOWN_DAYS)
                        cooldown_msg = f"Must wait {Friendship.EXTENDED_COOLDOWN_DAYS} days after {rejection_count} rejections"
                    else:
                        cooldown_period = timezone.timedelta(hours=Friendship.REJECTION_COOLDOWN_HOURS)
                        cooldown_msg = f"Must wait {Friendship.REJECTION_COOLDOWN_HOURS} hours after rejection"
                    
                    if time_since_rejection < cooldown_period:
                        remaining_time = cooldown_period - time_since_rejection
                        return False, f"Cannot resend friend request yet. {cooldown_msg}. Time remaining: {remaining_time}"
                
                existing.status = Friendship.PENDING
                existing.initiator = from_user
                existing.save(update_fields=['status', 'initiator', 'updated_at'])
                cls.log_operation("friend_request_resent", {
                    'from_user': from_user.id,
                    'to_user': to_user.id
                })
                # Publish realtime event and push notification for the re-sent friend request
                try:
                    transaction.on_commit(lambda: publish_friend_request(
                        user_id=str(to_user.id),
                        from_user_id=str(from_user.id),
                        from_name=from_user.get_full_name() or from_user.username
                    ))
                except Exception:
                    logger.exception("Failed to schedule friend request event publish")

                return True, "Friend request sent successfully"
        
        try:
            with transaction.atomic():
                if from_user.id < to_user.id:
                    user_a, user_b = from_user, to_user
                else:
                    user_a, user_b = to_user, from_user
                
                friendship = Friendship(
                    user_a=user_a,
                    user_b=user_b,
                    initiator=from_user,
                    status=Friendship.PENDING
                )
                friendship.full_clean()
                friendship.save()

                # Schedule realtime/push publish after DB commit
                try:
                    transaction.on_commit(lambda: publish_friend_request(
                        user_id=str(to_user.id),
                        from_user_id=str(from_user.id),
                        from_name=from_user.get_full_name() or from_user.username
                    ))
                except Exception:
                    logger.exception("Failed to schedule friend request event publish")

        except ValidationError as e:
            return False, str(e)
        
        cls.log_operation("friend_request_sent", {
            'from_user': from_user.id,
            'to_user': to_user.id
        })
        
        return True, "Friend request sent successfully"
    
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

        # Attempt to set user offline; non-fatal if it fails
        try:
            user.set_online_status(False)
            online_set = True
        except Exception as e:
            cls.log_error("Failed to set user offline during logout", e, {'user_id': user.id})

        # Consider logout successful if at least one of the actions succeeded
        if revoked or online_set:
            cls.log_operation("user_logout", {
                'user_id': user.id,
                'token_revoked': revoked,
                'offline_set': online_set
            })
            return True, "Logged out successfully", revoked

        # If neither step succeeded, return failure with logged context
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
        return PlanActivity.objects.filter(
            plan__in=user.viewable_plans
        ).select_related('plan', 'plan__group', 'plan__creator').order_by('-start_time')
    
    @classmethod
    def set_user_online_status(cls, user: User, is_online: bool) -> bool:
        try:
            with transaction.atomic():
                user.set_online_status(is_online)
            return True
        except Exception as e:
            cls.log_operation("set_online_status_failed", {
                'user_id': user.id,
                'error': str(e)
            })
            return False
    
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
        friendship = Friendship.get_friendship(current_user, target_user)
        
        if not friendship or friendship.status != Friendship.BLOCKED:
            return False, "User is not blocked"
        
        if friendship.initiator != current_user:
            return False, "Only the person who blocked can unblock"
        
        friendship.delete()
        
        cls.log_operation("user_unblocked", {
            'blocker': current_user.id,
            'unblocked': target_user.id
        })
        
        return True, "User unblocked successfully"
    
    @classmethod
    def join_group(cls, user: User, group_id: str = None, invite_code: str = None) -> Tuple[bool, str, Optional['Group']]:
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
        try:
            friendship = Friendship.get_friendship(from_user, current_user)
            
            if not friendship:
                return False, "Friend request not found"
            
            if friendship.status != Friendship.PENDING:
                return False, f"Friend request is not pending (status: {friendship.status})"
            
            if friendship.initiator != from_user:
                return False, "You can only accept requests sent to you"
            
            with transaction.atomic():
                friendship.status = Friendship.ACCEPTED
                friendship.save()
                
                # Auto-create direct conversation between new friends
                try:
                    # Import here to avoid circular import
                    conversation, created = ConversationService.get_or_create_direct_conversation(
                        current_user, from_user
                    )
                    if created:
                        cls.log_operation("auto_conversation_created", {
                            'conversation_id': str(conversation.id),
                            'user1': current_user.id,
                            'user2': from_user.id,
                            'trigger': 'friend_request_accepted'
                        })
                except Exception as conv_error:
                    cls.log_error("Error creating conversation after friend acceptance", conv_error)
            
                transaction.on_commit(lambda: publish_friend_request_accepted(
                    str(from_user.id),
                    str(current_user.id),
                    current_user.get_full_name() or current_user.username
                ))
            
            cls.log_operation("friend_request_accepted", {
                'user': current_user.id,
                'from_user': from_user.id
            })
            
            return True, "Friend request accepted"
            
        except Exception as e:
            return False, f"Error accepting friend request: {str(e)}"
    
    @classmethod
    def reject_friend_request(cls, current_user: User, from_user: User) -> Tuple[bool, str]:
        try:
            friendship = Friendship.get_friendship(from_user, current_user)
            
            if not friendship:
                return False, "Friend request not found"
            
            if friendship.status != Friendship.PENDING:
                return False, f"Friend request is not pending (status: {friendship.status})"
            
            if friendship.initiator != from_user:
                return False, "You can only reject requests sent to you"

            with transaction.atomic():
                rejection = FriendshipRejection(
                    friendship=friendship, 
                    rejected_by=current_user
                )
                rejection.full_clean()
                rejection.save()
                
                friendship.status = Friendship.REJECTED
                friendship.save()

            cls.log_operation("friend_request_rejected", {
                'user': current_user.id,
                'from_user': from_user.id
            })
            
            return True, "Friend request rejected"
            
        except Exception as e:
            return False, f"Error rejecting friend request: {str(e)}"
    
    @classmethod
    def cancel_friend_request(cls, current_user: User, to_user: User) -> Tuple[bool, str]:
        try:
            friendship = Friendship.get_friendship(current_user, to_user)
            
            if not friendship:
                return False, "Friend request not found"
            
            if friendship.status != Friendship.PENDING:
                return False, "Friend request is not pending"
            
            if friendship.initiator != current_user:
                return False, "You can only cancel requests you sent"

            friendship.delete()

            cls.log_operation("friend_request_cancelled", {
                'from_user': current_user.id,
                'to_user': to_user.id
            })
            
            return True, "Friend request cancelled"
            
        except Exception as e:
            return False, f"Error cancelling friend request: {str(e)}"

    @classmethod
    def block_user(cls, current_user: User, target_user: User) -> Tuple[bool, str]:
        if current_user == target_user:
            return False, "Cannot block yourself"
        
        with transaction.atomic():
            friendship = Friendship.get_friendship(current_user, target_user)
            
            if friendship:
                if friendship.status == Friendship.BLOCKED and friendship.initiator == current_user:
                    return False, "User is already blocked"
                
                if friendship.status == Friendship.BLOCKED and friendship.initiator == target_user:
                    return False, "You cannot block this user as they have blocked you"
                
                friendship.status = Friendship.BLOCKED
                friendship.initiator = current_user  # Set current user as the blocker
                friendship.save(update_fields=['status', 'initiator', 'updated_at'])
            else:
                if current_user.id < target_user.id:
                    friendship = Friendship.objects.create(
                        user_a=current_user,
                        user_b=target_user,
                        initiator=current_user,
                        status=Friendship.BLOCKED
                    )
                else:
                    friendship = Friendship.objects.create(
                        user_a=target_user,
                        user_b=current_user,
                        initiator=current_user,
                        status=Friendship.BLOCKED
                    )
        
        cls.log_operation("user_blocked", {
            'blocker': current_user.id,
            'blocked': target_user.id
        })
        
        return True, "User blocked successfully"
    
    @classmethod
    def unfriend_user(cls, current_user: User, target_user: User) -> Tuple[bool, str]:
        friendship = Friendship.get_friendship(current_user, target_user)
        
        if not friendship or friendship.status != Friendship.ACCEPTED:
            return False, "Not friends"
        
        friendship.delete()
        
        cls.log_operation("users_unfriended", {
            'user1': current_user.id,
            'user2': target_user.id
        })
        
        return True, "Unfriended successfully"
    
    @classmethod
    def is_group_member(cls, user: User, group: 'Group') -> bool:
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


class GroupService(BaseService):    
    @classmethod
    def create_group(cls, creator: User, name: str, description: str = "", 
                    is_public: bool = False, initial_members: List[User] = None) -> Group:
        with transaction.atomic():
            group = Group.objects.create(
                name=name,
                description=description,
                admin=creator,
                is_public=is_public
            )
            
            GroupMembership.objects.create(
                group=group,
                user=creator,
                role=GroupMembership.ADMIN
            )
            
            if initial_members:
                for user in initial_members:
                    if user != creator:
                        cls.add_member(group, user, role=GroupMembership.MEMBER)
        
        cls.log_operation("group_created", {
            'group_id': group.id,
            'creator': creator.id,
            'initial_members_count': len(initial_members) if initial_members else 0
        })
        
        return group
    
    @classmethod
    def add_member(cls, group: Group, user: User, 
                           role: str = None, added_by: User = None) -> Tuple[bool, str]:        
        if role is None:
            role = GroupMembership.MEMBER
        
        if group.is_member(user):
            return False, "User is already a member"
        
        if added_by and added_by != user:
            if not Friendship.are_friends(added_by, user):
                return False, "Can only add friends to group"
        
        try:
            membership = GroupMembership(
                group=group,
                user=user,
                role=role
            )
            membership.full_clean() 
            membership.save()
        except ValidationError as e:
            return False, str(e)
        
        cls.log_operation("member_added_to_group", {
            'group_id': group.id,
            'user_id': user.id,
            'role': role,
            'added_by': added_by.id if added_by else None
        })
        
        return True, f"User added to group as {role}"
    
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
        if not group.is_admin(removed_by):
            return False, "Permission denied"
        
        if group.admin == user:
            return False, "Cannot remove group admin"
        
        membership = group.get_user_membership(user)
        if not membership:
            return False, "User is not a member of this group"
        
        membership.delete()
        
        cls.log_operation("member_removed_from_group", {
            'group_id': group.id,
            'user_id': user.id,
            'removed_by': removed_by.id
        })
        
        return True, "Member removed from group"
    
    @classmethod
    def join_group_by_invite(cls, group: Group, user: User) -> Tuple[bool, str]:
        if group.is_member(user):
            return False, "Already a member"
        
        return cls.add_member(group, user, GroupMembership.MEMBER)
    
    @classmethod
    @transaction.atomic  
    def leave_group(cls, group: Group, user: User) -> Tuple[bool, str]:
        """
        Member tự rời nhóm
        """
        # Kiểm tra xem user có phải thành viên của nhóm không
        membership = group.get_user_membership(user)
        if not membership:
            return False, "Bạn không phải thành viên của nhóm này"
        
        # Kiểm tra nếu là admin duy nhất thì không được rời
        if membership.role == GroupMembership.ADMIN and group.get_admin_count() <= 1:
            return False, "Bạn là admin duy nhất của nhóm, không thể rời nhóm. Hãy chỉ định admin khác trước khi rời."
        
        # Xóa membership
        membership.delete()
        
        cls.log_operation("member_left_group", {
            'group_id': group.id,
            'user_id': user.id,
        })
        
        return True, "Bạn đã rời nhóm thành công"
    
    @classmethod
    def can_manage_members(cls, group: Group, user: User) -> bool:
        return group.is_admin(user)
    
    @classmethod
    def can_edit_group(cls, group: Group, user: User) -> bool:
        return group.is_admin(user)
    
    
    @classmethod
    @transaction.atomic
    def promote_member(cls, group: Group, user_to_promote: User, actor: User) -> Tuple[bool, str]:
        if not group.is_admin(actor):
            return False, "You do not have permission to promote members."

        membership = group.get_user_membership(user_to_promote)
        if not membership:
            return False, "User is not a member of this group."

        if membership.role == GroupMembership.ADMIN:
            return False, "User is already an admin."

        membership.role = GroupMembership.ADMIN
        membership.save(update_fields=['role', 'updated_at'])

        cls.log_operation("group_member_promoted", {
            'group_id': group.id,
            'user_id': user_to_promote.id,
            'promoted_by': actor.id
        })

        return True, "Member promoted to admin successfully."

    @classmethod
    @transaction.atomic
    def demote_member(cls, group: Group, user_to_demote: User, actor: User) -> Tuple[bool, str]:
        if not group.is_admin(actor):
            return False, "You do not have permission to demote members."
            
        if actor == user_to_demote:
            return False, "You cannot demote yourself."

        membership = group.get_user_membership(user_to_demote)
        if not membership:
            return False, "User is not a member of this group."

        if membership.role != GroupMembership.ADMIN:
            return False, "User is not an admin."
            
        if group.get_admin_count() <= 1:
            return False, "Cannot demote the last admin of the group."

        membership.role = GroupMembership.MEMBER
        membership.save(update_fields=['role', 'updated_at'])

        cls.log_operation("group_member_demoted", {
            'group_id': group.id,
            'user_id': user_to_demote.id,
            'demoted_by': actor.id
        })

        return True, "Admin demoted to member successfully."
    
    @classmethod
    def search_user_groups(cls, user: User, query: str):        
        return Group.objects.filter(
            members=user
        ).filter(
            models.Q(name__icontains=query) |
            models.Q(description__icontains=query)
    ).select_related('admin').prefetch_related('members', 'memberships__user').with_full_stats()
    
    @classmethod
    def get_group_plans(cls, group: 'Group', user: User) -> Dict[str, Any]:
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


class PlanService(BaseService): 
       
    @classmethod
    def create_plan(cls, creator: User, title: str, description: str = "",
                   plan_type: str = 'personal', group: Group = None,
                   start_date=None, end_date=None, budget=None,
                   is_public: bool = False) -> Plan:
        
        if plan_type == 'group' and group:
            if not group.is_member(creator):
                raise ValidationError("You must be a member of the group to create a plan")
        
        try:
            with transaction.atomic():
                plan = Plan(
                    title=title,
                    description=description,
                    creator=creator,
                    plan_type=plan_type,
                    group=group,
                    start_date=start_date,
                    end_date=end_date,
                    is_public=is_public,
                    status='upcoming'
                )
                plan.full_clean()
                plan.save()
                
                cls._schedule_plan_tasks(plan)
        except ValidationError as e:
            raise ValidationError(f"Plan creation failed: {str(e)}")
        
        cls.log_operation("plan_created", {
            'plan_id': plan.id,
            'creator': creator.id,
            'plan_type': plan_type,
            'group_id': group.id if group else None
        })
        
        return plan

    @classmethod
    def update_plan(cls, plan: Plan, data: Dict[str, Any], user: User = None) -> Plan:
        if getattr(plan, 'status', None) == 'completed':
            raise ValidationError("Cannot update a plan that is already completed")

        # Determine whether schedule-affecting fields are changing
        old_start = getattr(plan, 'start_date', None)
        old_end = getattr(plan, 'end_date', None)
        new_start = data.get('start_date', old_start)
        new_end = data.get('end_date', old_end)

        try:
            with transaction.atomic():

                if (('start_date' in data and new_start != old_start) or
                        ('end_date' in data and new_end != old_end)):
                    try:
                        cls.revoke_scheduled_tasks(plan)
                    except Exception as e:
                        logger.warning(f"Failed to revoke existing scheduled tasks for plan {plan.id}: {e}")

                # Apply incoming fields onto the model instance
                for field, value in data.items():
                    # Only set attributes that exist on the model
                    if hasattr(plan, field):
                        setattr(plan, field, value)

                # Validate and persist
                plan.full_clean()
                plan.save()

                # Schedule new tasks as needed (uses the same scheduling helper as create_plan)
                try:
                    cls._schedule_plan_tasks(plan)
                except Exception as e:
                    logger.warning(f"Failed to schedule tasks after updating plan {plan.id}: {e}")

        except ValidationError as e:
            # Surface validation errors to callers
            raise ValidationError(f"Plan update failed: {str(e)}")

        # Log the update operation for audit
        cls.log_operation("plan_updated", {
            'plan_id': str(plan.id),
            'updated_by': str(user.id) if user else None,
            'updated_fields': list(data.keys())
        })

        # Refresh from DB to return canonical instance
        plan.refresh_from_db()
        return plan
    
    @classmethod
    def add_activity_to_plan(cls, plan: Plan, user: User, activity_data: Dict[str, Any]) -> PlanActivity:
        
        if not cls.can_edit_plan(plan, user):
            raise ValidationError("Permission denied to edit this plan")
        
        start_time = activity_data.get('start_time')
        end_time = activity_data.get('end_time')
        
        if start_time and end_time and plan.has_time_conflict(start_time, end_time):
            raise ValidationError("Activity time conflicts with existing activities")
        
        try:
            with transaction.atomic():
                activity = PlanActivity(
                    plan=plan,
                    title=activity_data['title'],
                    description=activity_data.get('description', ''),
                    activity_type=activity_data.get('activity_type', 'other'),
                    start_time=start_time,
                    end_time=end_time,
                    estimated_cost=activity_data.get('estimated_cost'),
                    location_name=activity_data.get('location_name', ''),
                    location_address=activity_data.get('location_address', ''),
                    notes=activity_data.get('notes', '')
                )
                activity.full_clean()
                activity.save()
        except ValidationError as e:
            raise ValidationError(f"Activity creation failed: {str(e)}")
        
        cls.log_operation("activity_added_to_plan", {
            'plan_id': plan.id,
            'activity_id': activity.id,
            'user_id': user.id
        })
        
        def _publish_activity_created():
            try:
                from .realtime_publisher import RealtimeEventPublisher
                from .events import RealtimeEvent, EventType
                
                publisher = RealtimeEventPublisher()
                event = RealtimeEvent(
                    event_type=EventType.ACTIVITY_CREATED,
                    plan_id=str(plan.id),
                    user_id=str(user.id),
                    group_id=str(plan.group_id) if plan.group_id else None,
                    data={
                        'activity_id': str(activity.id),
                        'activity_title': activity.title,
                        'activity_type': activity.activity_type,
                        'plan_id': str(plan.id),
                        'plan_title': plan.title,
                        'created_by': user.get_full_name() or user.username,
                        'created_by_id': str(user.id),
                        'start_time': activity.start_time.isoformat() if activity.start_time else None,
                        'location_name': activity.location_name,
                        'initiator_id': str(user.id)
                    }
                )
                publisher.publish_event(event, send_push=True)
            except Exception as e:
                logger.warning(f"Failed to publish activity created event for activity {activity.id}: {e}")
        
        transaction.on_commit(_publish_activity_created)
        
        return activity
    
    @classmethod
    def add_activity_with_place(cls, plan: Plan, title: str, start_time, end_time, 
                               place_id: str = None, **extra_fields):        
        activity_data = {
            'title': title,
            'start_time': start_time,
            'end_time': end_time,
            **extra_fields
        }
        
        if place_id:
            activity_data['location_name'] = f"Place ID: {place_id}"
        
        with transaction.atomic():
            activity = PlanActivity.objects.create(
                plan=plan,
                title=title,
                start_time=start_time,
                end_time=end_time,
                **{k: v for k, v in extra_fields.items() 
                   if k in ['description', 'activity_type', 'estimated_cost', 
                           'location_name', 'location_address', 'notes']}
            )
        
        cls.log_operation("activity_added_with_place", {
            'plan_id': plan.id,
            'activity_id': activity.id,
            'place_id': place_id
        })
        
        return activity

    
    @classmethod
    def start_trip(cls, plan: Plan, user: User = None, force: bool = False):
        if plan.status != 'upcoming' and not force:
            raise ValueError(f"Cannot start trip in status: {plan.status}")
        
        if not force and plan.start_date and timezone.now() < plan.start_date:
            raise ValueError("Trip start time has not been reached yet")
        
        with transaction.atomic():
            updated_count = Plan.objects.filter(
                pk=plan.pk,
                status='upcoming'
            ).update(
                status='ongoing',
                updated_at=timezone.now()
            )
            
            if updated_count == 0 and not force:
                # Log current DB state for debugging race conditions
                try:
                    latest = Plan.objects.get(pk=plan.pk)
                    logger.warning(f"start_trip update_count=0 for plan {plan.id}: db_status={latest.status} start_date={latest.start_date}")
                except Exception:
                    logger.exception(f"start_trip failed to introspect plan {plan.id} after update_count==0")
                raise ValueError("Plan status was changed by another operation")
            
            plan.refresh_from_db()
            
            try:
                cls._schedule_completion_task(plan)
            except Exception as e:
                logger.warning(f"Failed to schedule completion task for plan {plan.id}: {e}")
        
        cls.log_operation("trip_started", {
            'plan_id': str(plan.id),
            'user_id': str(user.id) if user else None,
            'forced': force,
            'timestamp': timezone.now().isoformat()
        })
        
        def _publish_start_event():
            try:
                publisher = RealtimeEventPublisher()
                event = RealtimeEvent(
                    event_type=EventType.PLAN_STATUS_CHANGED,
                    plan_id=str(plan.id),
                    user_id=str(user.id) if user else None,
                    group_id=str(plan.group_id) if plan.group_id else None,
                    data={
                        'plan_id': str(plan.id),
                        'title': plan.title,
                        'old_status': 'upcoming',
                        'new_status': 'ongoing',
                        'started_by': str(user.id) if user else 'system',
                        'started_by_name': user.get_full_name() or user.username if user else 'System',
                        'timestamp': timezone.now().isoformat(),
                        'forced': force,
                        'initiator_id': str(user.id) if user else None
                    }
                )
                publisher.publish_event(event, send_push=True)
            except Exception as e:
                logger.warning(f"Failed to publish start event for plan {plan.id}: {e}")
        
        transaction.on_commit(_publish_start_event)
        
        return plan
    
    @classmethod
    def complete_trip(cls, plan: Plan, user: User = None, force: bool = False):
        if plan.status != 'ongoing' and not force:
            raise ValueError(f"Cannot complete trip in status: {plan.status}")
        
        if not force and plan.end_date and timezone.now() < plan.end_date:
            raise ValueError("Trip end time has not been reached yet")
        
        with transaction.atomic():
            updated_count = Plan.objects.filter(
                pk=plan.pk,
                status='ongoing'
            ).update(
                status='completed',
                updated_at=timezone.now()
            )
            
            if updated_count == 0 and not force:
                try:
                    latest = Plan.objects.get(pk=plan.pk)
                    logger.warning(f"complete_trip update_count=0 for plan {plan.id}: db_status={latest.status} end_date={latest.end_date}")
                except Exception:
                    logger.exception(f"complete_trip failed to introspect plan {plan.id} after update_count==0")
                raise ValueError("Plan status was changed by another operation")
            
            plan.refresh_from_db()
            
            try:
                cls._revoke_plan_tasks(plan)
            except Exception as e:
                logger.warning(f"Failed to revoke tasks for plan {plan.id}: {e}")
        
        cls.log_operation("trip_completed", {
            'plan_id': str(plan.id),
            'user_id': str(user.id) if user else None,
            'forced': force,
            'timestamp': timezone.now().isoformat()
        })
        
        def _publish_complete_event():
            try:
                publisher = RealtimeEventPublisher()
                event = RealtimeEvent(
                    event_type=EventType.PLAN_STATUS_CHANGED,
                    plan_id=str(plan.id),
                    user_id=str(user.id) if user else None,
                    group_id=str(plan.group_id) if plan.group_id else None,
                    data={
                        'plan_id': str(plan.id),
                        'title': plan.title,
                        'old_status': 'ongoing',
                        'new_status': 'completed',
                        'completed_by': str(user.id) if user else 'system',
                        'completed_by_name': user.get_full_name() or user.username if user else 'System',
                        'timestamp': timezone.now().isoformat(),
                        'forced': force,
                        'initiator_id': str(user.id) if user else None
                    }
                )
                publisher.publish_event(event, send_push=True)
            except Exception as e:
                logger.warning(f"Failed to publish complete event for plan {plan.id}: {e}")
        
        transaction.on_commit(_publish_complete_event)
        
        return plan
    
    @classmethod
    def cancel_trip(cls, plan: Plan, user: User = None, reason: str = None, force: bool = False):
        if user and not cls.can_edit_plan(plan, user):
            raise ValueError("Permission denied to cancel this plan")
        
        if plan.status in ['cancelled', 'completed'] and not force:
            raise ValueError(f"Cannot cancel plan that is already {plan.status}")
        
        with transaction.atomic():
            # Atomic status update
            updated_count = Plan.objects.filter(
                pk=plan.pk
            ).exclude(
                status__in=['cancelled'] if not force else []
            ).update(
                status='cancelled',
                updated_at=timezone.now()
            )
            
            if updated_count == 0 and not force:
                raise ValueError("Plan was already cancelled or status changed")
            
            # Refresh plan instance
            plan.refresh_from_db()
            
            # Revoke any scheduled tasks
            try:
                cls._revoke_plan_tasks(plan)
            except Exception as e:
                logger.warning(f"Failed to revoke tasks for plan {plan.id}: {e}")
        
        cls.log_operation("trip_cancelled", {
            'plan_id': str(plan.id),
            'user_id': str(user.id) if user else None,
            'reason': reason,
            'forced': force,
            'timestamp': timezone.now().isoformat()
        })
        
        return plan
    
    @classmethod
    def can_view_plan(cls, plan: Plan, user: User) -> bool:
        if plan.is_public:
            return True
        
        if plan.creator == user:
            return True
        
        return user in plan.collaborators
    
    @classmethod
    def can_edit_plan(cls, plan: Plan, user: User) -> bool:
        if plan.creator == user:
            return True
        
        if plan.is_group_plan() and plan.group:
            return plan.group.is_admin(user)
        
        return False
    
    @classmethod
    def get_plan_statistics(cls, plan: Plan) -> Dict[str, Any]:
        plan_with_stats = Plan.objects.with_stats().get(id=plan.id)
        
        activities_count = plan_with_stats.activities_count
        total_cost = plan_with_stats.total_estimated_cost
        
        completed_activities = plan.activities.filter(is_completed=True).count()
        completion_rate = (completed_activities / activities_count * 100) if activities_count > 0 else 0
        
        return {
            'activities': {
                'total': activities_count,
                'completed': completed_activities,
                'completion_rate': completion_rate
            },
            'budget': {
                'estimated': float(total_cost),
                'over_budget': False
            },
            'duration': {
                'days': plan.duration_days,
                'start_date': plan.start_date,
                'end_date': plan.end_date
            },
            'status': plan.status,
            'collaboration': {
                'type': plan.plan_type,
                'group_id': plan.group.id if plan.group else None,
                'collaborators_count': len(plan.collaborators)
            }
        }
    
    @classmethod
    def get_plan_schedule(cls, plan: 'Plan', user: User) -> Dict[str, Any]:      
        activities = plan.activities.order_by('start_time')
        
        schedule_by_date = {}
        for activity in activities:
            if activity.start_time:
                activity_date = activity.start_time.date()
                date_str = activity_date.strftime('%Y-%m-%d')
                
                if date_str not in schedule_by_date:
                    schedule_by_date[date_str] = {
                        'date': date_str,
                        'activities': []
                    }
                
                # Use summary serializer for lightweight data
                activity_data = PlanActivitySummarySerializer(activity).data
                schedule_by_date[date_str]['activities'].append(activity_data)
        
        total_activities = activities.count()
        completed_activities = activities.filter(is_completed=True).count()
        
        total_duration = 0
        for activity in activities:
            if activity.start_time and activity.end_time:
                duration_delta = activity.end_time - activity.start_time
                total_duration += int(duration_delta.total_seconds() / 60)
        
        return {
            'plan_id': str(plan.id),
            'plan_title': plan.title,
            'schedule_by_date': schedule_by_date,
            'statistics': {
                'total_activities': total_activities,
                'completed_activities': completed_activities,
                'completion_rate': (completed_activities / total_activities * 100) if total_activities > 0 else 0,
                'total_duration_minutes': total_duration,
                'total_duration_display': f"{total_duration // 60}h {total_duration % 60}m" if total_duration > 0 else "0m",
                'date_range': {
                    'start_date': plan.start_date,
                    'end_date': plan.end_date,
                    'duration_days': plan.duration_days
                }
            },
            'permissions': {
                'can_edit': cls.can_edit_plan(plan, user),
                'can_add_activity': cls.can_edit_plan(plan, user)
            }
        }
    
    
    @classmethod
    def get_plans_needing_updates(cls):
        return Plan.objects.plans_need_status_update()
    
    @classmethod
    def revoke_scheduled_tasks(cls, plan: Plan) -> None:
        
        old_start_id = plan.scheduled_start_task_id
        old_end_id = plan.scheduled_end_task_id
        
        for task_id in (old_start_id, old_end_id):
            if not task_id:
                continue
            try:
                current_app.control.revoke(task_id, terminate=False)
            except Exception:
                pass

        updates = {}
        if old_start_id:
            updates['scheduled_start_task_id'] = None
        if old_end_id:
            updates['scheduled_end_task_id'] = None
            
        if updates:
            Plan.objects.filter(
                pk=plan.pk,
                scheduled_start_task_id=old_start_id,
                scheduled_end_task_id=old_end_id
            ).update(**updates)
    
    @classmethod
    def refresh_plan_status(cls, plan: Plan) -> bool:
        if not cls.needs_status_update(plan):
            return False
            
        old_status = plan.status
        new_status = cls.get_expected_status(plan)
        
        if new_status != old_status:
            plan.status = new_status
            plan.save(update_fields=['status', 'updated_at'])
            
            cls.log_operation("plan_status_refreshed", {
                'plan_id': plan.id,
                'old_status': old_status,
                'new_status': new_status
            })
            
            return True
        return False
    
    @classmethod
    def needs_status_update(cls, plan: Plan) -> bool:
        if not (plan.start_date and plan.end_date):
            return False
            
        now = timezone.now()
        return (
            (plan.status == 'upcoming' and now >= plan.start_date) or
            (plan.status == 'ongoing' and now > plan.end_date)
        )
    
    @classmethod
    def get_expected_status(cls, plan: Plan) -> str:
        if not (plan.start_date and plan.end_date):
            return plan.status
            
        now = timezone.now()
        if now < plan.start_date:
            return 'upcoming'
        elif now <= plan.end_date:
            return 'ongoing'
        else:
            return 'completed'
    
    @classmethod
    def get_plans_needing_updates(cls):
        return Plan.objects.plans_need_status_update()
    
    
    @classmethod
    def _schedule_plan_tasks(cls, plan: Plan):
        try:
            def _do_schedule():
                scheduled_start_id = None
                scheduled_end_id = None

                try:
                    if plan.start_date:
                        # Log the planned times for easier debugging
                        start_task = start_plan_task.apply_async(args=[str(plan.id)], eta=plan.start_date)
                        scheduled_start_id = start_task.id

                    if plan.end_date:
                        end_task = complete_plan_task.apply_async(args=[str(plan.id)], eta=plan.end_date)
                        scheduled_end_id = end_task.id

                    updates = {}
                    if scheduled_start_id:
                        updates['scheduled_start_task_id'] = scheduled_start_id
                    if scheduled_end_id:
                        updates['scheduled_end_task_id'] = scheduled_end_id

                    if updates:
                        Plan.objects.filter(pk=plan.pk).update(**updates)

                except Exception as exc:
                    cls.log_operation("task_scheduling_failed", {
                        'plan_id': plan.id,
                        'error': str(exc)
                    })

            transaction.on_commit(_do_schedule)

        except Exception as e:
            cls.log_operation("task_scheduling_failed", {
                'plan_id': plan.id,
                'error': str(e)
            })
    
    @classmethod
    def _revoke_plan_tasks(cls, plan: Plan):
        old_start_id = plan.scheduled_start_task_id
        old_end_id = plan.scheduled_end_task_id
        
        for task_id in (old_start_id, old_end_id):
            if not task_id:
                continue
            try:
                current_app.control.revoke(task_id, terminate=False)
            except Exception:
                pass

        Plan.objects.filter(pk=plan.pk).update(
            scheduled_start_task_id=None,
            scheduled_end_task_id=None
        )
    
    @classmethod
    def _schedule_completion_task(cls, plan: Plan):
        if not plan.end_date:
            return
            
        try:            
            def _do_schedule_completion():
                try:
                    if plan.scheduled_end_task_id:
                        try:
                            current_app.control.revoke(plan.scheduled_end_task_id, terminate=False)
                        except Exception:
                            pass

                    end_task = complete_plan_task.apply_async(args=[str(plan.id)], eta=plan.end_date)

                    Plan.objects.filter(pk=plan.pk).update(scheduled_end_task_id=end_task.id)
                except Exception as exc:
                    logger.warning(f"Failed to schedule completion task for plan {plan.id}: {exc}")

            transaction.on_commit(_do_schedule_completion)

        except Exception as e:
            logger.warning(f"Failed to schedule completion task: {e}")
    
    @classmethod
    def update_activity(cls, plan: 'Plan', activity_id: str, user: User, data: Dict[str, Any]) -> Tuple[bool, str, Optional['PlanActivity']]:        
        if not cls.can_edit_plan(plan, user):
            return False, "You do not have permission to modify this plan", None
        
        try:
            plan_activity = plan.activities.get(id=activity_id)
        except PlanActivity.DoesNotExist:
            return False, "Activity not found in this plan", None
        
        # Update fields
        old_values = {}
        for field, value in data.items():
            if hasattr(plan_activity, field):
                old_values[field] = getattr(plan_activity, field, None)
                setattr(plan_activity, field, value)
        
        plan_activity.save()
        
        cls.log_operation("activity_updated", {
            'plan_id': plan.id,
            'activity_id': activity_id,
            'user_id': user.id
        })
        
        def _publish_activity_updated():
            try:
                publisher = RealtimeEventPublisher()
                event = RealtimeEvent(
                    event_type=EventType.ACTIVITY_UPDATED,
                    plan_id=str(plan.id),
                    user_id=str(user.id),
                    group_id=str(plan.group_id) if plan.group_id else None,
                    data={
                        'activity_id': str(plan_activity.id),
                        'activity_title': plan_activity.title,
                        'activity_type': plan_activity.activity_type,
                        'plan_id': str(plan.id),
                        'plan_title': plan.title,
                        'updated_by': user.get_full_name() or user.username,
                        'updated_by_id': str(user.id),
                        'updated_fields': list(data.keys()),
                        'start_time': plan_activity.start_time.isoformat() if plan_activity.start_time else None,
                        'location_name': plan_activity.location_name,
                        'initiator_id': str(user.id)
                    }
                )
                publisher.publish_event(event, send_push=True)
            except Exception as e:
                logger.warning(f"Failed to publish activity updated event for activity {plan_activity.id}: {e}")
        
        transaction.on_commit(_publish_activity_updated)
        
        return True, "Activity updated successfully", plan_activity
    
    @classmethod
    def remove_activity(cls, plan: 'Plan', activity_id: str, user: User) -> Tuple[bool, str]:        
        if not cls.can_edit_plan(plan, user):
            return False, "You do not have permission to modify this plan"
        
        try:
            plan_activity = plan.activities.get(id=activity_id)
        except PlanActivity.DoesNotExist:
            return False, "Activity not found in this plan"
        
        activity_title = plan_activity.title
        activity_type = plan_activity.activity_type
        plan_activity.delete()
        
        cls.log_operation("activity_removed", {
            'plan_id': plan.id,
            'activity_id': activity_id,
            'activity_title': activity_title,
            'user_id': user.id
        })
        
        def _publish_activity_deleted():
            try:
                from .realtime_publisher import RealtimeEventPublisher
                from .events import RealtimeEvent, EventType
                
                publisher = RealtimeEventPublisher()
                event = RealtimeEvent(
                    event_type=EventType.ACTIVITY_DELETED,
                    plan_id=str(plan.id),
                    user_id=str(user.id),
                    group_id=str(plan.group_id) if plan.group_id else None,
                    data={
                        'activity_id': activity_id,
                        'activity_title': activity_title,
                        'activity_type': activity_type,
                        'plan_id': str(plan.id),
                        'plan_title': plan.title,
                        'deleted_by': user.get_full_name() or user.username,
                        'deleted_by_id': str(user.id),
                        'initiator_id': str(user.id)
                    }
                )
                publisher.publish_event(event, send_push=True)
            except Exception as e:
                logger.warning(f"Failed to publish activity deleted event for activity {activity_id}: {e}")
        
        transaction.on_commit(_publish_activity_deleted)
        
        return True, f'Activity "{activity_title}" removed from plan'
    
    @classmethod
    def toggle_activity_completion(cls, plan: 'Plan', activity_id: str, user: User) -> Tuple[bool, str, Optional['PlanActivity']]:        
        if not cls.can_edit_plan(plan, user):
            return False, "You do not have permission to modify this plan", None
        
        try:
            plan_activity = plan.activities.get(id=activity_id)
        except PlanActivity.DoesNotExist:
            return False, "Activity not found in this plan", None
        
        plan_activity.is_completed = not plan_activity.is_completed
        plan_activity.completed_at = timezone.now() if plan_activity.is_completed else None
        plan_activity.save()
        
        status_text = "completed" if plan_activity.is_completed else "incomplete"
        
        cls.log_operation("activity_completion_toggled", {
            'plan_id': plan.id,
            'activity_id': activity_id,
            'is_completed': plan_activity.is_completed,
            'user_id': user.id
        })
        
        if plan_activity.is_completed:
            def _publish_activity_completed():
                try:
                    publisher = RealtimeEventPublisher()
                    event = RealtimeEvent(
                        event_type=EventType.ACTIVITY_COMPLETED,
                        plan_id=str(plan.id),
                        user_id=str(user.id),
                        group_id=str(plan.group_id) if plan.group_id else None,
                        data={
                            'activity_id': str(plan_activity.id),
                            'activity_title': plan_activity.title,
                            'activity_type': plan_activity.activity_type,
                            'plan_id': str(plan.id),
                            'plan_title': plan.title,
                            'completed_by': user.get_full_name() or user.username,
                            'completed_by_id': str(user.id),
                            'completed_at': plan_activity.completed_at.isoformat() if plan_activity.completed_at else None,
                            'location_name': plan_activity.location_name,
                            'initiator_id': str(user.id)
                        }
                    )
                    publisher.publish_event(event, send_push=True)
                except Exception as e:
                    logger.warning(f"Failed to publish activity completed event for activity {plan_activity.id}: {e}")
            
            transaction.on_commit(_publish_activity_completed)
        
        return True, f'Activity marked as {status_text}', plan_activity
    
    @classmethod
    def get_joined_plans(cls, user: User, search: str = None):        
        group_plans = Plan.objects.filter(
            plan_type='group',
            group__members=user
        ).exclude(creator=user).distinct()
        
        if search:
            group_plans = group_plans.filter(
                models.Q(title__icontains=search) |
                models.Q(description__icontains=search)
            )
        
        return group_plans
    
    @classmethod
    def get_public_plans(cls, user: User, search: str = None):
        
        public_plans = Plan.objects.filter(
            is_public=True,
            status__in=['upcoming', 'ongoing']
        ).exclude(creator=user)
        
        public_plans = public_plans.exclude(
            plan_type='group',
            group__members=user
        )
        
        if search:
            public_plans = public_plans.filter(
                models.Q(title__icontains=search) |
                models.Q(description__icontains=search)
            )
        
        return public_plans.order_by('-created_at')
    
    @classmethod
    def join_plan(cls, plan: 'Plan', user: User) -> Tuple[bool, str]:

        if plan.creator == user:
            return False, "Cannot join your own plan"
        
        if plan.plan_type == 'group' and plan.group:
            if plan.group.members.filter(id=user.id).exists():
                return False, "You are already a member of this plan"
            
            # Add user to group
            GroupMembership.objects.create(
                group=plan.group,
                user=user,
                role=GroupMembership.MEMBER
            )
            
            cls.log_operation("plan_joined", {
                'plan_id': plan.id,
                'user_id': user.id,
                'group_id': plan.group.id
            })
            
            return True, f'Successfully joined plan "{plan.title}"'
        
        return False, "This plan is not joinable"


# Helper functions for attachment handling
def is_local_path(attachment_value: str) -> bool:
    if not attachment_value or not isinstance(attachment_value, str):
        return False
    
    local_patterns = [
        r'^file://',  # file:// protocol
        r'^/data/user/',  # Android app data
        r'^/storage/emulated/',  # Android storage
        r'\\AppData\\Local\\Temp\\',  # Windows temp paths
        r'^/tmp/',  # Unix temp paths
        r'^/var/folders/',  # macOS temp paths
        r'^C:\\Users\\.*\\AppData\\',  # Windows user data
        r'^/Users/.*/Library/Caches/',  # macOS cache paths
    ]
    
    for pattern in local_patterns:
        if re.search(pattern, attachment_value, re.IGNORECASE):
            return True
    
    if ('/' in attachment_value or '\\' in attachment_value) and not attachment_value.startswith(('http://', 'https://')):
        if not attachment_value.startswith('/') and '\\' not in attachment_value:
            return False
        return True
    
    return False



class ConversationService(BaseService):
    
    @classmethod
    def create_message(cls, conversation: 'Conversation', sender: User, 
                      validated_data: Dict[str, Any]) -> 'ChatMessage':
        message_type = validated_data.get('message_type', 'text')
        content = validated_data.get('content', '')
        attachment = validated_data.get('attachment')
        attachment_name = validated_data.get('attachment_name', '')
        attachment_size = validated_data.get('attachment_size')
        reply_to_id = validated_data.get('reply_to_id')
        latitude = validated_data.get('latitude')
        longitude = validated_data.get('longitude')
        location_name = validated_data.get('location_name', '')
        
        
        # Validate reply_to
        reply_to = None
        if reply_to_id:
            try:
                reply_to = ChatMessage.objects.get(
                    id=reply_to_id, 
                    conversation=conversation,
                    is_deleted=False
                )
            except ChatMessage.DoesNotExist:
                raise ValidationError("Reply message not found in this conversation")
        
        if attachment:
            if isinstance(attachment, str):
                attachment = attachment.strip()
                if cls.is_local_path(attachment):
                    raise ValidationError(
                        "Local file paths are not allowed. Please upload the file via multipart request."
                    )
                # Allow Cloudinary URLs/public_ids
            elif isinstance(attachment, UploadedFile):
                # File upload - will be handled by CloudinaryField on save
                pass
            else:
                raise ValidationError("Attachment must be a file upload or valid URL/public_id")
        
        with transaction.atomic():
            message = ChatMessage.objects.create(
                conversation=conversation,
                sender=sender,
                message_type=message_type,
                content=content,
                attachment=attachment,
                attachment_name=attachment_name,
                attachment_size=attachment_size,
                reply_to=reply_to,
                latitude=latitude,
                longitude=longitude,
                location_name=location_name
            )
            
            cls.update_last_message_time(conversation)
            
        transaction.on_commit(lambda: cls._send_realtime_message(message))
        transaction.on_commit(lambda: cls._send_push_notification(message))
        
        cls.log_operation("message_created", {
            'conversation_id': str(conversation.id),
            'message_id': str(message.id),
            'sender_id': str(sender.id) if sender else None,
            'message_type': message_type
        })
        
        return message
    
    @classmethod
    def get_user_conversations(cls, user: User) -> QuerySet['Conversation']:
        return Conversation.objects.for_user(user).with_last_message().order_by('-last_message_at')
    
    @classmethod
    def search_user_conversations(cls, user: User, query: str) -> QuerySet['Conversation']:
        """Search conversations by name, participant names, or group names"""
        if not query or not query.strip():
            return cls.get_user_conversations(user)
        
        query = query.strip().lower()
        conversations = cls.get_user_conversations(user)
        
        search_conditions = Q()
        
        search_conditions |= Q(name__icontains=query)
        
        search_conditions |= Q(group__name__icontains=query)
        
    
        search_conditions |= Q(
            group__members__first_name__icontains=query
        ) | Q(
            group__members__last_name__icontains=query
        ) | Q(
            group__members__username__icontains=query
        )
        
        # For direct conversations, also search the other participant
        search_conditions |= Q(
            user_a__first_name__icontains=query
        ) | Q(
            user_a__last_name__icontains=query
        ) | Q(
            user_a__username__icontains=query
        ) | Q(
            user_b__first_name__icontains=query
        ) | Q(
            user_b__last_name__icontains=query
        ) | Q(
            user_b__username__icontains=query
        )
        
        return conversations.filter(search_conditions).distinct()
    
    @classmethod
    def get_or_create_direct_conversation(cls, user1: User, user2: User) -> Tuple['Conversation', bool]:
        if user1 == user2:
            raise ValueError("Cannot create conversation with yourself")
        
        friendship = Friendship.objects.filter(
            Q(user_a=user1, user_b=user2) | Q(user_a=user2, user_b=user1),
            status=Friendship.ACCEPTED
        ).first()
        
        if not friendship:
            raise ValidationError("Users must be friends to start a conversation")
        
        # Check for existing conversation
        existing_conv = Conversation.objects.get_direct_conversation(user1, user2)
        if existing_conv:
            return existing_conv, False
        
        conversation = cls.create_direct_conversation(user1, user2)
        
        cls.log_operation("conversation_created", {
            'conversation_id': str(conversation.id),
            'type': 'direct',
            'participants': [str(user1.id), str(user2.id)]
        })
        
        return conversation, True
    
    @classmethod 
    def create_direct_conversation(cls, user1: User, user2: User) -> 'Conversation':
        if user1.id == user2.id:
            raise ValidationError("Cannot create conversation with same user")

        conversation = Conversation.objects.create(
            conversation_type='direct',
            user_a=user1,
            user_b=user2
        )
        
        return conversation
    
    @classmethod
    def get_or_create_group_conversation(cls, group: 'Group') -> Tuple['Conversation', bool]:
        if hasattr(group, 'conversation') and group.conversation:
            return group.conversation, False
        
        conversation = Conversation.objects.create(
            conversation_type='group',
            group=group,
            name=f"Group Chat: {group.name}"
        )
        
        cls.log_operation("conversation_created", {
            'conversation_id': str(conversation.id),
            'type': 'group',
            'group_id': str(group.id)
        })
        
        return conversation, True

    

    @classmethod
    def get_conversation_messages(cls, user: User, conversation_id: str, 
                                limit: int = 50, before_id: str = None) -> Dict[str, Any]:
        try:            
            conversation = Conversation.objects.get(id=conversation_id)
            
            if not cls._can_user_access_conversation(user, conversation):
                raise ValidationError("Access denied to this conversation")
            
            queryset = ChatMessage.objects.filter(
                conversation=conversation,
                is_deleted=False
            ).select_related('sender', 'reply_to__sender').order_by('-created_at', '-id')
            
            result = ManualCursorPaginator.paginate_by_id(
                queryset=queryset,
                before_id=before_id,
                limit=limit,
                ordering='-created_at'
            )
            
            return {
                'messages': result['items'],
                'has_more': result['has_more'],
                'next_cursor': result['next_cursor'],
                'count': result['count']
            }
            
        except Conversation.DoesNotExist:
            raise ValidationError("Conversation not found")
    

    @classmethod
    def mark_messages_read(cls, user: User, conversation_id: str, message_ids: List[str]) -> Tuple[bool, str]:
        try:
            conversation = Conversation.objects.get(id=conversation_id)
            
            if not cls._can_user_access_conversation(user, conversation):
                return False, "Access denied to this conversation"
            
            messages = ChatMessage.objects.filter(
                id__in=message_ids,
                conversation=conversation
            ).exclude(sender=user)
            
            for message in messages:
                MessageReadStatus.objects.get_or_create(
                    message=message,
                    user=user
                )
            
            user.clear_unread_cache()
            
            cls.log_operation("messages_marked_read", {
                'user_id': str(user.id),
                'conversation_id': str(conversation.id),
                'message_count': len(message_ids)
            })
            
            return True, f"Marked {len(message_ids)} messages as read"
            
        except Conversation.DoesNotExist:
            return False, "Conversation not found"
        except Exception as e:
            return False, "Failed to mark messages as read"
    
    @classmethod
    def mark_as_read_for_user(cls, conversation, user, up_to_message=None):
        messages = conversation.messages.active().exclude(sender=user)

        if up_to_message:
            messages = messages.filter(created_at__lte=up_to_message.created_at)
        
        unread_message_ids = messages.exclude(
            read_statuses__user=user
        ).values_list('id', flat=True)
        
        if unread_message_ids:
            read_statuses = [
                MessageReadStatus(message_id=msg_id, user=user)
                for msg_id in unread_message_ids
            ]
            MessageReadStatus.objects.bulk_create(read_statuses, ignore_conflicts=True)
            
            user.clear_unread_cache()
        
        return len(unread_message_ids)
    
    @classmethod
    def get_unread_count_for_user(cls, conversation, user):
        return conversation.messages.unread_for_user(user).count()
    

    @classmethod
    def update_last_message_time(cls, conversation, timestamp=None):
        if timestamp is None:
            timestamp = timezone.now()
            
        if not conversation.last_message_at or timestamp > conversation.last_message_at:
            conversation.last_message_at = timestamp
            conversation.save(update_fields=['last_message_at'])
    
    @classmethod
    def _can_user_access_conversation(cls, user: User, conversation: 'Conversation') -> bool:
        if conversation.conversation_type == 'direct':
            return conversation.user_a == user or conversation.user_b == user
        elif conversation.conversation_type == 'group' and conversation.group:
            return conversation.group.members.filter(id=user.id).exists()
        return False
    
    @classmethod
    def _send_realtime_message(cls, message: 'ChatMessage'):
        try:
            channel_layer = get_channel_layer()
            if not channel_layer:
                return
            
            # Serialize message
            serializer = ChatMessageSerializer(message)
            message_data = serializer.data
            
            # Send to conversation channel
            group_name = ChannelGroups.conversation(str(message.conversation.id))
            async_to_sync(channel_layer.group_send)(
                group_name,
                {
                    'type': 'chat_message',
                    'data': message_data
                }
            )
            
        except Exception as e:
            cls.log_error("Error sending realtime message", e)
    
    @classmethod
    def _send_push_notification(cls, message: 'ChatMessage'):
        try:
            
            notification_service = NotificationService()
            
            # Get other participants (exclude sender)
            participants = message.conversation.participants.exclude(id=message.sender.id)
            
            # Send notification to each participant
            for participant in participants:
                if hasattr(participant, 'fcm_token') and participant.fcm_token:
                    
                    if message.conversation.conversation_type == 'direct':
                        title = f"Tin nhắn từ {message.sender.get_full_name() or message.sender.username}"
                    else:
                        group_name = message.conversation.group.name if message.conversation.group else "Nhóm"
                        title = f"{message.sender.get_full_name() or message.sender.username} trong {group_name}"
                    
                    # Format message content based on type
                    if message.message_type == 'text':
                        body = message.content[:100]
                    elif message.message_type == 'image':
                        body = "📷 Đã gửi một hình ảnh"
                    elif message.message_type == 'location':
                        body = f"📍 Đã chia sẻ vị trí: {message.location_name or 'Vị trí'}"
                    elif message.message_type == 'file':
                        body = f"📎 Đã gửi file: {message.attachment_name or 'File'}"
                    else:
                        body = "Đã gửi một tin nhắn"
                    
                    data = {
                        'action': 'new_message',
                        'conversation_id': str(message.conversation.id),
                        'message_id': str(message.id),
                        'sender_id': str(message.sender.id)
                    }
                    
                    notification_service.send_push_notification(
                        [participant.fcm_token],
                        title,
                        body,
                        data
                    )
                    
        except Exception as e:
            cls.log_error("Error sending push notification", e)


class ChatService(BaseService):
    
    @classmethod
    def send_message(cls, sender: User, group: 'Group', **validated_data) -> 'ChatMessage':

        # Get or create group conversation
        conversation, created = ConversationService.get_or_create_group_conversation(group)
        
        # Delegate to canonical message creation
        return ConversationService.create_message(
            conversation=conversation,
            sender=sender,
            validated_data=validated_data
        )
    
    @classmethod
    def send_direct_message(cls, sender: User, recipient: User, **validated_data) -> 'ChatMessage':

        conversation, created = ConversationService.get_or_create_direct_conversation(sender, recipient)
        
        return ConversationService.create_message(
            conversation=conversation,
            sender=sender,
            validated_data=validated_data
        )
    
    @classmethod
    def create_system_message(cls, conversation: 'Conversation' = None, group: 'Group' = None, content: str = "") -> 'ChatMessage':
        if conversation is None and group is None:
            raise ValueError("Either conversation or group must be provided")
        
        if group is not None:
            conversation, created = ConversationService.get_or_create_group_conversation(group)
        
        validated_data = {
            'message_type': 'system',
            'content': content
        }
        
        return ConversationService.create_message(
            conversation=conversation,
            sender=None,  # System messages have no sender
            validated_data=validated_data
        )
    
    @classmethod
    def get_group_messages(cls, user: User, group_id: str, limit: int = 50, before_id: str = None) -> Dict[str, Any]:
        try:            
            group = Group.objects.get(id=group_id)
            
            if not group.members.filter(id=user.id).exists():
                raise ValidationError("Group not found or access denied")
            
            # Get or create group conversation
            conversation, created = ConversationService.get_or_create_group_conversation(group)
            
            # Use conversation service
            return ConversationService.get_conversation_messages(
                user=user,
                conversation_id=str(conversation.id),
                limit=limit,
                before_id=before_id
            )
            
        except Group.DoesNotExist:
            raise ValidationError("Group not found")
    
    @classmethod
    def edit_message(cls, message: ChatMessage, user: User, new_content: str) -> Tuple[bool, str]:
        if message.sender != user:
            return False, "Can only edit your own messages"
        
        edit_deadline = message.created_at + timezone.timedelta(minutes=15)
        if timezone.now() > edit_deadline:
            return False, "Message edit time expired (15 minutes limit)"
        
        if message.message_type == 'system':
            return False, "Cannot edit system messages"
        
        message.content = new_content
        message.is_edited = True
        message.save(update_fields=['content', 'is_edited', 'updated_at'])
        
        cls.log_operation("message_edited", {
            'message_id': str(message.id),
            'editor': str(user.id)
        })
        
        return True, "Message edited successfully"
    
    @classmethod
    def delete_message(cls, message: ChatMessage, user: User) -> Tuple[bool, str]:
        can_delete = (
            message.sender == user or 
            (message.conversation and message.conversation.group and message.conversation.group.is_admin(user))
        )
        
        if not can_delete:
            return False, "Permission denied. Only sender or group admin can delete messages"
        
        message.soft_delete()
        
        cls.log_operation("message_deleted", {
            'message_id': str(message.id),
            'deleted_by': str(user.id),
            'was_admin_action': message.conversation and message.conversation.group and message.conversation.group.is_admin(user) and message.sender != user
        })
        
        return True, "Message deleted successfully"
    
    @classmethod
    def get_unread_count(cls, user: User, group: Group = None) -> int:
        if group:
            conversation, created = ConversationService.get_or_create_group_conversation(group)
            return ConversationService.get_unread_count_for_user(conversation, user)
        else:
            return getattr(user, 'unread_messages_count', 0)
    
    @classmethod
    def mark_messages_as_read(cls, user: User, group: Group) -> None:
        conversation, created = ConversationService.get_or_create_group_conversation(group)
        ConversationService.mark_as_read_for_user(conversation, user)
        
        cls.log_operation("messages_marked_read", {
            'user_id': str(user.id),
            'group_id': str(group.id),
            'timestamp': timezone.now().isoformat()
        })



