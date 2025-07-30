from rest_framework.permissions import BasePermission, SAFE_METHODS
from django.utils import timezone
from django.contrib.auth import get_user_model
from .models import Friendship

User = get_user_model()

# Đặc biệt: Permission cho users cần thêm active check
class IsAuthenticatedAndActive(BasePermission):
    """
    Authenticated + Active check
    Chỉ dùng khi cần check is_active
    """
    
    def has_permission(self, request, view):
        return (
            request.user and 
            request.user.is_authenticated and 
            request.user.is_active
        )
        
class PlanPermission(BasePermission):
    """
    Permission cho Plan model - CHỈ BUSINESS LOGIC
    Dùng với IsAuthenticated: permission_classes = [IsAuthenticated, PlanPermission]
    """
    
    def has_permission(self, request, view):
        """Check permission cho việc tạo plan mới"""
        if request.method == 'POST':
            # For creating group plans, check if user is group member
            group_id = request.data.get('group')
            if group_id:
                from .models import Group
                try:
                    group = Group.objects.get(id=group_id)
                    return group.is_member(request.user)
                except Group.DoesNotExist:
                    return False
        return True  # For other methods, check object permission
    
    def has_object_permission(self, request, view, obj):
        """Chỉ kiểm tra business logic, auth đã được IsAuthenticated handle"""
        user = request.user
        
        if obj.creator == user:
            return True
        
        if request.method in SAFE_METHODS: # [GET, HEAD, OPTIONS] các hàm đọc
            return self._can_view_plan(user, obj)
        else:
            return self._can_edit_plan(user, obj)
    
    def _can_view_plan(self, user, plan): # dấu gạch chân ở đầu là private method chỉ dùng trong class này support cho hàm public
        if plan.is_public:
            return True
        if plan.is_group_plan() and plan.group:
            return plan.group.is_member(user)
        return plan.creator == user
    
    def _can_edit_plan(self, user, plan):
        if plan.creator == user:
            return True
        if plan.is_group_plan() and plan.group:
            return plan.group.is_admin(user)
        return False


class GroupPermission(BasePermission):
    """Permission cho Group model"""
    
    def has_object_permission(self, request, view, obj):
        user = request.user
        
        if request.method in SAFE_METHODS:
            return self._can_view_group(user, obj)
        elif request.method in ['PUT', 'PATCH']:
            return obj.is_admin(user)  # Cho phép multiple admins to edit
        elif request.method == 'DELETE':
            return obj.admin == user # Chỉ có primary admin can delete
        return False
    
    def _can_view_group(self, user, group):
        if getattr(group, 'is_public', True): #Trả về True nếu không có field is_public
            return True
        return group.is_member(user)


class GroupMembershipPermission(BasePermission):
    """Permission cho membership actions"""
    
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


class ChatMessagePermission(BasePermission):
    """Permission cho chat messages"""
    
    def has_permission(self, request, view):
        """Check nếu user có thể gửi message vào group"""
        if request.method == 'POST':
            # For creating messages, check if user is group member
            group_id = request.data.get('group') or view.kwargs.get('group_id')
            if group_id:
                from .models import Group
                try:
                    group = Group.objects.get(id=group_id)
                    return group.is_member(request.user)
                except Group.DoesNotExist:
                    return False
        return True  # For other methods, check object permission
    
    def has_object_permission(self, request, view, obj):
        user = request.user
        
        if not obj.group.is_member(user):
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
        time_limit = timezone.timedelta(minutes=15)
        return timezone.now() - message.created_at <= time_limit
    
    def _can_delete_message(self, user, message):
        return message.sender == user or message.group.is_admin(user)


class PlanActivityPermission(BasePermission):
    """Permission cho PlanActivity model - OPTIMIZED"""
    
    def has_object_permission(self, request, view, obj):
        """Check if user can access plan activity"""
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
        """Check if user can access the plan"""
        if plan.created_by == user:
            return True
        
        if plan.is_group_plan() and plan.group:
            return plan.group.is_member(user)
        
        return False
    
    def _can_modify_activity(self, user, plan):
        """Check if user can modify activities in plan"""
        if plan.created_by == user:
            return True
        
        if plan.is_group_plan() and plan.group:
            return plan.group.is_admin(user)
        
        return False


class FriendshipPermission(BasePermission):
    """Permission cho friendships - Updated for user/friend fields"""
    
    def has_object_permission(self, request, view, obj):
        user = request.user
        action = getattr(view, 'action', None)
        
        # ✅ UPDATED - use user/friend instead of sender/receiver
        if user not in [obj.user, obj.friend]:
            return False
        
        if action == 'accept':
            # ✅ UPDATED - friend receives and can accept
            return obj.friend == user and obj.status == 'pending'
        elif action == 'reject':
            # ✅ UPDATED - friend receives and can reject  
            return obj.friend == user and obj.status == 'pending'
        elif action == 'cancel':
            # ✅ UPDATED - user sent and can cancel
            return obj.user == user and obj.status == 'pending'
        elif action in ['block', 'unblock']:
            return True
        
        return request.method in SAFE_METHODS


class UserProfilePermission(BasePermission):
    """Permission cho user profiles"""
    
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


# Utility permissions
class IsOwnerOrReadOnly(BasePermission):
    """Owner full access, others read-only"""
    
    def has_object_permission(self, request, view, obj):
        if request.method in SAFE_METHODS:
            return True
        
        owner_field = getattr(obj, 'creator', getattr(obj, 'user', None))
        return owner_field == request.user


class IsGroupMember(BasePermission):
    """Must be group member"""
    
    def has_object_permission(self, request, view, obj):
        group = getattr(obj, 'group', obj)
        return group.is_member(request.user)


class IsGroupAdmin(BasePermission):
    """Must be group admin"""
    
    def has_object_permission(self, request, view, obj):
        group = getattr(obj, 'group', obj)
        return group.is_admin(request.user)



