"""
Chat Infrastructure — Django ORM Models

These are Django ORM model definitions (persistence concern).
They live in the infrastructure layer because they depend on Django's ORM.

The domain layer (entities.py, repositories.py, events.py) is pure Python.
"""
from uuid import UUID
from typing import Optional, Union, Any

from django.conf import settings
from django.db import models
from django.db.models import Q, Exists, OuterRef, Subquery, QuerySet
from django.core.exceptions import ValidationError

from cloudinary.models import CloudinaryField
from cloudinary import CloudinaryImage, CloudinaryResource

from planpals.shared.base_models import BaseModel


class ConversationQuerySet(models.QuerySet['Conversation']):    
    def active(self) -> 'ConversationQuerySet':
        return self.filter(is_active=True)
    
    def for_user(self, user) -> 'ConversationQuerySet':
        user_id = getattr(user, 'id', user)
        return self.filter(
            Q(conversation_type='group', group__members=user_id) |
            Q(conversation_type='direct', user_a=user_id) |
            Q(conversation_type='direct', user_b=user_id)
        ).distinct()
    
    def direct_chats(self) -> 'ConversationQuerySet':
        return self.filter(conversation_type='direct')
    
    def group_chats(self) -> 'ConversationQuerySet':
        return self.filter(conversation_type='group')
    
    def with_last_message(self) -> 'ConversationQuerySet':
        last_message_subquery = ChatMessage.objects.filter(
            conversation=OuterRef('pk'),
            is_deleted=False
        ).order_by('-created_at')
        
        return self.annotate(
            last_message_id=Subquery(last_message_subquery.values('id')[:1]),
            last_message_time=Subquery(last_message_subquery.values('created_at')[:1]),
            last_message_content=Subquery(last_message_subquery.values('content')[:1]),
            last_message_message_type=Subquery(last_message_subquery.values('message_type')[:1]),
            last_message_sender_id=Subquery(last_message_subquery.values('sender_id')[:1]),
            last_message_sender_username=Subquery(last_message_subquery.values('sender__username')[:1]),
            last_message_attachment_name=Subquery(last_message_subquery.values('attachment_name')[:1]),
            last_message_location_name=Subquery(last_message_subquery.values('location_name')[:1]),
        ).select_related('group', 'user_a', 'user_b')

    def get_direct_conversation(self, user1, user2) -> Optional['Conversation']:
        user1_id = getattr(user1, 'id', user1)
        user2_id = getattr(user2, 'id', user2)
        
        return self.filter(
            conversation_type='direct'
        ).filter(
            (Q(user_a=user1_id) & Q(user_b=user2_id)) |
            (Q(user_a=user2_id) & Q(user_b=user1_id))
        ).first()


