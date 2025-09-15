from django.db import transaction, models
from django.utils import timezone
from django.core.exceptions import ValidationError
from typing import Dict, List, Optional, Tuple, Any
import logging
from oauth2_provider.models import AccessToken, RefreshToken

from uuid import UUID

from .models import (
    User, Group, Plan, PlanActivity, ChatMessage, Friendship, GroupMembership, FriendshipRejection, Conversation, MessageReadStatus
)
from .events import RealtimeEvent, EventType
from .realtime_publisher import RealtimeEventPublisher
from .tasks import start_plan_task, complete_plan_task
from celery import current_app
from .paginators import ManualCursorPaginator

logger = logging.getLogger(__name__)

class BaseService:
    @staticmethod
    def log_operation(operation: str, details: Dict[str, Any] = None):
        logger.info(f"Service operation: {operation}", extra=details or {})
    
    @staticmethod
    def validate_user_permission(user, resource, permission_type: str) -> bool:
        if not user or not user.is_authenticated:
            return False
        return True


# ============================================================================
# USER SERVICE
# ============================================================================

class UserService(BaseService):
    @classmethod
    def get_user_with_counts(cls, user_id: UUID) -> User:
        return User.objects.with_counts().get(id=user_id)
    
    @classmethod
    def get_friendship_status(cls, current_user: User, target_user: User) -> Dict[str, Any]:
        # Self-check
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
            return {'status': direction}
        if status == Friendship.REJECTED:
            return {'status': 'rejected'}
        if status == Friendship.BLOCKED:
            return {'status': 'blocked'}

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
                return False, "Cannot send friend request"
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
                existing.save()
                cls.log_operation("friend_request_resent", {
                    'from_user': from_user.id,
                    'to_user': to_user.id
                })
                return True, "Friend request sent successfully"
        
        try:
            with transaction.atomic():
                # Ensure canonical ordering (user_a has smaller UUID than user_b)
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
        
        try:
            if token_string:
                at_qs = AccessToken.objects.select_for_update().filter(
                    token=token_string, user=user
                )
                if at_qs.exists():
                    at = at_qs.first()
                    RefreshToken.objects.filter(access_token=at).delete()
                    at.delete()
                    revoked = True
            
            user.set_online_status(False)
            
            cls.log_operation("user_logout", {
                'user_id': user.id,
                'token_revoked': revoked
            })
            
            return True, "Logged out successfully", revoked
            
        except Exception as e:
            cls.log_operation("user_logout_failed", {
                'user_id': user.id,
                'error': str(e)
            })
            return False, f"Logout failed: {e}", False
    
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
                # Import locally to avoid circular import with serializers.py
                from .serializers import UserSerializer

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
        friendship = Friendship.objects.filter(
            user=current_user,
            friend=target_user,
            status=Friendship.BLOCKED
        ).first()
        
        if not friendship:
            return False, "User is not blocked"
        
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
                # Import here to avoid circular import
                from .models import FriendshipRejection
                
                # Create rejection record first (while status is still PENDING)
                rejection = FriendshipRejection(
                    friendship=friendship, 
                    rejected_by=current_user
                )
                rejection.full_clean()  # Validate before saving
                rejection.save()
                
                # Then update friendship status
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
            friendship = Friendship.objects.get(
                user=current_user,
                friend=to_user,
                status=Friendship.PENDING
            )

            friendship.delete()

            cls.log_operation("friend_request_cancelled", {
                'from_user': current_user.id,
                'to_user': to_user.id
            })
            
            return True, "Friend request cancelled"
            
        except Friendship.DoesNotExist:
            return False, "Friend request not found"

    @classmethod
    def block_user(cls, current_user: User, target_user: User) -> Tuple[bool, str]:
        if current_user == target_user:
            return False, "Cannot block yourself"
        
        with transaction.atomic():
            Friendship.objects.filter(
                models.Q(user=current_user, friend=target_user) |
                models.Q(user=target_user, friend=current_user)
            ).delete()
            
            Friendship.objects.create(
                user=current_user,
                friend=target_user,
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


# ============================================================================
# GROUP SERVICE  
# ============================================================================

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
                        cls.add_member_to_group(group, user, role=GroupMembership.MEMBER)
        
        cls.log_operation("group_created", {
            'group_id': group.id,
            'creator': creator.id,
            'initial_members_count': len(initial_members) if initial_members else 0
        })
        
        return group
    
    @classmethod
    def add_member_to_group(cls, group: Group, user: User, 
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
            membership.full_clean()  # Use model validation
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
        
        return cls.add_member_to_group(group, user, GroupMembership.MEMBER)
    
    @classmethod
    def can_manage_members(cls, group: Group, user: User) -> bool:
        return group.is_admin(user)
    
    @classmethod
    def can_edit_group(cls, group: Group, user: User) -> bool:
        return group.is_admin(user)
    
    @classmethod
    def get_group_statistics(cls, group: Group) -> Dict[str, Any]:
        group_with_stats = Group.objects.with_full_stats().get(id=group.id)
        
        return {
            'members_count': group_with_stats.member_count_annotated,
            'admin_count': group_with_stats.admin_count_annotated,
            'plans_count': group_with_stats.plans_count_annotated,
            'created_at': group.created_at,
            'is_public': getattr(group, 'is_public', False)  # Handle if field doesn't exist
        }
    
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
            
        # Check if this is the last admin using model method
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

# ============================================================================
# PLAN SERVICE
# ============================================================================

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
                plan.full_clean()  # Use model validation
                plan.save()
                
                # Schedule any necessary tasks
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
    
    # @classmethod
    # def start_plan(cls, plan: Plan, user: User) -> Tuple[bool, str]:
    #     if not cls.can_edit_plan(plan, user):
    #         return False, "Permission denied"
        
    #     if plan.status != 'upcoming':
    #         return False, "Plan is not in upcoming status"
        
    #     # Delegate to start_trip for consistent logic
    #     try:
    #         result = cls.start_trip(plan, user, force=True)
    #         return True, "Plan started successfully"
    #     except ValueError as e:
    #         return False, str(e)
    
    # @classmethod
    # def complete_plan(cls, plan: Plan, user: User) -> Tuple[bool, str]:

    #     if not cls.can_edit_plan(plan, user):
    #         return False, "Permission denied"
        
    #     if plan.status not in ['ongoing', 'upcoming']:
    #         return False, f"Cannot complete plan with status: {plan.status}"
        
    #     # Delegate to complete_trip for consistent logic
    #     try:
    #         result = cls.complete_trip(plan, user, force=True)
    #         return True, "Plan completed successfully"
    #     except ValueError as e:
    #         return False, str(e)
    
    @classmethod
    def cancel_plan(cls, plan: Plan, user: User, reason: str = None) -> Tuple[bool, str]:
        if not cls.can_edit_plan(plan, user):
            return False, "Permission denied"
        
        if plan.status in ['cancelled', 'completed']:
            return False, f"Cannot cancel plan that is already {plan.get_status_display().lower()}"
        
        if plan.is_group_plan() and user != plan.creator:
            if not plan.group.is_admin(user):
                return False, "Only group admins can cancel group plans"
        
        with transaction.atomic():
            try:
                cls._revoke_plan_tasks(plan)
            except Exception:
                pass
            
            now = timezone.now()
            updated_count = Plan.objects.filter(
                pk=plan.pk,
                status__in=['upcoming', 'ongoing']
            ).update(
                status='cancelled',
                updated_at=now
            )
            
            if updated_count == 0:
                return False, "Plan status was changed by another user"
            
            plan.refresh_from_db()
        
        cls.log_operation("plan_cancelled", {
            'plan_id': plan.id,
            'cancelled_by': user.id,
            'reason': reason
        })
        
        return True, "Plan cancelled successfully"
    
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
                        'timestamp': timezone.now().isoformat(),
                        'forced': force
                    }
                )
                publisher.publish_event(event)
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
                raise ValueError("Plan status was changed by another operation")
            
            # Refresh plan instance
            plan.refresh_from_db()
            
            # Revoke any remaining scheduled tasks
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
                        'timestamp': timezone.now().isoformat(),
                        'forced': force
                    }
                )
                publisher.publish_event(event)
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
                'over_budget': False  # Add budget comparison logic if needed
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
        
        activities = plan.activities.select_related('location').order_by('start_time')
        
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
                
                duration_minutes = 0
                if activity.start_time and activity.end_time:
                    duration_delta = activity.end_time - activity.start_time
                    duration_minutes = int(duration_delta.total_seconds() / 60)
                
                schedule_by_date[date_str]['activities'].append({
                    'id': str(activity.id),
                    'title': activity.title,
                    'description': activity.description,
                    'activity_type': activity.activity_type,
                    'start_time': activity.start_time,
                    'end_time': activity.end_time,
                    'duration_minutes': duration_minutes,
                    'estimated_cost': float(activity.estimated_cost) if activity.estimated_cost else 0,
                    'location_name': activity.location_name,
                    'location_address': activity.location_address,
                    'notes': activity.notes,
                    'is_completed': activity.is_completed
                })
        
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
            if plan.start_date:
                start_task = start_plan_task.apply_async(
                    args=[str(plan.id)],
                    eta=plan.start_date
                )
                plan.scheduled_start_task_id = start_task.id
            
            if plan.end_date:
                end_task = complete_plan_task.apply_async(
                    args=[str(plan.id)],
                    eta=plan.end_date
                )
                plan.scheduled_end_task_id = end_task.id
            
            plan.save(update_fields=['scheduled_start_task_id', 'scheduled_end_task_id'])
            
        except ImportError:
            pass
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
            if plan.scheduled_end_task_id:
                try:
                    current_app.control.revoke(plan.scheduled_end_task_id, terminate=False)
                except Exception:
                    pass
            
            end_task = complete_plan_task.apply_async(
                args=[str(plan.id)],
                eta=plan.end_date
            )
            
            Plan.objects.filter(pk=plan.pk).update(
                scheduled_end_task_id=end_task.id
            )
            
        except ImportError:
            pass
        except Exception as e:
            logger.warning(f"Failed to schedule completion task: {e}")


