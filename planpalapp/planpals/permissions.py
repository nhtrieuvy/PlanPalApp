from rest_framework.permissions import BasePermission, SAFE_METHODS
from django.utils import timezone
from django.contrib.auth import get_user_model
from .models import Friendship, Group, Plan, Conversation
from .services import GroupService, PlanService
User = get_user_model()


class IsAuthenticatedAndActive(BasePermission):
    def has_permission(self, request, view):
        return (
            request.user and 
            request.user.is_authenticated and 
            request.user.is_active
        )


class PlanPermission(BasePermission):
    def has_permission(self, request, view):
        if request.method == 'POST':
            plan_type = request.data.get('plan_type', 'personal')
            group_id = request.data.get('group_id')
            
            if plan_type == 'group' and group_id:
                try:
                    group = Group.objects.get(id=group_id)
                    return GroupService.can_edit_group(group, request.user)
                except Group.DoesNotExist:
                    return False
            return True
        return True 
    
    def has_object_permission(self, request, view, obj):
        user = request.user
                
        if obj.creator == user:
            return True
        
        if request.method in SAFE_METHODS:
            return PlanService.can_view_plan(obj, user)
        else:
            return PlanService.can_edit_plan(obj, user)



class GroupPermission(BasePermission):
    def has_object_permission(self, request, view, obj):
        user = request.user
        
        if request.method in SAFE_METHODS:
            return self._can_view_group(user, obj)
        elif request.method in ['PUT', 'PATCH']:
            return obj.is_admin(user)
        elif request.method == 'DELETE':
            return obj.admin == user
        return False
    
    def _can_view_group(self, user, group):
        if getattr(group, 'is_public', True):
            return True
        return group.is_member(user)


class GroupMembershipPermission(BasePermission):
    def has_object_permission(self, request, view, obj):
        user = request.user
        action = getattr(view, 'action', None)
        group = getattr(obj, 'group', obj)
        
        if action == 'join':
            return self._can_join_group(user, group)
        elif action == 'leave':
            return self._can_leave_group(user, group)
        elif action in ['kick', 'remove_member']:
            return group.is_admin(user)
        elif action == 'add_member':
            return self._can_add_member(user, group)
        elif action in ['promote', 'demote']:
            return group.admin == user
        
        return group.is_admin(user)
    
    def _can_join_group(self, user, group):
        if group.is_member(user):
            return False
        if getattr(group, 'is_public', True):
            return True
        return Friendship.are_friends(user, group.admin)
    
    def _can_leave_group(self, user, group):
        return group.is_member(user)
    
    def _can_add_member(self, user, group):
        return group.is_admin(user)


class ChatMessagePermission(BasePermission):    
    def has_permission(self, request, view):
        if request.method == 'POST':
            group_id = request.data.get('group') or view.kwargs.get('group_id')
            conversation_id = request.data.get('conversation') or view.kwargs.get('conversation_id')
            
            if group_id:
                try:
                    group = Group.objects.get(id=group_id)
                    return group.is_member(request.user)
                except Group.DoesNotExist:
                    return False
            elif conversation_id:
                try:
                    conversation = Conversation.objects.get(id=conversation_id)
                    return conversation.is_participant(request.user)
                except Conversation.DoesNotExist:
                    return False
        return True  
    
    def has_object_permission(self, request, view, obj):
        user = request.user
        
        if obj.conversation:
            if not obj.conversation.is_participant(user):
                return False
        elif obj.group:  # Legacy group support
            if not obj.group.is_member(user):
                return False
        else:
            return False
        
        if request.method in SAFE_METHODS:
            return True
        elif request.method in ['PUT', 'PATCH']:
            return self._can_edit_message(user, obj)
        elif request.method == 'DELETE':
            return self._can_delete_message(user, obj)
        return False
    
    def _can_edit_message(self, user, message):
        if message.sender != user or message.message_type == 'system':
            return False
        if message.message_type != 'text':
            return False
        time_limit = timezone.timedelta(minutes=15)
        return timezone.now() - message.created_at <= time_limit
    
    def _can_delete_message(self, user, message):
        if message.sender == user:
            return True
        if message.conversation and message.conversation.group:
            return message.conversation.group.is_admin(user)
        elif message.group:
            return message.group.is_admin(user)
        return False


class PlanActivityPermission(BasePermission):
    def has_permission(self, request, view):
        if request.method == 'POST':
            plan_id = request.data.get('plan')
            if plan_id:
                try:
                    plan = Plan.objects.select_related('group').get(id=plan_id)
                    if plan.is_group_plan():
                        return plan.group.is_admin(request.user)
                    else:
                        return plan.creator == request.user
                except Plan.DoesNotExist:
                    return False
        return True  # For other methods, check object permission
    
    def has_object_permission(self, request, view, obj):
        user = request.user
        plan = obj.plan
        
        if not self._can_access_plan(user, plan):
            return False
        
        if request.method in SAFE_METHODS:
            return True
        elif request.method in ['PUT', 'PATCH', 'DELETE']:
            return self._can_modify_activity(user, plan)
        
        return False
    
    def _can_access_plan(self, user, plan):
        if plan.creator == user:
            return True
        
        if plan.is_group_plan() and plan.group:
            return plan.group.is_member(user)
        
        return False
    
    def _can_modify_activity(self, user, plan):
        if plan.creator == user:
            return True
        
        if plan.is_group_plan() and plan.group:
            return plan.group.is_admin(user)
        
        return False


