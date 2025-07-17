from rest_framework.permissions import BasePermission, IsAuthenticated, SAFE_METHODS
from django.utils import timezone
from django.contrib.auth import get_user_model

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
        from .models import Friendship
        return Friendship.are_friends(user, group.admin)
    
    def _can_leave_group(self, user, group):
        return group.is_member(user)


class ChatMessagePermission(BasePermission):
    """Permission cho chat messages"""
    
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


class FriendshipPermission(BasePermission):
    """Permission cho friendships"""
    
    def has_object_permission(self, request, view, obj):
        user = request.user
        action = getattr(view, 'action', None)
        
        if user not in [obj.sender, obj.receiver]:
            return False
        
        if action == 'accept':
            return obj.receiver == user and obj.status == 'pending'
        elif action == 'reject':
            return obj.receiver == user and obj.status == 'pending'
        elif action == 'cancel':
            return obj.sender == user and obj.status == 'pending'
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
        from .models import Friendship
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



