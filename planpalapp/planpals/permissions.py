from rest_framework.permissions import BasePermission, SAFE_METHODS
from django.utils import timezone
from django.contrib.auth import get_user_model
from .models import Friendship, Group, Plan, Conversation

User = get_user_model()


class IsAuthenticatedAndActive(BasePermission):
    """
    Optimized authentication + active check
    Clean and efficient permission base class
    """
    
    def has_permission(self, request, view):
        """Check if user is authenticated and active"""
        return (
            request.user and 
            request.user.is_authenticated and 
            request.user.is_active
        )


class PlanPermission(BasePermission):
    """
    Optimized Plan permission using service layer
    Delegates business logic to service layer
    """
    
    def has_permission(self, request, view):
        """Check permission for plan creation - only group admins can create group plans"""
        if request.method == 'POST':
            plan_type = request.data.get('plan_type', 'personal')
            group_id = request.data.get('group_id')
            
            if plan_type == 'group' and group_id:
                try:
                    group = Group.objects.get(id=group_id)
                    # Use service layer for permission check
                    from .integrations import group_service
                    return group_service.can_edit_group(group, request.user)
                except Group.DoesNotExist:
                    return False
            # Personal plans - anyone can create
            return True
        return True  # For other methods, check object permission
    
    def has_object_permission(self, request, view, obj):
        """Use service layer for permission checking"""
        user = request.user
        
        # Import service layer
        from .integrations import plan_service
        
        # Creator always has access
        if obj.creator == user:
            return True
        
        if request.method in SAFE_METHODS:
            return plan_service.can_view_plan(obj, user)
        else:
            return plan_service.can_edit_plan(obj, user)
    
    def _can_view_plan(self, user, plan):
        """Delegate view permission to service layer"""
        from .integrations import plan_service
        return plan_service.can_view_plan(plan, user)
    
    def _can_edit_plan(self, user, plan):
        """Delegate edit permission to service layer"""
        from .integrations import plan_service
        return plan_service.can_edit_plan(plan, user)


class GroupPermission(BasePermission):
    """
    Optimized Group permission using model methods
    Clean separation of view/edit/delete permissions
    """
    
    def has_object_permission(self, request, view, obj):
        """Use model methods for permission checking"""
        user = request.user
        
        if request.method in SAFE_METHODS:
            return self._can_view_group(user, obj)
        elif request.method in ['PUT', 'PATCH']:
            # Use model method for admin check
            return obj.is_admin(user)
        elif request.method == 'DELETE':
            # Only primary admin can delete group
            return obj.admin == user
        return False
    
    def _can_view_group(self, user, group):
        """Delegate view permission to model logic"""
        # Groups are generally viewable by members
        # Add is_public field support if needed in future
        if getattr(group, 'is_public', True):
            return True
        return group.is_member(user)


class GroupMembershipPermission(BasePermission):
    """
    Optimized GroupMembership permission
    Uses model methods for friend and membership checks
    """
    
    def has_object_permission(self, request, view, obj):
        """Handle membership actions using model methods"""
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
            # Only primary admin can promote/demote
            return group.admin == user
        
        # Default: admin access for other actions
        return group.is_admin(user)
    
    def _can_join_group(self, user, group):
        """Check if user can join group"""
        if group.is_member(user):
            return False
        if getattr(group, 'is_public', True):
            return True
        # Use canonical friendship model method
        return Friendship.are_friends(user, group.admin)
    
    def _can_leave_group(self, user, group):
        """Check if user can leave group"""
        return group.is_member(user)
    
    def _can_add_member(self, user, group):
        """Admin can add members - friendship validation in serializer"""
        return group.is_admin(user)


class ChatMessagePermission(BasePermission):
    """
    Optimized ChatMessage permission 
    Supports both group and conversation-based messaging
    """
    
    def has_permission(self, request, view):
        """Check if user can send message to group/conversation"""
        if request.method == 'POST':
            # Support both group and conversation messaging
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
                    return conversation.participants.filter(id=request.user.id).exists()
                except Conversation.DoesNotExist:
                    return False
        return True  # For other methods, check object permission
    
    def has_object_permission(self, request, view, obj):
        """Check message access permissions"""
        user = request.user
        
        # Check if user has access to the conversation/group
        if obj.conversation:
            if not obj.conversation.participants.filter(id=user.id).exists():
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
        """Check if user can edit message - use model properties"""
        if message.sender != user or message.message_type == 'system':
            return False
        # Only text messages can be edited within time limit
        if message.message_type != 'text':
            return False
        time_limit = timezone.timedelta(minutes=15)
        return timezone.now() - message.created_at <= time_limit
    
    def _can_delete_message(self, user, message):
        """Check if user can delete message"""
        # Sender can always delete their own messages
        if message.sender == user:
            return True
        # Group admin can delete messages in group
        if message.conversation and message.conversation.group:
            return message.conversation.group.is_admin(user)
        elif message.group:  # Legacy support
            return message.group.is_admin(user)
        return False