class ChatService(BaseService):
    
    @classmethod
    def send_message(cls, sender: User, group: 'Group', content: str, 
                    message_type: str = 'user') -> 'ChatMessage':
        
        if not group.is_member(sender):
            raise ValidationError("You must be a member of the group to send messages")
        
        try:
            message = ChatMessage(
                sender=sender,
                group=group,
                content=content,
                message_type=message_type
            )
            message.full_clean()
            message.save()
        except ValidationError as e:
            raise ValidationError(f"Message creation failed: {str(e)}")
        
        cls.log_operation("message_sent", {
            'message_id': message.id,
            'sender': sender.id,
            'group_id': group.id,
            'type': message_type
        })
        
        return message
    
    @classmethod
    def get_group_messages(cls, user: User, group_id: str, limit: int = 50, before_id: str = None) -> Dict[str, Any]:
        
        try:
            group = Group.objects.get(id=group_id, members=user)
        except Group.DoesNotExist:
            raise ValidationError("Group not found or access denied")
        
        queryset = ChatMessage.objects.filter(
            group=group
        ).select_related('sender').order_by('-created_at')
        
        result = ManualCursorPaginator.paginate_by_id(
            queryset=queryset,
            before_id=before_id,
            limit=limit,
            ordering='-id'
        )
        
        return {
            'messages': result['items'],
            'has_more': result['has_more'],
            'next_cursor': result['next_cursor'],
            'count': result['count']
        }
    
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
            'message_id': message.id,
            'editor': user.id
        })
        
        return True, "Message edited successfully"
    
    @classmethod
    def delete_message(cls, message: ChatMessage, user: User) -> Tuple[bool, str]:        
        # Sender or group admin can delete
        can_delete = (
            message.sender == user or 
            (hasattr(message, 'group') and message.group and message.group.is_admin(user))
        )
        
        if not can_delete:
            return False, "Permission denied. Only sender or group admin can delete messages"
        
        # Use model's soft delete method
        message.soft_delete()
        
        cls.log_operation("message_deleted", {
            'message_id': message.id,
            'deleted_by': user.id,
            'was_admin_action': hasattr(message, 'group') and message.group and message.group.is_admin(user) and message.sender != user
        })
        
        return True, "Message deleted successfully"
    
    @classmethod
    def get_unread_count(cls, user: User, group: Group = None) -> int:
        if group:
            return ChatMessage.objects.unread_for_user(user).for_group(group).count()
        else:
            return user.unread_messages_count
    
    @classmethod
    def mark_messages_as_read(cls, user: User, group: Group) -> None:
        cls.log_operation("messages_marked_read", {
            'user_id': user.id,
            'group_id': group.id,
            'timestamp': timezone.now()
        })
        
        user.clear_unread_cache()
    
    @classmethod
    def _get_last_read_time(cls, user: User, group: Group):
        return timezone.now() - timezone.timedelta(days=7)

    @classmethod
    def create_system_message(cls, conversation=None, group=None, content: str = ""):

        if conversation is None and group is None:
            raise ValueError("Either conversation or group must be provided")

        with transaction.atomic():
            if group is not None:
                # Use ConversationService method instead of model method
                conversation, created = ConversationService.get_or_create_for_group(group)

            # Create the system message with validation
            message = ChatMessage(
                conversation=conversation,
                sender=None,
                message_type='system',
                content=content
            )
            message.full_clean()
            message.save()

        cls.log_operation("system_message_created", {
            'conversation_id': conversation.id if conversation else None,
            'group_id': getattr(group, 'id', None),
            'message_id': message.id
        })

        return message


