from django.db import transaction, models
from django.utils import timezone
from django.core.exceptions import ValidationError
from django.contrib.auth import get_user_model
from typing import Dict, List, Optional, Tuple, Any
import logging

from .models import (
    User, Group, Plan, PlanActivity, ChatMessage, Friendship, GroupMembership
)
from .events import RealtimeEvent, EventType
from .realtime_publisher import RealtimeEventPublisher

logger = logging.getLogger(__name__)

# ============================================================================
# BASE SERVICE CLASS
# ============================================================================

class BaseService:
    """Base service class with common functionality"""
    
    @staticmethod
    def log_operation(operation: str, details: Dict[str, Any] = None):
        """Log service operations for debugging and monitoring"""
        logger.info(f"Service operation: {operation}", extra=details or {})
    
    @staticmethod
    def validate_user_permission(user, resource, permission_type: str) -> bool:
        """Generic permission validation"""
        if not user or not user.is_authenticated:
            return False
        return True


# ============================================================================
# USER SERVICE
# ============================================================================

class UserService(BaseService):
    """Service for user-related business logic"""
    
    @classmethod
    def get_user_with_counts(cls, user_id: str) -> User:
        """Get user with all counts efficiently"""
        return User.objects.with_cached_counts().get(id=user_id)
    
    @classmethod
    def get_friendship_status(cls, current_user: User, target_user: User) -> Dict[str, Any]:
        """Get friendship status between two users"""
        if current_user == target_user:
            return {'status': 'self'}
        
        # Check if there's an existing friendship
        friendship = Friendship.objects.filter(
            models.Q(user=current_user, friend=target_user) |
            models.Q(user=target_user, friend=current_user)
        ).first()
        
        if not friendship:
            return {'status': 'none'}
        
        if friendship.status == Friendship.ACCEPTED:
            return {'status': 'friends', 'since': friendship.created_at}
        elif friendship.status == Friendship.PENDING:
            if friendship.user == current_user:
                return {'status': 'pending_sent'}
            else:
                return {'status': 'pending_received'}
        elif friendship.status == Friendship.BLOCKED:
            return {'status': 'blocked'}
        
        return {'status': 'unknown'}
    
    @classmethod
    def send_friend_request(cls, from_user: User, to_user: User) -> Tuple[bool, str]:
        """Send friend request with validation and cooldown logic"""
        if from_user == to_user:
            return False, "Cannot send friend request to yourself"
        
        # Check if friendship already exists
        existing = Friendship.objects.filter(
            models.Q(user=from_user, friend=to_user) |
            models.Q(user=to_user, friend=from_user)
        ).first()
        
        if existing:
            if existing.status == Friendship.ACCEPTED:
                return False, "Already friends"
            elif existing.status == Friendship.PENDING:
                return False, "Friend request already sent"
            elif existing.status == Friendship.BLOCKED:
                return False, "Cannot send friend request"
            elif existing.status == Friendship.REJECTED:
                # Check cooldown logic
                rejections = existing.rejections.all()[:Friendship.MAX_REJECTION_COUNT + 1]
                
                if rejections:
                    last_rejection = rejections[0]
                    time_since_rejection = timezone.now() - last_rejection.created_at
                    rejection_count = len(rejections)
                    
                    # Determine cooldown period
                    if rejection_count >= Friendship.MAX_REJECTION_COUNT:
                        cooldown_period = timezone.timedelta(days=Friendship.EXTENDED_COOLDOWN_DAYS)
                        cooldown_msg = f"Must wait {Friendship.EXTENDED_COOLDOWN_DAYS} days after {rejection_count} rejections"
                    else:
                        cooldown_period = timezone.timedelta(hours=Friendship.REJECTION_COOLDOWN_HOURS)
                        cooldown_msg = f"Must wait {Friendship.REJECTION_COOLDOWN_HOURS} hours after rejection"
                    
                    if time_since_rejection < cooldown_period:
                        remaining_time = cooldown_period - time_since_rejection
                        return False, f"Cannot resend friend request yet. {cooldown_msg}. Time remaining: {remaining_time}"
                
                # Update existing rejected friendship to pending
                existing.status = Friendship.PENDING
                existing.save()
                cls.log_operation("friend_request_resent", {
                    'from_user': from_user.id,
                    'to_user': to_user.id
                })
                return True, "Friend request sent successfully"
        
        # Create new friendship request
        with transaction.atomic():
            Friendship.objects.create(
                user=from_user,
                friend=to_user,
                status=Friendship.PENDING
            )
        
        cls.log_operation("friend_request_sent", {
            'from_user': from_user.id,
            'to_user': to_user.id
        })
        
        return True, "Friend request sent successfully"
    
    @classmethod
    def accept_friend_request(cls, current_user: User, from_user: User) -> Tuple[bool, str]:
        """Accept friend request"""
        try:
            friendship = Friendship.objects.get(
                user=from_user,
                friend=current_user,
                status=Friendship.PENDING
            )
            
            with transaction.atomic():
                friendship.status = Friendship.ACCEPTED
                friendship.save()
            
            cls.log_operation("friend_request_accepted", {
                'user': current_user.id,
                'from_user': from_user.id
            })
            
            return True, "Friend request accepted"
            
        except Friendship.DoesNotExist:
            return False, "Friend request not found"
    
    @classmethod
    def reject_friend_request(cls, current_user: User, from_user: User) -> Tuple[bool, str]:
        """Reject a friend request and record the rejection."""
        try:
            friendship = Friendship.objects.get(
                user=from_user,
                friend=current_user,
                status=Friendship.PENDING
            )

            with transaction.atomic():
                friendship.status = Friendship.REJECTED
                friendship.save()
                
                # Record the rejection event
                from .models import FriendshipRejection
                FriendshipRejection.objects.create(
                    friendship=friendship, 
                    rejected_by=current_user
                )

            cls.log_operation("friend_request_rejected", {
                'user': current_user.id,
                'from_user': from_user.id
            })
            
            return True, "Friend request rejected"
            
        except Friendship.DoesNotExist:
            return False, "Friend request not found"
    
    @classmethod
    def cancel_friend_request(cls, current_user: User, to_user: User) -> Tuple[bool, str]:
        """Cancel a friend request sent by the current user."""
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
        """Block a user"""
        if current_user == target_user:
            return False, "Cannot block yourself"
        
        with transaction.atomic():
            # Remove any existing friendship
            Friendship.objects.filter(
                models.Q(user=current_user, friend=target_user) |
                models.Q(user=target_user, friend=current_user)
            ).delete()
            
            # Create block relationship
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
        """Remove friendship between users"""
        friendship = Friendship.objects.filter(
            models.Q(user=current_user, friend=target_user) |
            models.Q(user=target_user, friend=current_user),
            status=Friendship.ACCEPTED
        ).first()
        
        if not friendship:
            return False, "Not friends"
        
        friendship.delete()
        
        cls.log_operation("users_unfriended", {
            'user1': current_user.id,
            'user2': target_user.id
        })
        
        return True, "Unfriended successfully"
    
    @classmethod
    def create_personal_plan(cls, user: User, title: str, start_date, end_date, **kwargs) -> 'Plan':
        """Create personal plan for user"""
        from .models import Plan
        return Plan.objects.create(
            creator=user,
            title=title,
            description=kwargs.get('description', ''),
            plan_type='personal',
            start_date=start_date,
            end_date=end_date,
            budget=kwargs.get('budget'),
            is_public=kwargs.get('is_public', False),
            status='planning'
        )
    
    @classmethod
    def create_group_plan(cls, user: User, group: 'Group', title: str, start_date, end_date, **kwargs) -> 'Plan':
        """Create group plan for user"""
        # Validate user is group member
        if not cls.is_group_member(user, group):
            raise ValidationError("You must be a member of the group to create a plan")
        
        from .models import Plan
        return Plan.objects.create(
            creator=user,
            title=title,
            description=kwargs.get('description', ''),
            plan_type='group',
            group=group,
            start_date=start_date,
            end_date=end_date,
            budget=kwargs.get('budget'),
            is_public=kwargs.get('is_public', False),
            status='planning'
        )
    
    @classmethod
    def is_group_member(cls, user: User, group: 'Group') -> bool:
        """Check if user is member of group"""
        from .models import GroupMembership
        return GroupMembership.objects.filter(group=group, user=user).exists()