class Conversation(BaseModel):
    CONVERSATION_TYPES = [
        ('direct', 'Chat cá nhân'),
        ('group', 'Chat nhóm'),
    ]
    
    conversation_type = models.CharField(
        max_length=10,
        choices=CONVERSATION_TYPES,
        db_index=True,
        help_text="Conversation type"
    )
    
    group = models.OneToOneField(
        'planpals.Group',
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name='conversation',
        help_text="Group (only for group conversations)"
    )
    
    user_a = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name='direct_conversations_as_a',
        help_text="First participant in direct conversation (smaller UUID)"
    )
    
    user_b = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name='direct_conversations_as_b',
        help_text="Second participant in direct conversation (larger UUID)"
    )

    # Conversation metadata
    name = models.CharField(
        max_length=200,
        blank=True,
        help_text="Coversation name"
    )
    
    avatar = CloudinaryField(
        'image',
        blank=True,
        null=True,
        folder='planpal/conversations/avatars',
        transformation={
            'width': 200,
            'height': 200,
            'crop': 'fill',
            'gravity': 'face',
            'quality': 'auto:good'
        },
        help_text="Conversation avatar"
    )
    
    last_message_at = models.DateTimeField(
        null=True,
        blank=True,
        db_index=True,
        help_text="Timestamp of the last message in the conversation"
    )
    
    
    # Custom manager
    objects = ConversationQuerySet.as_manager()

    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_conversations'
        constraints = [
            models.CheckConstraint(
                condition=Q(conversation_type='group', group__isnull=False) |
                          ~Q(conversation_type='group'),
                name='group_conv_must_have_group'
            ),
            models.CheckConstraint(
                condition=Q(conversation_type='direct', user_a__isnull=False, user_b__isnull=False) |
                          ~Q(conversation_type='direct'),
                name='direct_conv_must_have_users'
            ),
            models.CheckConstraint(
                condition=Q(conversation_type='group', user_a__isnull=True, user_b__isnull=True) |
                          Q(conversation_type='direct', group__isnull=True),
                name='exclusive_conversation_types'
            ),
        ]
        indexes = [
            *BaseModel.Meta.indexes,
            models.Index(fields=['conversation_type', 'is_active']),
            models.Index(fields=['group', 'is_active']),  # Group conversations
            models.Index(fields=['user_a', 'user_b']),    # Direct conversations exact pair
            models.Index(fields=['last_message_at']),
            models.Index(fields=['is_active', 'last_message_at']),
            # For Conversation.for_user() — direct branch filters by single user:
            models.Index(fields=['conversation_type', 'user_a']),
            models.Index(fields=['conversation_type', 'user_b']),
        ]

    def __str__(self) -> str:
        if self.conversation_type == 'group' and self.group:
            return f"Group: {self.group.name}"
        elif self.conversation_type == 'direct' and self.user_a and self.user_b:
            return f"Direct: {self.user_a.username} & {self.user_b.username}"
        return f"Conversation {self.id}"

    def clean(self) -> None:
        if self.conversation_type == 'group' and not self.group:
            raise ValidationError("Group conversation must have a group")
        
        if self.conversation_type == 'direct' and self.group:
            raise ValidationError("Direct conversation cannot have a group")
        
        if self.conversation_type == 'direct' and (not self.user_a or not self.user_b):
            raise ValidationError("Direct conversation must have both users")
        
        if self.conversation_type == 'direct' and self.user_a_id and self.user_b_id:
            if self.user_a_id > self.user_b_id:
                raise ValidationError("Direct conversation: user_a must have smaller UUID than user_b")

    def save(self, *args: Any, **kwargs: Any) -> None:
        if self.conversation_type == 'direct' and self.user_a_id and self.user_b_id:
            if self.user_a_id > self.user_b_id:
                self.user_a, self.user_b = self.user_b, self.user_a
        
        self.clean()
        super().save(*args, **kwargs)

    @property
    def participants(self):
        from django.contrib.auth import get_user_model
        User = get_user_model()
        if self.conversation_type == 'group' and self.group:
            return self.group.members.all()
        elif self.conversation_type == 'direct' and self.user_a and self.user_b:
            return User.objects.filter(id__in=[self.user_a_id, self.user_b_id])
        return User.objects.none()

    
    def get_avatar_url(self, current_user=None) -> Optional[str]:
        if self.avatar:
            cloudinary_image = CloudinaryImage(str(self.avatar))
            return cloudinary_image.build_url(secure=True)
        
        if self.conversation_type == 'group' and self.group:
            return self.group.avatar_url
        
        if self.conversation_type == 'direct' and current_user:
            other_user = self.get_other_participant(current_user)
            if other_user:
                return other_user.avatar_url
        return None

    

    def get_other_participant(self, user):
        if self.conversation_type != 'direct':
            return None
        return self.user_b if self.user_a_id == user.id else self.user_a

    def is_participant(self, user) -> bool:
        if self.conversation_type == 'group' and self.group:
            return self.group.is_member(user)
        elif self.conversation_type == 'direct':
            return user.id in [self.user_a_id, self.user_b_id]
        return False

    @property
    def participant_count(self) -> int:
        if self.conversation_type == 'group' and self.group:
            return self.group.member_count
        elif self.conversation_type == 'direct':
            return 2
        return 0