# ============================================================================
# NOTIFICATION SERVICE
# ============================================================================

class NotificationService(BaseService):
    
    @classmethod
    def notify_plan_created(cls, plan_id: str, creator_name: str, group_id: str = None):
        cls.log_operation("plan_created_notification", {
            'plan_id': plan_id,
            'creator_name': creator_name,
            'group_id': group_id
        })
        
    
    @classmethod
    def notify_member_added(cls, group_id: str, user_id: str, added_by_id: str):
        cls.log_operation("member_added_notification", {
            'group_id': group_id,
            'user_id': user_id,
            'added_by_id': added_by_id
        })
    
    @classmethod
    def notify_friend_request(cls, from_user_id: str, to_user_id: str):
        cls.log_operation("friend_request_notification", {
            'from_user_id': from_user_id,
            'to_user_id': to_user_id
        })

class ConversationService(BaseService):
    @classmethod
    def send_message_to_conversation(cls, conversation, sender: User, content: str, 
                                   message_type: str = 'text', **kwargs) -> 'ChatMessage':
        
        # Optimized participant check using new methods
        if not conversation.is_participant(sender):
            raise ValidationError("Sender is not a participant of this conversation")

        try:
            with transaction.atomic():
                message = ChatMessage(
                    conversation=conversation,
                    sender=sender,
                    content=content,
                    message_type=message_type,
                    **kwargs
                )
                message.full_clean()  # Use model validation
                message.save()
                
                cls.log_operation("conversation_message_sent", {
                    'conversation_id': conversation.id,
                    'sender_id': sender.id,
                    'message_type': message_type
                })
                
                return message
        except ValidationError as e:
            raise ValidationError(f"Message creation failed: {str(e)}")
    
    @classmethod
    def update_last_message_time(cls, conversation, timestamp=None):
        """Update last message timestamp"""
        if timestamp is None:
            timestamp = timezone.now()
            
        if not conversation.last_message_at or timestamp > conversation.last_message_at:
            conversation.last_message_at = timestamp
            conversation.save(update_fields=['last_message_at'])
    
    @classmethod
    def get_unread_count_for_user(cls, conversation, user):
        return conversation.messages.unread_for_user(user).count()
    
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
    def get_or_create_direct_conversation(cls, user1: User, user2: User):
        """Get or create direct conversation between two users"""        
        if user1 == user2:
            raise ValueError("Cannot create conversation with yourself")
        
        try:
            # Use optimized query method
            existing = Conversation.objects.get_direct_conversation(user1, user2)
            if existing:
                return existing, False
                
            # Create new conversation with canonical ordering
            conversation = cls.create_direct_conversation(user1, user2)
            
            cls.log_operation("direct_conversation_created", {
                'conversation_id': conversation.id,
                'user1_id': user1.id,
                'user2_id': user2.id
            })
            
            return conversation, True
        except ValidationError as e:
            raise ValidationError(f"Conversation creation failed: {str(e)}")

    @classmethod 
    def create_direct_conversation(cls, user1: User, user2: User) -> 'Conversation':
        """Create direct conversation between two users with canonical ordering"""
        if user1.id == user2.id:
            raise ValidationError("Cannot create conversation with same user")
        
        # Canonical ordering (smaller UUID first)
        if user1.id < user2.id:
            conversation = Conversation.objects.create(
                conversation_type='direct',
                user_a=user1,
                user_b=user2
            )
        else:
            conversation = Conversation.objects.create(
                conversation_type='direct',
                user_a=user2,
                user_b=user1
            )
        
        return conversation
    
    @classmethod
    def create_group_conversation(cls, group):
        """Create or get group conversation"""        
        try:
            conversation, created = cls.get_or_create_for_group(group)
            
            if created:
                cls.log_operation("group_conversation_created", {
                    'conversation_id': conversation.id,
                    'group_id': group.id
                })
            
            return conversation
        except ValidationError as e:
            raise ValidationError(f"Group conversation creation failed: {str(e)}")
    
    @classmethod
    def get_or_create_for_group(cls, group):
        """Get or create group conversation"""        
        try:
            return group.conversation, False
        except Conversation.DoesNotExist:
            conversation = Conversation.objects.create(
                conversation_type='group',
                group=group
            )
            return conversation, True

    @classmethod
    def update_last_message_time(cls, conversation, timestamp=None):
        """Update last message timestamp"""
        if timestamp is None:
            timestamp = timezone.now()
            
        if not conversation.last_message_at or timestamp > conversation.last_message_at:
            conversation.last_message_at = timestamp
            conversation.save(update_fields=['last_message_at'])



