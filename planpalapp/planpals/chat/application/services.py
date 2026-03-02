from django.db import transaction
from django.db.models import Q, QuerySet
from django.utils import timezone
from django.core.exceptions import ValidationError
from django.core.files.uploadedfile import UploadedFile
from django.contrib.auth import get_user_model
from typing import Dict, List, Tuple, Any
import logging

from channels.layers import get_channel_layer
from asgiref.sync import async_to_sync

from planpals.shared.base_service import BaseService
from planpals.shared.events import ChannelGroups
from planpals.chat.infrastructure.models import Conversation, ChatMessage, MessageReadStatus
from planpals.models import User, Group, Friendship
from planpals.shared.paginators import ManualCursorPaginator
from planpals.integrations.notification_service import NotificationService

# Commands & factories — thin delegation layer
from planpals.chat.application.commands import (
    EditMessageCommand,
    DeleteMessageCommand,
    MarkMessagesReadCommand,
)
from planpals.chat.application import factories as chat_factories

logger = logging.getLogger(__name__)


class ConversationService(BaseService):
    
    @classmethod
    def create_message(cls, conversation: 'Conversation', sender, 
                      validated_data: Dict[str, Any]) -> 'ChatMessage':
        message_type = validated_data.get('message_type', 'text')
        content = validated_data.get('content', '')
        attachment = validated_data.get('attachment')
        attachment_name = validated_data.get('attachment_name', '')
        attachment_size = validated_data.get('attachment_size')
        reply_to_id = validated_data.get('reply_to_id')
        latitude = validated_data.get('latitude')
        longitude = validated_data.get('longitude')
        location_name = validated_data.get('location_name', '')
        
        
        # Validate reply_to
        reply_to = None
        if reply_to_id:
            try:
                reply_to = ChatMessage.objects.get(
                    id=reply_to_id, 
                    conversation=conversation,
                    is_deleted=False
                )
            except ChatMessage.DoesNotExist:
                raise ValidationError("Reply message not found in this conversation")
        
        if attachment:
            if isinstance(attachment, str):
                attachment = attachment.strip()
                if cls.is_local_path(attachment):
                    raise ValidationError(
                        "Local file paths are not allowed. Please upload the file via multipart request."
                    )
                # Allow Cloudinary URLs/public_ids
            elif isinstance(attachment, UploadedFile):
                # File upload - will be handled by CloudinaryField on save
                pass
            else:
                raise ValidationError("Attachment must be a file upload or valid URL/public_id")
        
        with transaction.atomic():
            message = ChatMessage.objects.create(
                conversation=conversation,
                sender=sender,
                message_type=message_type,
                content=content,
                attachment=attachment,
                attachment_name=attachment_name,
                attachment_size=attachment_size,
                reply_to=reply_to,
                latitude=latitude,
                longitude=longitude,
                location_name=location_name
            )
            
            cls.update_last_message_time(conversation)
            
        transaction.on_commit(lambda: cls._send_realtime_message(message))
        transaction.on_commit(lambda: cls._send_push_notification(message))
        
        cls.log_operation("message_created", {
            'conversation_id': str(conversation.id),
            'message_id': str(message.id),
            'sender_id': str(sender.id) if sender else None,
            'message_type': message_type
        })
        
        return message
    
    @classmethod
    def get_user_conversations(cls, user) -> QuerySet['Conversation']:
        return Conversation.objects.for_user(user).select_related(
            'group', 'user_a', 'user_b',
        ).with_last_message().order_by('-last_message_at')
    
    @classmethod
    def search_user_conversations(cls, user, query: str) -> QuerySet['Conversation']:
        """Search conversations by name, participant names, or group names"""
        if not query or not query.strip():
            return cls.get_user_conversations(user)
        
        query = query.strip().lower()
        conversations = cls.get_user_conversations(user)
        
        search_conditions = Q()
        
        search_conditions |= Q(name__icontains=query)
        
        search_conditions |= Q(group__name__icontains=query)
        
    
        search_conditions |= Q(
            group__members__first_name__icontains=query
        ) | Q(
            group__members__last_name__icontains=query
        ) | Q(
            group__members__username__icontains=query
        )
        
        # For direct conversations, also search the other participant
        search_conditions |= Q(
            user_a__first_name__icontains=query
        ) | Q(
            user_a__last_name__icontains=query
        ) | Q(
            user_a__username__icontains=query
        ) | Q(
            user_b__first_name__icontains=query
        ) | Q(
            user_b__last_name__icontains=query
        ) | Q(
            user_b__username__icontains=query
        )
        
        return conversations.filter(search_conditions).distinct()
    
    @classmethod
    def get_or_create_direct_conversation(cls, user1, user2) -> Tuple['Conversation', bool]:
        if user1 == user2:
            raise ValueError("Cannot create conversation with yourself")
        
        friendship = Friendship.objects.filter(
            Q(user_a=user1, user_b=user2) | Q(user_a=user2, user_b=user1),
            status=Friendship.ACCEPTED
        ).first()
        
        if not friendship:
            raise ValidationError("Users must be friends to start a conversation")
        
        # Check for existing conversation
        existing_conv = Conversation.objects.get_direct_conversation(user1, user2)
        if existing_conv:
            return existing_conv, False
        
        conversation = cls.create_direct_conversation(user1, user2)
        
        cls.log_operation("conversation_created", {
            'conversation_id': str(conversation.id),
            'type': 'direct',
            'participants': [str(user1.id), str(user2.id)]
        })
        
        return conversation, True
    
    @classmethod 
    def create_direct_conversation(cls, user1, user2) -> 'Conversation':
        if user1.id == user2.id:
            raise ValidationError("Cannot create conversation with same user")

        conversation = Conversation.objects.create(
            conversation_type='direct',
            user_a=user1,
            user_b=user2
        )
        
        return conversation
    
    @classmethod
    def get_or_create_group_conversation(cls, group) -> Tuple['Conversation', bool]:
        if hasattr(group, 'conversation') and group.conversation:
            return group.conversation, False
        
        conversation = Conversation.objects.create(
            conversation_type='group',
            group=group,
            name=f"Group Chat: {group.name}"
        )
        
        cls.log_operation("conversation_created", {
            'conversation_id': str(conversation.id),
            'type': 'group',
            'group_id': str(group.id)
        })
        
        return conversation, True

    

    @classmethod
    def get_conversation_messages(cls, user, conversation_id: str, 
                                limit: int = 50, before_id: str = None) -> Dict[str, Any]:
        try:            
            conversation = Conversation.objects.get(id=conversation_id)
            
            if not cls._can_user_access_conversation(user, conversation):
                raise ValidationError("Access denied to this conversation")
            
            queryset = ChatMessage.objects.filter(
                conversation=conversation,
                is_deleted=False
            ).select_related(
                'sender', 'reply_to__sender', 'conversation__group'
            ).order_by('-created_at', '-id')
            
            result = ManualCursorPaginator.paginate_by_id(
                queryset=queryset,
                before_id=before_id,
                limit=limit,
                ordering='-created_at'
            )
            
            return {
                'messages': result['items'],
                'has_more': result['has_more'],
                'next_cursor': result['next_cursor'],
                'count': result['count']
            }
            
        except Conversation.DoesNotExist:
            raise ValidationError("Conversation not found")
    

    @classmethod
    def mark_messages_read(cls, user, conversation_id: str, message_ids: List[str]) -> Tuple[bool, str]:
        try:
            conversation = Conversation.objects.get(id=conversation_id)
            
            if not cls._can_user_access_conversation(user, conversation):
                return False, "Access denied to this conversation"
            
            # Fetch valid message IDs in a single query (exclude own messages)
            valid_ids = list(
                ChatMessage.objects.filter(
                    id__in=message_ids,
                    conversation=conversation
                ).exclude(sender=user).values_list('id', flat=True)
            )
            
            if valid_ids:
                # Bulk create read statuses — single INSERT, ignore duplicates
                read_statuses = [
                    MessageReadStatus(message_id=mid, user=user)
                    for mid in valid_ids
                ]
                MessageReadStatus.objects.bulk_create(read_statuses, ignore_conflicts=True)
            
            user.clear_unread_cache()
            
            cls.log_operation("messages_marked_read", {
                'user_id': str(user.id),
                'conversation_id': str(conversation.id),
                'message_count': len(valid_ids)
            })
            
            return True, f"Marked {len(valid_ids)} messages as read"
            
        except Conversation.DoesNotExist:
            return False, "Conversation not found"
        except Exception as e:
            return False, "Failed to mark messages as read"
    
    @classmethod
    def mark_as_read_for_user(cls, conversation, user, up_to_message=None):
        messages = conversation.messages.active().exclude(sender=user)

        if up_to_message:
            messages = messages.filter(created_at__lte=up_to_message.created_at)
        
        unread_message_ids = messages.exclude(
            read_statuses__user=user
        ).values_list('id', flat=True)
        
        if unread_message_ids:
            read_statuses = [
                MessageReadStatus(message_id=msg_id, user=user)
                for msg_id in unread_message_ids
            ]
            MessageReadStatus.objects.bulk_create(read_statuses, ignore_conflicts=True)
            
            user.clear_unread_cache()
        
        return len(unread_message_ids)
    
    @classmethod
    def get_unread_count_for_user(cls, conversation, user):
        return conversation.messages.unread_for_user(user).count()
    

    @classmethod
    def update_last_message_time(cls, conversation, timestamp=None):
        if timestamp is None:
            timestamp = timezone.now()
            
        if not conversation.last_message_at or timestamp > conversation.last_message_at:
            conversation.last_message_at = timestamp
            conversation.save(update_fields=['last_message_at'])
    
    @classmethod
    def _can_user_access_conversation(cls, user, conversation: 'Conversation') -> bool:
        if conversation.conversation_type == 'direct':
            return conversation.user_a == user or conversation.user_b == user
        elif conversation.conversation_type == 'group' and conversation.group:
            return conversation.group.members.filter(id=user.id).exists()
        return False
    
    @classmethod
    def _send_realtime_message(cls, message: 'ChatMessage'):
        try:
            channel_layer = get_channel_layer()
            if not channel_layer:
                return
            
            # Serialize message
            from planpals.chat.presentation.serializers import ChatMessageSerializer
            serializer = ChatMessageSerializer(message)
            message_data = serializer.data
            
            # Send to conversation channel
            group_name = ChannelGroups.conversation(str(message.conversation.id))
            async_to_sync(channel_layer.group_send)(
                group_name,
                {
                    'type': 'chat_message',
                    'data': message_data
                }
            )
            
        except Exception as e:
            cls.log_error("Error sending realtime message", e)
    
    @classmethod
    def _send_push_notification(cls, message: 'ChatMessage'):
        try:
            
            notification_service = NotificationService()
            
            # Get other participants (exclude sender)
            participants = message.conversation.participants.exclude(id=message.sender.id)
            
            # Send notification to each participant
            for participant in participants:
                if hasattr(participant, 'fcm_token') and participant.fcm_token:
                    
                    if message.conversation.conversation_type == 'direct':
                        title = f"Tin nhắn từ {message.sender.get_full_name() or message.sender.username}"
                    else:
                        group_name = message.conversation.group.name if message.conversation.group else "Nhóm"
                        title = f"{message.sender.get_full_name() or message.sender.username} trong {group_name}"
                    
                    # Format message content based on type
                    if message.message_type == 'text':
                        body = message.content[:100]
                    elif message.message_type == 'image':
                        body = "📷 Đã gửi một hình ảnh"
                    elif message.message_type == 'location':
                        body = f"📍 Đã chia sẻ vị trí: {message.location_name or 'Vị trí'}"
                    elif message.message_type == 'file':
                        body = f"📎 Đã gửi file: {message.attachment_name or 'File'}"
                    else:
                        body = "Đã gửi một tin nhắn"
                    
                    data = {
                        'action': 'new_message',
                        'conversation_id': str(message.conversation.id),
                        'message_id': str(message.id),
                        'sender_id': str(message.sender.id)
                    }
                    
                    notification_service.send_push_notification(
                        [participant.fcm_token],
                        title,
                        body,
                        data
                    )
                    
        except Exception as e:
            cls.log_error("Error sending push notification", e)


