from rest_framework import serializers
from django.core.files.uploadedfile import UploadedFile

from planpals.chat.infrastructure.models import Conversation, ChatMessage, MessageReadStatus
from planpals.auth.presentation.serializers import UserSummarySerializer
from planpals.groups.presentation.serializers import GroupSummarySerializer


class ChatMessageSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    conversation = serializers.SerializerMethodField()
    
    sender = UserSummarySerializer(read_only=True)
    reply_to = serializers.SerializerMethodField()
    reply_to_id = serializers.UUIDField(write_only=True, required=False)
    
    attachment = serializers.FileField(required=False, allow_null=True, write_only=True)
    attachment_url = serializers.CharField(read_only=True)
    attachment_size_display = serializers.CharField(read_only=True)
    location_url = serializers.CharField(read_only=True)
    
    can_edit = serializers.SerializerMethodField()
    can_delete = serializers.SerializerMethodField()
    
    class Meta:
        model = ChatMessage
        fields = [
            'id', 'conversation', 'sender', 'message_type', 'content',
            'attachment', 'attachment_url',
            'attachment_name', 'attachment_size', 'attachment_size_display',
            'latitude', 'longitude', 'location_name', 'location_url',
            'reply_to', 'reply_to_id', 'is_edited', 'is_deleted',
            'can_edit', 'can_delete', 'created_at', 'updated_at'
        ]
        read_only_fields = [
            'id', 'sender', 'is_edited', 'is_deleted', 
            'created_at', 'updated_at'
        ]
    
    def get_reply_to(self, obj):
        if obj.reply_to:
            return {
                'id': str(obj.reply_to.id),  # Convert UUID to string
                'content': obj.reply_to.content[:100] + ('...' if len(obj.reply_to.content) > 100 else ''),
                'sender': obj.reply_to.sender.username if obj.reply_to.sender else 'System',
                'message_type': obj.reply_to.message_type
            }
        return None
    
    def get_conversation(self, obj):
        if obj.conversation:
            return str(obj.conversation.id)
        return None
    
    def get_can_edit(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            return (obj.sender == request.user and 
                    obj.message_type == 'text' and 
                    not obj.is_deleted)
        return False
    
    def get_can_delete(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            user = request.user
            if obj.sender == user:
                return True
            if obj.conversation and obj.conversation.group:
                return obj.conversation.group.is_admin(user)
        return False
    
    def validate(self, attrs):        
        message_type = attrs.get('message_type', 'text')
        content = attrs.get('content', '').strip()
        attachment = attrs.get('attachment')
        
        if message_type == 'text':
            if not content:
                raise serializers.ValidationError({
                    'content': 'Text messages must have content'
                })
            # Text messages should not have attachments
            if attachment:
                raise serializers.ValidationError({
                    'attachment': 'Text messages cannot have attachments. Use "image" or "file" type for attachments.'
                })
        
        elif message_type == 'image':
            if not attachment:
                raise serializers.ValidationError({
                    'attachment': 'Image messages must have an attachment'
                })
            
            # Validate image content type for FileField uploads
            if isinstance(attachment, UploadedFile):
                if attachment.content_type and not attachment.content_type.startswith('image/'):
                    raise serializers.ValidationError({
                        'attachment': 'Attachment must be an image file'
                    })
            elif isinstance(attachment, str):
                pass
        
        elif message_type == 'file':
            if not attachment:
                raise serializers.ValidationError({
                    'attachment': 'File messages must have an attachment'
                })
        
        elif message_type == 'location':
            if not (attrs.get('latitude') and attrs.get('longitude')):
                raise serializers.ValidationError({
                    'latitude': 'Location messages must have coordinates',
                    'longitude': 'Location messages must have coordinates'
                })
        
        elif message_type == 'system':
            if not content:
                raise serializers.ValidationError({
                    'content': 'System messages must have content'
                })
        
        return attrs


class MessageReadStatusSerializer(serializers.ModelSerializer):
    user = UserSummarySerializer(read_only=True)
    
    class Meta:
        model = MessageReadStatus
        fields = ['id', 'message', 'user', 'read_at']
        read_only_fields = ['id', 'user', 'read_at']


class ConversationSerializer(serializers.ModelSerializer):
    participants = serializers.SerializerMethodField()
    group = GroupSummarySerializer(read_only=True)
    
    avatar_url = serializers.CharField(read_only=True)
    unread_count = serializers.SerializerMethodField()
    last_message = serializers.SerializerMethodField()
    
    class Meta:
        model = Conversation
        fields = [
            'id', 'conversation_type', 'name', 'avatar', 'avatar_url',
            'group', 'participants', 'last_message_at', 'is_active',
            'unread_count', 'last_message', 'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'created_at', 'updated_at', 'last_message_at']
    
    def to_representation(self, instance):
        data = super().to_representation(instance)
        
        request = self.context.get('request')
        current_user = request.user if request and request.user.is_authenticated else None
        
        data['avatar_url'] = instance.get_avatar_url(current_user)
        
        if instance.conversation_type == 'direct' and current_user:
            other_user = instance.get_other_participant(current_user)
            if other_user:
                data['other_participant'] = {
                    'id': other_user.id,
                    'username': other_user.username,
                    'full_name': other_user.get_full_name(),
                    'is_online': other_user.is_online,
                    'last_seen': other_user.last_seen
                }
        
        return data

    def get_participants(self, obj):
        """Return participants using select_related data for direct chats (no extra query)."""
        if obj.conversation_type == 'direct':
            users = [u for u in (obj.user_a, obj.user_b) if u is not None]
            return UserSummarySerializer(users, many=True, context=self.context).data
        # Group chat — delegates to property (joins through membership)
        return UserSummarySerializer(
            obj.participants, many=True, context=self.context
        ).data
    
    def get_unread_count(self, obj):
        # Try annotation first (set by queryset .annotate(unread_count_annotated=...))
        if hasattr(obj, 'unread_count_annotated'):
            return obj.unread_count_annotated or 0

        from planpals.chat.application.services import ConversationService
    
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            return ConversationService.get_unread_count_for_user(obj, request.user)
        return 0
    
    def get_last_message(self, obj):
        # Use with_last_message() annotations when available — no extra query
        if hasattr(obj, 'last_message_content') and obj.last_message_content:
            sender_name = "System"
            if hasattr(obj, 'last_message_sender_id') and obj.last_message_sender_id:
                # Resolve sender from select_related user_a/user_b for direct,
                # or fall back to username lookup
                if obj.user_a and obj.user_a.id == obj.last_message_sender_id:
                    sender_name = obj.user_a.username
                elif obj.user_b and obj.user_b.id == obj.last_message_sender_id:
                    sender_name = obj.user_b.username
                else:
                    # Group chat — look up sender from cache/single query
                    from django.contrib.auth import get_user_model
                    User = get_user_model()
                    try:
                        sender_name = User.objects.values_list(
                            'username', flat=True
                        ).get(id=obj.last_message_sender_id)
                    except User.DoesNotExist:
                        sender_name = "Unknown"

            content = obj.last_message_content
            return {
                'id': None,
                'content': content[:100] + ('...' if len(content) > 100 else ''),
                'message_type': 'text',
                'sender': sender_name,
                'created_at': getattr(obj, 'last_message_time', obj.last_message_at)
            }

        last_message = getattr(obj, 'prefetched_last_message', None)
        if not last_message:
            last_message = obj.messages.filter(
                is_deleted=False
            ).select_related('sender').order_by('-created_at').first()
        
        if last_message:
            content = last_message.content or ''
            return {
                'id': last_message.id,
                'content': content[:100] + ('...' if len(content) > 100 else ''),
                'message_type': last_message.message_type,
                'sender': last_message.sender.username if last_message.sender else 'System',
                'created_at': last_message.created_at
            }
        return None


class ConversationSummarySerializer(serializers.ModelSerializer):
    avatar_url = serializers.CharField(read_only=True)
    unread_count = serializers.SerializerMethodField()
    
    last_message_preview = serializers.SerializerMethodField()
    
    class Meta:
        model = Conversation
        fields = [
            'id', 'conversation_type', 'avatar_url',
            'last_message_at', 'unread_count', 'last_message_preview', 'is_active'
        ]
    
    def to_representation(self, instance):
        data = super().to_representation(instance)
        
        request = self.context.get('request')
        current_user = request.user if request and request.user.is_authenticated else None
        
        data['avatar_url'] = instance.get_avatar_url(current_user)
        
        if instance.conversation_type == 'group' and instance.group:
            data['group_id'] = instance.group.id
            data['member_count'] = instance.group.member_count
        elif instance.conversation_type == 'direct' and current_user:
            other_user = instance.get_other_participant(current_user)
            if other_user:
                data['other_user_id'] = other_user.id
                data['other_user_online'] = other_user.is_online
        
        return data
    
    def get_unread_count(self, obj):
        from planpals.chat.application.services import ConversationService
        
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            return ConversationService.get_unread_count_for_user(obj, request.user)
        return 0
    
    def get_last_message_preview(self, obj):
        if hasattr(obj, 'last_message_content') and obj.last_message_content:
            sender_name = "System"
            if hasattr(obj, 'last_message_sender_id') and obj.last_message_sender_id:
                # Use select_related user_a/user_b for direct chats
                if obj.user_a and obj.user_a.id == obj.last_message_sender_id:
                    sender_name = obj.user_a.username
                elif obj.user_b and obj.user_b.id == obj.last_message_sender_id:
                    sender_name = obj.user_b.username
                else:
                    from django.contrib.auth import get_user_model
                    User = get_user_model()
                    try:
                        sender_name = User.objects.values_list(
                            'username', flat=True
                        ).get(id=obj.last_message_sender_id)
                    except User.DoesNotExist:
                        sender_name = "Unknown"
            
            content = obj.last_message_content
            return {
                'content': content[:50] + ('...' if len(content) > 50 else ''),
                'sender': sender_name,
                'created_at': getattr(obj, 'last_message_time', obj.last_message_at)
            }
        
        last_message = obj.messages.filter(
            is_deleted=False
        ).select_related('sender').order_by('-created_at').first()
        if last_message:
            return {
                'content': last_message.content[:50] + ('...' if len(last_message.content) > 50 else ''),
                'sender': last_message.sender.username if last_message.sender else 'System',
                'created_at': last_message.created_at
            }
        
        return None
