from rest_framework.permissions import BasePermission, SAFE_METHODS

from planpals.groups.infrastructure.models import Group, GroupMembership
from planpals.models import Friendship


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


class IsGroupMember(BasePermission):
    def has_object_permission(self, request, view, obj):
        group = getattr(obj, 'group', obj)
        return group.is_member(request.user)


class IsGroupAdmin(BasePermission):
    def has_object_permission(self, request, view, obj):
        group = getattr(obj, 'group', obj)
        return group.is_admin(request.user)
