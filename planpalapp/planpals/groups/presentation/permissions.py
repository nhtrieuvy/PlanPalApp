from rest_framework.permissions import BasePermission, SAFE_METHODS

from planpals.groups.infrastructure.models import Group, GroupMembership


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
        if getattr(group, 'is_public', False):
            return True
        return group.is_member(user)


class IsGroupMember(BasePermission):
    def has_object_permission(self, request, view, obj):
        group = getattr(obj, 'group', obj)
        return group.is_member(request.user)


class IsGroupAdmin(BasePermission):
    def has_object_permission(self, request, view, obj):
        group = getattr(obj, 'group', obj)
        return group.is_admin(request.user)