class FriendshipPermission(BasePermission):    
    def has_object_permission(self, request, view, obj):
        user = request.user
        action = getattr(view, 'action', None)
        
        if user not in [obj.user_a, obj.user_b]:
            return False
        
        if action == 'accept':
            # Only the receiver (non-initiator) can accept
            return obj.can_be_accepted_by(user)
        elif action == 'reject':
            # Only the receiver can reject
            return obj.can_be_accepted_by(user) and obj.status == 'pending'
        elif action == 'cancel':
            # Only the initiator can cancel
            return obj.is_initiated_by(user) and obj.status == 'pending'
        elif action in ['block', 'unblock']:
            # Either user can block/unblock
            return True
        
        return request.method in SAFE_METHODS


class ConversationPermission(BasePermission):
    def has_object_permission(self, request, view, obj):
        user = request.user
        
        if not obj.is_participant(user):
            return False
        
        if request.method in SAFE_METHODS:
            return True
        elif request.method in ['PUT', 'PATCH']:
            if obj.conversation_type == 'group' and obj.group:
                return obj.group.is_admin(user)
            return True
        elif request.method == 'DELETE':
            if obj.conversation_type == 'group' and obj.group:
                return obj.group.admin == user
            return True
        
        return False


class UserProfilePermission(BasePermission):    
    def has_object_permission(self, request, view, obj):
        user = request.user
        target_user = obj
        
        if user == target_user:
            return True
        
        if request.method in SAFE_METHODS:
            return self._can_view_profile(user, target_user)
        else:
            return user == target_user
    
    def _can_view_profile(self, user, target_user):
        if getattr(target_user, 'is_profile_public', True):
            return True
        return Friendship.are_friends(user, target_user)


class IsOwnerOrReadOnly(BasePermission):
    def has_object_permission(self, request, view, obj):
        if request.method in SAFE_METHODS:
            return True
        
        owner_field = getattr(obj, 'creator', 
                            getattr(obj, 'user', 
                                   getattr(obj, 'owner', None)))
        return owner_field == request.user


class IsGroupMember(BasePermission):
    def has_object_permission(self, request, view, obj):
        group = getattr(obj, 'group', obj)
        return group.is_member(request.user)


class IsGroupAdmin(BasePermission):
    def has_object_permission(self, request, view, obj):
        group = getattr(obj, 'group', obj)
        return group.is_admin(request.user)


class IsFriend(BasePermission):
    def has_object_permission(self, request, view, obj):
        target_user = getattr(obj, 'user', obj)
        return Friendship.are_friends(request.user, target_user)


class IsConversationParticipant(BasePermission):
    def has_object_permission(self, request, view, obj):
        conversation = getattr(obj, 'conversation', obj)
        return conversation.is_participant(request.user)


class CanNotTargetSelf(BasePermission):
    """Permission to ensure user cannot target themselves for friendship actions"""
    def has_object_permission(self, request, view, obj):
        # obj is the target user
        return request.user != obj


class CanViewUserProfile(BasePermission):
    """Permission to check if user can view another user's profile"""
    def has_object_permission(self, request, view, obj):
        target_user = obj
        current_user = request.user
        
        # Can always view own profile
        if current_user == target_user:
            return True
        
        # Check if profile is public or if they are friends
        if getattr(target_user, 'is_profile_public', True):
            return True
        
        return Friendship.are_friends(current_user, target_user)


class CanManageFriendship(BasePermission):
    """Permission for friendship management (block, unblock, unfriend)"""
    def has_object_permission(self, request, view, obj):
        target_user = obj
        current_user = request.user
        
        # Cannot target self
        if current_user == target_user:
            return False
        
        # For unfriend: must be friends
        if view.action == 'unfriend':
            return Friendship.are_friends(current_user, target_user)
        
        # For block/unblock: always allowed (business logic in service)
        return True


class CanEditMyPlans(BasePermission):
    """Permission for plan filtering by type"""
    def has_permission(self, request, view):
        return True  # Basic filtering, no special permission needed


class IsOwnerOrGroupAdmin(BasePermission):
    """Permission to check if user is owner or group admin for plan actions"""
    def has_object_permission(self, request, view, obj):
        user = request.user
        
        # If it's a plan
        if hasattr(obj, 'creator'):
            plan = obj
            if plan.creator == user:
                return True
            
            if plan.is_group_plan() and plan.group:
                return plan.group.is_admin(user)
        
        return False


class CanJoinPlan(BasePermission):
    """Permission to check if user can join a plan"""
    def has_object_permission(self, request, view, obj):
        plan = obj
        user = request.user
        
        # Cannot join own plan
        if plan.creator == user:
            return False
        
        # For group plans, check if user can join the group
        if plan.plan_type == 'group' and plan.group:
            # Already a member
            if plan.group.members.filter(id=user.id).exists():
                return False
            
            # Check if group allows joining (public or admin invites)
            if getattr(plan.group, 'is_public', True):
                return True
            
            # Could add more complex logic here
            return True
        
        # For personal plans, generally not joinable
        return plan.is_public


class CanAccessPlan(BasePermission):
    """Permission for accessing plan details and activities"""
    
    def has_object_permission(self, request, view, obj):
        plan = obj
        user = request.user
        
        # Owner can always access
        if plan.creator == user:
            return True
        
        # For group plans, check if user is a member
        if plan.plan_type == 'group' and plan.group:
            return plan.group.is_member(user)
        
        # For personal plans, only owner can access
        return False


class CanModifyPlan(BasePermission):
    """Permission for modifying plan activities and details"""
    
    def has_object_permission(self, request, view, obj):
        plan = obj
        user = request.user
        
        # Owner can always modify
        if plan.creator == user:
            return True
        
        # For group plans, check if user is group admin or member (depending on settings)
        if plan.plan_type == 'group' and plan.group:
            # Group admin can always modify
            if plan.group.admin == user:
                return True
            # For now, all members can modify (can be changed based on requirements)
            return plan.group.is_member(user)
        
        return False