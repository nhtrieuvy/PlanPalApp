from rest_framework.permissions import BasePermission, SAFE_METHODS
from django.utils import timezone
from django.contrib.auth import get_user_model
from django.db import models
from planpals.auth.infrastructure.models import Friendship, User

User = get_user_model()


class IsAuthenticatedAndActive(BasePermission):
    def has_permission(self, request, view):
        return (
            request.user and 
            request.user.is_authenticated and 
            request.user.is_active
        )


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


class IsFriend(BasePermission):
    def has_object_permission(self, request, view, obj):
        target_user = getattr(obj, 'user', obj)
        return Friendship.are_friends(request.user, target_user)


class CanNotTargetSelf(BasePermission):
    def has_object_permission(self, request, view, obj):
        return request.user != obj


class CanViewUserProfile(BasePermission):
    def has_object_permission(self, request, view, obj):
        target_user = obj
        current_user = request.user
        
        from planpals.auth.application.services import UserService
        return UserService.can_view_profile(current_user, target_user)


class CanManageFriendship(BasePermission):
    def has_object_permission(self, request, view, obj):
        target_user = obj
        current_user = request.user
        
        if current_user == target_user:
            return False
        
        if view.action == 'unfriend':
            return Friendship.are_friends(current_user, target_user)
        
        return True