class ChatMessageQuerySet(models.QuerySet['ChatMessage']):    
    def active(self) -> 'ChatMessageQuerySet':
        return self.filter(is_deleted=False)

    def for_conversation(self, conversation) -> 'ChatMessageQuerySet':
        return self.filter(conversation=conversation)
    
    def for_group(self, group) -> 'ChatMessageQuerySet':
        return self.filter(group=group)
    
    def for_user(self, user) -> 'ChatMessageQuerySet':
        return self.filter(sender=user)
    
    def by_user(self, user) -> 'ChatMessageQuerySet':
        return self.filter(sender=user)
    
    def recent(self, limit: int = 50) -> 'ChatMessageQuerySet':
        return self.order_by('-created_at')[:limit]
    
    def with_read_status(self, user) -> 'ChatMessageQuerySet':
        return self.annotate(
            is_read_by_user=Exists(
                MessageReadStatus.objects.filter(
                    message=OuterRef('pk'),
                    user=user
                )
            )
        )
    
    def unread_for_user(self, user) -> 'ChatMessageQuerySet':
        return self.active().exclude(sender=user).exclude(
            Exists(
                MessageReadStatus.objects.filter(
                    message=OuterRef('pk'),
                    user=user
                )
            )
        )
    
    def by_type(self, message_type: str) -> 'ChatMessageQuerySet':
        return self.filter(message_type=message_type)
    
    def text_messages(self) -> 'ChatMessageQuerySet':
        return self.filter(message_type='text')
    
    def system_messages(self) -> 'ChatMessageQuerySet':
        return self.filter(message_type='system')
    
    def with_attachments(self) -> 'ChatMessageQuerySet':
        return self.exclude(attachment='')