class PlanActivityPermission(BasePermission):
    """
    Optimized PlanActivity permission using model methods
    Supports both personal and group plan activities
    """
    
    def has_permission(self, request, view):
        """Check permission for activity creation"""
        if request.method == 'POST':
            plan_id = request.data.get('plan')
            if plan_id:
                try:
                    plan = Plan.objects.select_related('group').get(id=plan_id)
                    # Use model methods for permission checking
                    if plan.is_group_plan():
                        return plan.group.is_admin(request.user)
                    else:
                        return plan.creator == request.user
                except Plan.DoesNotExist:
                    return False
        return True  # For other methods, check object permission
    
    def has_object_permission(self, request, view, obj):
        """Check activity access permissions using model methods"""
        user = request.user
        plan = obj.plan
        
        # Check plan access first
        if not self._can_access_plan(user, plan):
            return False
        
        if request.method in SAFE_METHODS:
            return True
        elif request.method in ['PUT', 'PATCH', 'DELETE']:
            return self._can_modify_activity(user, plan)
        
        return False
    
    def _can_access_plan(self, user, plan):
        """Check if user can access the plan - delegate to model"""
        if plan.creator == user:
            return True
        
        if plan.is_group_plan() and plan.group:
            return plan.group.is_member(user)
        
        return False
    
    def _can_modify_activity(self, user, plan):
        """Check if user can modify activities - use model methods"""
        if plan.creator == user:
            return True
        
        if plan.is_group_plan() and plan.group:
            return plan.group.is_admin(user)
        
        return False


class FriendshipPermission(BasePermission):
    """
    Optimized Friendship permission for canonical model
    Uses model methods for efficient permission checking
    """
    
    def has_object_permission(self, request, view, obj):
        """Handle friendship actions using canonical model"""
        user = request.user
        action = getattr(view, 'action', None)
        
        # Check if user is part of this friendship using model method
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
        
        # Default: read access for involved users
        return request.method in SAFE_METHODS


class ConversationPermission(BasePermission):
    """
    New permission class for Conversation model
    Supports both direct and group conversations
    """
    
    def has_object_permission(self, request, view, obj):
        """Check conversation access permissions"""
        user = request.user
        
        # Check if user is participant in conversation
        if not obj.participants.filter(id=user.id).exists():
            return False
        
        if request.method in SAFE_METHODS:
            return True
        elif request.method in ['PUT', 'PATCH']:
            # For group conversations, only group admins can edit
            if obj.conversation_type == 'group' and obj.group:
                return obj.group.is_admin(user)
            # For direct conversations, any participant can edit (limited fields)
            return True
        elif request.method == 'DELETE':
            # Only group admin can delete group conversations
            if obj.conversation_type == 'group' and obj.group:
                return obj.group.admin == user
            # Direct conversations can be "left" by any participant
            return True
        
        return False


class UserProfilePermission(BasePermission):
    """
    Optimized User profile permission
    Uses canonical friendship model for access control
    """
    
    def has_object_permission(self, request, view, obj):
        """Check profile access permissions"""
        user = request.user
        target_user = obj
        
        # Users can always access their own profile
        if user == target_user:
            return True
        
        if request.method in SAFE_METHODS:
            return self._can_view_profile(user, target_user)
        else:
            # Only own profile can be edited
            return user == target_user
    
    def _can_view_profile(self, user, target_user):
        """Check if user can view target profile"""
        # Check if profile is public (future feature)
        if getattr(target_user, 'is_profile_public', True):
            return True
        # Use canonical friendship model method
        return Friendship.are_friends(user, target_user)


# Utility permissions - Optimized and clean
class IsOwnerOrReadOnly(BasePermission):
    """
    Owner has full access, others have read-only access
    Flexible owner field detection
    """
    
    def has_object_permission(self, request, view, obj):
        """Check owner permissions with flexible field detection"""
        if request.method in SAFE_METHODS:
            return True
        
        # Try multiple common owner field names
        owner_field = getattr(obj, 'creator', 
                            getattr(obj, 'user', 
                                   getattr(obj, 'owner', None)))
        return owner_field == request.user


class IsGroupMember(BasePermission):
    """
    Must be group member - uses model method
    """
    
    def has_object_permission(self, request, view, obj):
        """Check group membership using model method"""
        group = getattr(obj, 'group', obj)
        return group.is_member(request.user)


class IsGroupAdmin(BasePermission):
    """
    Must be group admin - uses model method
    """
    
    def has_object_permission(self, request, view, obj):
        """Check group admin status using model method"""
        group = getattr(obj, 'group', obj)
        return group.is_admin(request.user)


class IsFriend(BasePermission):
    """
    Must be friends - uses canonical friendship model
    """
    
    def has_object_permission(self, request, view, obj):
        """Check friendship using canonical model method"""
        target_user = getattr(obj, 'user', obj)
        return Friendship.are_friends(request.user, target_user)


class IsConversationParticipant(BasePermission):
    """
    Must be conversation participant - new permission for conversation model
    """
    
    def has_object_permission(self, request, view, obj):
        """Check if user is conversation participant"""
        conversation = getattr(obj, 'conversation', obj)
        return conversation.participants.filter(id=request.user.id).exists()