# ============================================================================
# GROUP SERVICE  
# ============================================================================

class GroupService(BaseService):
    """Service for group-related business logic"""
    
    @classmethod
    def create_group(cls, creator: User, name: str, description: str = "", 
                    is_public: bool = False, initial_members: List[User] = None) -> Group:
        """Create a new group with initial setup"""
        with transaction.atomic():
            group = Group.objects.create(
                name=name,
                description=description,
                admin=creator,
                is_public=is_public
            )
            
            # Add creator as member
            GroupMembership.objects.create(
                group=group,
                user=creator,
                role=GroupMembership.ADMIN
            )
            
            # Add initial members if provided
            if initial_members:
                for user in initial_members:
                    if user != creator:  # Don't add creator twice
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
        """Add a user to a group with validation"""
        from .models import GroupMembership, Friendship
        
        # Set default role
        if role is None:
            role = GroupMembership.MEMBER
        
        # Check if user is already a member
        if GroupMembership.objects.filter(group=group, user=user).exists():
            return False, "User is already a member"
        
        # Additional validation: only friends can be added (if added_by is provided)
        if added_by and added_by != user:
            if not Friendship.are_friends(added_by, user):
                return False, "Can only add friends to group"
        
        # Create membership
        GroupMembership.objects.create(
            group=group,
            user=user,
            role=role
        )
        
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
        """Remove a user from a group"""
        # Check permissions
        if not cls.can_manage_members(group, removed_by):
            return False, "Permission denied"
        
        # Cannot remove the admin
        if group.admin == user:
            return False, "Cannot remove group admin"
        
        try:
            membership = GroupMembership.objects.get(group=group, user=user)
            membership.delete()
            
            cls.log_operation("member_removed_from_group", {
                'group_id': group.id,
                'user_id': user.id,
                'removed_by': removed_by.id
            })
            
            return True, "Member removed from group"
            
        except GroupMembership.DoesNotExist:
            return False, "User is not a member of this group"
    
    @classmethod
    def join_group_by_invite(cls, group: Group, user: User) -> Tuple[bool, str]:
        """Join a group using invite code or public access"""
        if GroupMembership.objects.filter(group=group, user=user).exists():
            return False, "Already a member"
        
        # Add as regular member
        return cls.add_member_to_group(group, user, GroupMembership.MEMBER)
    
    @classmethod
    def can_manage_members(cls, group: Group, user: User) -> bool:
        """Check if user can manage group members"""
        return group.admin == user
    
    @classmethod
    def can_edit_group(cls, group: Group, user: User) -> bool:
        """Check if user can edit group details"""
        return group.admin == user
    
    @classmethod
    def get_group_statistics(cls, group: Group) -> Dict[str, Any]:
        """Get comprehensive group statistics"""
        members_count = group.memberships.count()
        plans_count = group.plans.count()
        messages_count = group.messages.count()
        
        return {
            'members_count': members_count,
            'plans_count': plans_count,
            'messages_count': messages_count,
            'created_at': group.created_at,
            'is_public': group.is_public
        }
    
    @classmethod
    @transaction.atomic
    def promote_member(cls, group: Group, user_to_promote: User, actor: User) -> Tuple[bool, str]:
        """Promotes a group member to admin with permission checks."""
        if not cls.can_manage_members(group, actor):
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
        """Demotes a group admin to member with permission checks."""
        if not cls.can_manage_members(group, actor):
            return False, "You do not have permission to demote members."
            
        if actor == user_to_demote:
            return False, "You cannot demote yourself."

        membership = group.get_user_membership(user_to_demote)
        if not membership:
            return False, "User is not a member of this group."

        if membership.role != GroupMembership.ADMIN:
            return False, "User is not an admin."
            
        # Check if this is the last admin
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