class ChatService(BaseService):
    
    @classmethod
    def send_message(cls, sender, group, **validated_data) -> 'ChatMessage':

        # Get or create group conversation
        conversation, created = ConversationService.get_or_create_group_conversation(group)
        
        # Delegate to canonical message creation
        return ConversationService.create_message(
            conversation=conversation,
            sender=sender,
            validated_data=validated_data
        )
    
    @classmethod
    def send_direct_message(cls, sender, recipient, **validated_data) -> 'ChatMessage':

        conversation, created = ConversationService.get_or_create_direct_conversation(sender, recipient)
        
        return ConversationService.create_message(
            conversation=conversation,
            sender=sender,
            validated_data=validated_data
        )
    
    @classmethod
    def create_system_message(cls, conversation=None, group=None, content: str = "") -> 'ChatMessage':
        if conversation is None and group is None:
            raise ValueError("Either conversation or group must be provided")
        
        if group is not None:
            conversation, created = ConversationService.get_or_create_group_conversation(group)
        
        validated_data = {
            'message_type': 'system',
            'content': content
        }
        
        return ConversationService.create_message(
            conversation=conversation,
            sender=None,  # System messages have no sender
            validated_data=validated_data
        )
    
    @classmethod
    def get_group_messages(cls, user, group_id: str, limit: int = 50, before_id: str = None) -> Dict[str, Any]:
        try:            
            group = Group.objects.get(id=group_id)
            
            if not group.members.filter(id=user.id).exists():
                raise ValidationError("Group not found or access denied")
            
            # Get or create group conversation
            conversation, created = ConversationService.get_or_create_group_conversation(group)
            
            # Use conversation service
            return ConversationService.get_conversation_messages(
                user=user,
                conversation_id=str(conversation.id),
                limit=limit,
                before_id=before_id
            )
            
        except Group.DoesNotExist:
            raise ValidationError("Group not found")
    
    @classmethod
    def edit_message(cls, message: ChatMessage, user, new_content: str) -> Tuple[bool, str]:
        """Delegate to EditMessageHandler."""
        cmd = EditMessageCommand(
            message_id=message.id,
            editor_id=user.id,
            new_content=new_content,
        )
        handler = chat_factories.get_edit_message_handler()
        success, msg = handler.handle(cmd)

        if success:
            cls.log_operation("message_edited", {
                'message_id': str(message.id),
                'editor': str(user.id)
            })

        return success, msg
    
    @classmethod
    def delete_message(cls, message: ChatMessage, user) -> Tuple[bool, str]:
        """Delegate to DeleteMessageHandler."""
        cmd = DeleteMessageCommand(
            message_id=message.id,
            deleted_by_id=user.id,
        )
        handler = chat_factories.get_delete_message_handler()
        success, msg = handler.handle(cmd)

        if success:
            cls.log_operation("message_deleted", {
                'message_id': str(message.id),
                'deleted_by': str(user.id),
            })

        return success, msg
    
    @classmethod
    def get_unread_count(cls, user, group=None) -> int:
        if group:
            conversation, created = ConversationService.get_or_create_group_conversation(group)
            return ConversationService.get_unread_count_for_user(conversation, user)
        else:
            return getattr(user, 'unread_messages_count', 0)
    
    @classmethod
    def mark_messages_as_read(cls, user, group) -> None:
        conversation, created = ConversationService.get_or_create_group_conversation(group)
        ConversationService.mark_as_read_for_user(conversation, user)
        
        cls.log_operation("messages_marked_read", {
            'user_id': str(user.id),
            'group_id': str(group.id),
            'timestamp': timezone.now().isoformat()
        })
