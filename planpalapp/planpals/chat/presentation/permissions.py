from rest_framework.permissions import BasePermission, SAFE_METHODS
from django.utils import timezone

from planpals.chat.infrastructure.models import Conversation
from planpals.models import Group


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