# ============================================================================
# PLAN SERVICE
# ============================================================================

class PlanService(BaseService):
    """Service for plan-related business logic"""
    
    @classmethod
    def create_plan(cls, creator: User, title: str, description: str = "",
                   plan_type: str = 'personal', group: Group = None,
                   start_date=None, end_date=None, budget=None,
                   is_public: bool = False) -> Plan:
        """Create a new plan with validation"""
        
        # Validate group access if group plan
        if plan_type == 'group' and group:
            if not GroupMembership.objects.filter(group=group, user=creator).exists():
                raise ValidationError("You must be a member of the group to create a plan")
        
        with transaction.atomic():
            plan = Plan.objects.create(
                title=title,
                description=description,
                creator=creator,
                plan_type=plan_type,
                group=group,
                start_date=start_date,
                end_date=end_date,
                budget=budget,
                is_public=is_public,
                status='planning'
            )
            
            # Schedule any necessary tasks
            cls._schedule_plan_tasks(plan)
        
        cls.log_operation("plan_created", {
            'plan_id': plan.id,
            'creator': creator.id,
            'plan_type': plan_type,
            'group_id': group.id if group else None
        })
        
        return plan
    
    @classmethod
    def add_activity_to_plan(cls, plan: Plan, user: User, activity_data: Dict[str, Any]) -> PlanActivity:
        """Add an activity to a plan with validation"""
        
        # Check permissions
        if not cls.can_edit_plan(plan, user):
            raise ValidationError("Permission denied to edit this plan")
        
        # Validate time conflicts
        if cls._has_time_conflict(plan, activity_data.get('start_time'), 
                                 activity_data.get('end_time')):
            raise ValidationError("Activity time conflicts with existing activities")
        
        with transaction.atomic():
            activity = PlanActivity.objects.create(
                plan=plan,
                title=activity_data['title'],
                description=activity_data.get('description', ''),
                activity_type=activity_data.get('activity_type', 'other'),
                start_time=activity_data.get('start_time'),
                end_time=activity_data.get('end_time'),
                estimated_cost=activity_data.get('estimated_cost', 0),
                location_name=activity_data.get('location_name', ''),
                location_address=activity_data.get('location_address', ''),
                notes=activity_data.get('notes', '')
            )
        
        cls.log_operation("activity_added_to_plan", {
            'plan_id': plan.id,
            'activity_id': activity.id,
            'user_id': user.id
        })
        
        return activity
    
    @classmethod
    def add_activity_with_place(cls, plan: Plan, title: str, start_time, end_time, 
                               place_id: str = None, **extra_fields):
        """Add activity with place integration (for backward compatibility)"""
        from .models import PlanActivity
        
        # Build activity data
        activity_data = {
            'title': title,
            'start_time': start_time,
            'end_time': end_time,
            **extra_fields
        }
        
        # Handle place_id if provided
        if place_id:
            activity_data['location_name'] = f"Place ID: {place_id}"
        
        # Use existing add_activity_to_plan method but skip user validation for now
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
    def start_plan(cls, plan: Plan, user: User) -> Tuple[bool, str]:
        """Start a plan and handle associated logic"""
        if not cls.can_edit_plan(plan, user):
            return False, "Permission denied"
        
        if plan.status != 'planning':
            return False, "Plan is not in planning status"
        
        with transaction.atomic():
            plan.status = 'active'
            plan.save()
            
            # Schedule Celery tasks for the plan
            cls._schedule_plan_tasks(plan)
        
        cls.log_operation("plan_started", {
            'plan_id': plan.id,
            'started_by': user.id
        })
        
        return True, "Plan started successfully"
    
    @classmethod
    def complete_plan(cls, plan: Plan, user: User) -> Tuple[bool, str]:
        """Complete a plan"""
        if not cls.can_edit_plan(plan, user):
            return False, "Permission denied"
        
        if plan.status not in ['active', 'planning']:
            return False, f"Cannot complete plan with status: {plan.status}"
        
        with transaction.atomic():
            plan.status = 'completed'
            plan.completed_at = timezone.now()
            plan.save()
            
            # Cancel any scheduled tasks
            cls._cancel_plan_tasks(plan)
        
        cls.log_operation("plan_completed", {
            'plan_id': plan.id,
            'completed_by': user.id
        })
        
        return True, "Plan completed successfully"
    
    @classmethod
    def cancel_plan(cls, plan: Plan, user: User, reason: str = None) -> Tuple[bool, str]:
        """Cancel a plan with proper validation and cleanup"""
        if not cls.can_edit_plan(plan, user):
            return False, "Permission denied"
        
        # Validate current status
        if plan.status in ['cancelled', 'completed']:
            return False, f"Cannot cancel plan that is already {plan.get_status_display().lower()}"
        
        # Permission check for group plans
        if plan.is_group_plan() and user != plan.creator:
            if not plan.group.is_admin(user):
                return False, "Only group admins can cancel group plans"
        
        with transaction.atomic():
            # Try to revoke any scheduled tasks
            try:
                cls._revoke_plan_tasks(plan)
            except Exception:
                # Best effort - don't fail cancel if revoke fails
                pass
            
            # Update plan status
            now = timezone.now()
            updated_count = Plan.objects.filter(
                pk=plan.pk,
                status__in=['planning', 'active', 'upcoming', 'ongoing']
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
        """Start a trip (compatible with tasks) - transition from upcoming to ongoing"""
        # Validate status transition
        if plan.status != 'upcoming' and not force:
            raise ValueError(f"Cannot start trip in status: {plan.status}")
        
        # Check if it's time to start (unless forced)
        if not force and plan.start_date and timezone.now() < plan.start_date:
            raise ValueError("Trip start time has not been reached yet")
        
        with transaction.atomic():
            # Atomic status update with condition check
            updated_count = Plan.objects.filter(
                pk=plan.pk,
                status='upcoming'
            ).update(
                status='ongoing',
                updated_at=timezone.now()
            )
            
            if updated_count == 0 and not force:
                raise ValueError("Plan status was changed by another operation")
            
            # Refresh plan instance
            plan.refresh_from_db()
            
            # Schedule completion task if needed
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
        
        # Publish realtime event using transaction.on_commit for reliability
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
        """Complete a trip (compatible with tasks) - transition from ongoing to completed"""
        # Validate status transition
        if plan.status != 'ongoing' and not force:
            raise ValueError(f"Cannot complete trip in status: {plan.status}")
        
        # Check if it's time to complete (unless forced)
        if not force and plan.end_date and timezone.now() < plan.end_date:
            raise ValueError("Trip end time has not been reached yet")
        
        with transaction.atomic():
            # Atomic status update with condition check
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
        
        # Publish realtime event using transaction.on_commit for reliability
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
        """Cancel a trip - can be called from any status"""
        # Check permissions if user is provided
        if user and not cls.can_edit_plan(plan, user):
            raise ValueError("Permission denied to cancel this plan")
        
        # Validate current status (unless forced)
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
        """Check if user can view a plan"""
        # Public plans can be viewed by anyone
        if plan.is_public:
            return True
        
        # Creator can always view
        if plan.creator == user:
            return True
        
        # Group members can view group plans
        if plan.plan_type == 'group' and plan.group:
            return GroupMembership.objects.filter(
                group=plan.group, user=user
            ).exists()
        
        return False
    
    @classmethod
    def can_edit_plan(cls, plan: Plan, user: User) -> bool:
        """Check if user can edit a plan"""
        # Creator can always edit
        if plan.creator == user:
            return True
        
        # Group admins can edit group plans
        if plan.plan_type == 'group' and plan.group:
            return plan.group.admin == user
        
        return False
    
    @classmethod
    def get_plan_statistics(cls, plan: Plan) -> Dict[str, Any]:
        """Get comprehensive plan statistics"""
        activities = plan.activities.all()
        total_activities = activities.count()
        completed_activities = activities.filter(is_completed=True).count()
        total_cost = sum(float(a.estimated_cost) for a in activities if a.estimated_cost)
        
        # Calculate duration
        duration_days = 0
        if plan.start_date and plan.end_date:
            duration_days = (plan.end_date - plan.start_date).days + 1
        
        return {
            'activities': {
                'total': total_activities,
                'completed': completed_activities,
                'completion_rate': (completed_activities / total_activities * 100) if total_activities > 0 else 0
            },
            'budget': {
                'planned': float(plan.budget) if plan.budget else 0,
                'estimated': total_cost,
                'over_budget': total_cost > float(plan.budget) if plan.budget else False
            },
            'duration': {
                'days': duration_days,
                'start_date': plan.start_date,
                'end_date': plan.end_date
            },
            'status': plan.status,
            'collaboration': {
                'type': plan.plan_type,
                'group_id': plan.group.id if plan.group else None
            }
        }
    
    @classmethod
    def _has_time_conflict(cls, plan: Plan, start_time, end_time) -> bool:
        """Check if activity times conflict with existing activities"""
        if not start_time or not end_time:
            return False
        
        conflicts = plan.activities.filter(
            models.Q(
                start_time__lt=end_time,
                end_time__gt=start_time
            )
        ).exists()
        
        return conflicts
    
    @classmethod
    def _schedule_plan_tasks(cls, plan: Plan):
        """Schedule Celery tasks for plan notifications and reminders"""
        try:
            from .tasks import schedule_plan_reminders
            schedule_plan_reminders.delay(str(plan.id))
        except ImportError:
            logger.warning("Celery tasks not available for plan scheduling")
    
    @classmethod
    def _cancel_plan_tasks(cls, plan: Plan):
        """Cancel scheduled Celery tasks for a plan"""
        try:
            from .tasks import cancel_plan_reminders
            cancel_plan_reminders.delay(str(plan.id))
        except ImportError:
            logger.warning("Celery tasks not available for plan cancellation")
    
    @classmethod
    def bulk_update_plan_statuses(cls) -> Dict[str, int]:
        """Bulk update plan statuses based on dates with realtime events"""
        from .models import Plan
        now = timezone.now()
        
        # Get plans that will be updated for realtime events
        upcoming_plans = list(Plan.objects.filter(
            status='upcoming',
            start_date__lte=now
        ).values('id', 'title', 'group_id', 'creator_id'))
        
        ongoing_plans = list(Plan.objects.filter(
            status='ongoing',
            end_date__lt=now
        ).values('id', 'title', 'group_id', 'creator_id'))
        
        # Perform bulk updates
        upcoming_to_ongoing = Plan.objects.filter(
            status='upcoming',
            start_date__lte=now
        ).update(
            status='ongoing',
            updated_at=now
        )
        
        ongoing_to_completed = Plan.objects.filter(
            status='ongoing',
            end_date__lt=now
        ).update(
            status='completed', 
            updated_at=now
        )
        
        cls.log_operation("bulk_status_update", {
            'upcoming_to_ongoing': upcoming_to_ongoing,
            'ongoing_to_completed': ongoing_to_completed,
            'total_updated': upcoming_to_ongoing + ongoing_to_completed
        })
        
        # Publish realtime events for each updated plan
        def _publish_bulk_events():
            try:
                publisher = RealtimeEventPublisher()
                
                # Publish events for upcoming -> ongoing
                for plan_data in upcoming_plans:
                    event = RealtimeEvent(
                        event_type=EventType.PLAN_STATUS_CHANGED,
                        plan_id=str(plan_data['id']),
                        user_id=None,  # System update
                        group_id=str(plan_data['group_id']) if plan_data['group_id'] else None,
                        data={
                            'plan_id': str(plan_data['id']),
                            'title': plan_data['title'],
                            'old_status': 'upcoming',
                            'new_status': 'ongoing',
                            'updated_by': 'system',
                            'timestamp': now.isoformat(),
                            'bulk_update': True
                        }
                    )
                    publisher.publish_event(event, send_push=False)  # No push for bulk updates
                
                # Publish events for ongoing -> completed
                for plan_data in ongoing_plans:
                    event = RealtimeEvent(
                        event_type=EventType.PLAN_STATUS_CHANGED,
                        plan_id=str(plan_data['id']),
                        user_id=None,  # System update
                        group_id=str(plan_data['group_id']) if plan_data['group_id'] else None,
                        data={
                            'plan_id': str(plan_data['id']),
                            'title': plan_data['title'],
                            'old_status': 'ongoing',
                            'new_status': 'completed',
                            'updated_by': 'system',
                            'timestamp': now.isoformat(),
                            'bulk_update': True
                        }
                    )
                    publisher.publish_event(event, send_push=False)  # No push for bulk updates
                    
            except Exception as e:
                logger.warning(f"Failed to publish bulk update events: {e}")
        
        transaction.on_commit(_publish_bulk_events)
        
        return {
            'upcoming_to_ongoing': upcoming_to_ongoing,
            'ongoing_to_completed': ongoing_to_completed,
            'total_updated': upcoming_to_ongoing + ongoing_to_completed
        }
    
    @classmethod
    def _schedule_plan_tasks(cls, plan: Plan):
        """Schedule Celery tasks for plan lifecycle"""
        try:
            # Lazy import to avoid circular dependency
            from .tasks import start_plan_task, end_plan_task
            
            # Schedule start task if plan has start date
            if plan.start_date:
                start_task = start_plan_task.apply_async(
                    args=[str(plan.id)],
                    eta=plan.start_date
                )
                plan.scheduled_start_task_id = start_task.id
            
            # Schedule end task if plan has end date
            if plan.end_date:
                end_task = end_plan_task.apply_async(
                    args=[str(plan.id)],
                    eta=plan.end_date
                )
                plan.scheduled_end_task_id = end_task.id
            
            # Save task IDs
            plan.save(update_fields=['scheduled_start_task_id', 'scheduled_end_task_id'])
            
        except ImportError:
            # Celery tasks not available - this is OK in development/testing
            pass
        except Exception as e:
            cls.log_operation("task_scheduling_failed", {
                'plan_id': plan.id,
                'error': str(e)
            })
    
    @classmethod
    def _revoke_plan_tasks(cls, plan: Plan):
        """Revoke scheduled Celery tasks for a plan"""
        old_start_id = plan.scheduled_start_task_id
        old_end_id = plan.scheduled_end_task_id
        
        # Try to revoke tasks (best effort)
        for task_id in (old_start_id, old_end_id):
            if not task_id:
                continue
            try:
                from celery import current_app
                current_app.control.revoke(task_id, terminate=False)
            except Exception:
                pass

        # Clear stored ids
        Plan.objects.filter(pk=plan.pk).update(
            scheduled_start_task_id=None,
            scheduled_end_task_id=None
        )
    
    @classmethod
    def _schedule_completion_task(cls, plan: Plan):
        """Schedule completion task for an ongoing plan"""
        if not plan.end_date:
            return
            
        try:
            from .tasks import complete_plan_task
            
            # Revoke existing end task if any
            if plan.scheduled_end_task_id:
                try:
                    from celery import current_app
                    current_app.control.revoke(plan.scheduled_end_task_id, terminate=False)
                except Exception:
                    pass
            
            # Schedule new completion task
            end_task = complete_plan_task.apply_async(
                args=[str(plan.id)],
                eta=plan.end_date
            )
            
            # Update plan with new task id
            Plan.objects.filter(pk=plan.pk).update(
                scheduled_end_task_id=end_task.id
            )
            
        except ImportError:
            # Celery not available - OK in dev/test
            pass
        except Exception as e:
            logger.warning(f"Failed to schedule completion task: {e}")


# ============================================================================
# CHAT SERVICE
# ============================================================================

class ChatService(BaseService):
    """Service for chat and messaging business logic"""
    
    @classmethod
    def send_message(cls, sender: User, group: Group, content: str, 
                    message_type: str = 'user') -> ChatMessage:
        """Send a message to a group chat"""
        
        # Validate group membership
        if not GroupMembership.objects.filter(group=group, user=sender).exists():
            raise ValidationError("You must be a member of the group to send messages")
        
        # Create message
        message = ChatMessage.objects.create(
            sender=sender,
            group=group,
            content=content,
            message_type=message_type
        )
        
        cls.log_operation("message_sent", {
            'message_id': message.id,
            'sender': sender.id,
            'group_id': group.id,
            'type': message_type
        })
        
        return message
    
    @classmethod
    def edit_message(cls, message: ChatMessage, user: User, new_content: str) -> Tuple[bool, str]:
        """Edit a message with validation"""
        
        # Only sender can edit
        if message.sender != user:
            return False, "Can only edit your own messages"
        
        # Check edit time limit (15 minutes)
        edit_deadline = message.created_at + timezone.timedelta(minutes=15)
        if timezone.now() > edit_deadline:
            return False, "Message edit time expired (15 minutes limit)"
        
        # Cannot edit system messages
        if message.message_type == 'system':
            return False, "Cannot edit system messages"
        
        message.content = new_content
        message.is_edited = True
        message.save()
        
        cls.log_operation("message_edited", {
            'message_id': message.id,
            'editor': user.id
        })
        
        return True, "Message edited successfully"
    
    @classmethod
    def delete_message(cls, message: ChatMessage, user: User) -> Tuple[bool, str]:
        """Delete a message with permission check - validation only, no actual deletion"""
        
        # Sender or group admin can delete
        can_delete = (
            message.sender == user or 
            message.group.admin == user  # Assuming group has admin field
        )
        
        if not can_delete:
            return False, "Permission denied. Only sender or group admin can delete messages"
        
        cls.log_operation("message_delete_validated", {
            'message_id': message.id,
            'deleted_by': user.id,
            'was_admin_action': message.group.admin == user and message.sender != user
        })
        
        return True, "Message can be deleted"
    
    @classmethod
    def get_unread_count(cls, user: User, group: Group = None) -> int:
        """Get unread messages count for user"""
        if group:
            # Unread count for specific group
            last_read = cls._get_last_read_time(user, group)
            return ChatMessage.objects.filter(
                group=group,
                created_at__gt=last_read
            ).exclude(sender=user).count()
        else:
            # Total unread count across all groups
            total = 0
            user_groups = Group.objects.filter(members=user)
            for group in user_groups:
                total += cls.get_unread_count(user, group)
            return total
    
    @classmethod
    def mark_messages_as_read(cls, user: User, group: Group) -> None:
        """Mark messages as read for user in group"""
        # This would typically update a UserGroupReadStatus model
        # For now, we'll just log the operation
        cls.log_operation("messages_marked_read", {
            'user_id': user.id,
            'group_id': group.id,
            'timestamp': timezone.now()
        })
    
    @classmethod
    def _get_last_read_time(cls, user: User, group: Group):
        """Get the last time user read messages in group"""
        # This would typically come from a UserGroupReadStatus model
        # For now, return a default time
        return timezone.now() - timezone.timedelta(days=7)


# ============================================================================
# NOTIFICATION SERVICE
# ============================================================================

class NotificationService(BaseService):
    """Service for notifications and alerts"""
    
    @classmethod
    def notify_plan_created(cls, plan_id: str, creator_name: str, group_id: str = None):
        """Send notification when a plan is created"""
        cls.log_operation("plan_created_notification", {
            'plan_id': plan_id,
            'creator_name': creator_name,
            'group_id': group_id
        })
        
        # Implementation would send actual notifications
        # via email, push notifications, etc.
    
    @classmethod
    def notify_member_added(cls, group_id: str, user_id: str, added_by_id: str):
        """Send notification when member is added to group"""
        cls.log_operation("member_added_notification", {
            'group_id': group_id,
            'user_id': user_id,
            'added_by_id': added_by_id
        })
    
    @classmethod
    def notify_friend_request(cls, from_user_id: str, to_user_id: str):
        """Send notification for friend request"""
        cls.log_operation("friend_request_notification", {
            'from_user_id': from_user_id,
            'to_user_id': to_user_id
        })