class ChatMessage(BaseModel):
    MESSAGE_TYPES = [
        ('text', 'Văn bản'),
        ('image', 'Hình ảnh'),
        ('file', 'File đính kèm'),
        ('location', 'Vị trí'),
        ('system', 'Thông báo hệ thống'),
    ]
    
    conversation = models.ForeignKey(
        Conversation,
        on_delete=models.CASCADE,
        related_name='messages',
        null=True,  # Keep nullable to handle existing messages
        blank=True,
        help_text="The conversation contains this message"
    )
    
    sender = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='sent_messages',
        null=True,  # Null cho system messages
        blank=True,
        help_text="Sender"
    )
    
    message_type = models.CharField(
        max_length=20,
        choices=MESSAGE_TYPES,
        default='text',
        db_index=True,
        help_text="Message type"
    )
    
    # Nội dung tin nhắn
    content = models.TextField(
        null=True,
        blank=True,
        help_text="Message content"
    )
    
    attachment = CloudinaryField(
        'file',
        blank=True,
        null=True,
        folder='planpal/messages/attachments',
        resource_type='auto',
        help_text="Attachment file (image, document, etc.)"
    )
    
    attachment_name = models.CharField(
        max_length=255,
        blank=True,
        help_text="Original file name"
    )

    attachment_resource_type = models.CharField(
        max_length=20,
        blank=True,
        default='',
        help_text="Cloudinary resource type for attachment"
    )
    
    attachment_size = models.PositiveIntegerField(
        blank=True,
        null=True,
        help_text="File size (bytes)"
    )
    
    latitude = models.DecimalField(
        max_digits=9,
        decimal_places=6,
        blank=True,
        null=True,
        help_text="Latitude of location"
    )
    
    longitude = models.DecimalField(
        max_digits=9,
        decimal_places=6,
        blank=True,
        null=True,
        help_text="Longitude of location"
    )
    
    location_name = models.CharField(
        max_length=200,
        blank=True,
        help_text="Location name"
    )
    
    reply_to = models.ForeignKey(
        'self',
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name='replies',
        help_text="Reply to message"
    )
    
    # Message status
    is_edited = models.BooleanField(
        default=False,
        help_text="Message has been edited"
    )
    
    is_deleted = models.BooleanField(
        default=False,
        db_index=True,
        help_text="Message has been deleted (soft delete)"
    )
    
    objects = ChatMessageQuerySet.as_manager()

    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_chat_messages'
        ordering = ['created_at']
        
        indexes = [
            *BaseModel.Meta.indexes,
            # NEW: Index cho conversation (primary)
            models.Index(fields=['conversation', 'created_at']),
            models.Index(fields=['conversation', 'is_deleted', 'created_at']),
            # Index cho query messages của user
            models.Index(fields=['sender', 'created_at']),
            # Index cho query theo type
            models.Index(fields=['message_type', 'created_at']),
        ]

    def __str__(self) -> str:
        if self.conversation:
            conv_label = self.conversation.name or f"Conversation {self.conversation.id}"
        else:
            conv_label = "unknown location"

        if self.sender:
            return f"{self.sender.username} in {conv_label}: {self.content[:50]}..."
        return f"System message in {conv_label}: {self.content[:50]}..."

    def clean(self) -> None:
        if self.message_type == 'system' and self.sender is not None:
            raise ValidationError("System message cannot have a sender")
        
        # Non-system messages cần sender
        if self.message_type != 'system' and self.sender is None:
            raise ValidationError("Non-system message must have a sender")
        
        # Location messages cần coordinates
        if self.message_type == 'location':
            if self.latitude is None or self.longitude is None:
                raise ValidationError("Location message must have latitude and longitude")

    @property
    def is_text_message(self):
        return self.message_type == 'text'

    @property
    def is_image_message(self):
        return self.message_type == 'image'

    @property
    def is_file_message(self):
        return self.message_type == 'file'

    @property
    def is_location_message(self):
        return self.message_type == 'location'

    @property
    def has_attachment(self):
        return bool(self.attachment)

    @property
    def attachment_url(self):
        if not self.has_attachment:
            return None
        attachment_identifier = str(self.attachment)
        if attachment_identifier.startswith(('http://', 'https://')):
            return attachment_identifier
        resource_type = self.attachment_resource_type or (
            'image' if self.message_type == 'image' else 'raw'
        )
        if attachment_identifier and resource_type == 'image':
            cloudinary_image = CloudinaryImage(attachment_identifier)
            return cloudinary_image.build_url(secure=True)
        if attachment_identifier:
            cloudinary_resource = CloudinaryResource(
                attachment_identifier,
                resource_type=resource_type,
                type='upload',
            )
            return cloudinary_resource.build_url(secure=True)
        return None

    @property
    def attachment_size_display(self):
        if not self.attachment_size:
            return None
        
        size = self.attachment_size
        for unit in ['B', 'KB', 'MB', 'GB']:
            if size < 1024.0:
                return f"{size:.1f} {unit}"
            size /= 1024.0
        return f"{size:.1f} TB"

    @property
    def location_url(self):
        if self.latitude is not None and self.longitude is not None:
            return f"https://maps.google.com/?q={self.latitude},{self.longitude}"
        return None

    def soft_delete(self):
        self.is_deleted = True
        self.content = "[Tin nhắn đã bị xóa]"
        self.save(update_fields=['is_deleted', 'content', 'updated_at'])

    def save(self, *args: Any, **kwargs: Any) -> None:
        if not hasattr(self, '_clean_called'):
            self.clean()
            self._clean_called = True
        
        super().save(*args, **kwargs)
        
        if self.conversation and not self.is_deleted:
            if not self.conversation.last_message_at or self.created_at > self.conversation.last_message_at:
                self.conversation.last_message_at = self.created_at
                self.conversation.save(update_fields=['last_message_at'])
        
        # Clear unread message cache for participants
        if self.conversation:
            from django.contrib.auth import get_user_model
            User = get_user_model()
            participant_ids = list(self.conversation.participants.values_list('id', flat=True))
            User.clear_unread_cache_for_users(participant_ids)

    
class MessageReadStatus(BaseModel):
    message = models.ForeignKey(
        ChatMessage,
        on_delete=models.CASCADE,
        related_name='read_statuses',
        help_text="Message that has been read"
    )
    
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='message_read_statuses',
        help_text="User who has read the message"
    )
    
    read_at = models.DateTimeField(
        auto_now_add=True,
        help_text="Time when the message was read"
    )

    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_message_read_statuses'
        # Mỗi user chỉ đọc 1 message 1 lần
        unique_together = ('message', 'user')
        
        indexes = [
            *BaseModel.Meta.indexes,
            # unique_together('message','user') already covers message lookups
            # Removed [message, read_at] — not used in any WHERE clause
            # Index for "all messages read by user X" queries
            models.Index(fields=['user', 'read_at']),
        ]
        
        ordering = ['read_at']

    def __str__(self) -> str:
        return f"{self.user.username} read message {self.message.id}"
