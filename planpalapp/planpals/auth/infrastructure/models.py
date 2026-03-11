"""
Auth Infrastructure — Django ORM Models

These are Django ORM model definitions (persistence concern).
They live in the infrastructure layer because they depend on Django's ORM.

The domain layer (entities.py, repositories.py, events.py) is pure Python.
"""
from uuid import UUID, uuid4
from collections import defaultdict
from decimal import Decimal
from datetime import datetime, timedelta, date
from typing import Dict, List, Optional, Any, Union, Tuple

from django.db import models, transaction, IntegrityError
from django.db.models import constraints, QuerySet
from django.contrib.auth.models import AbstractUser, UserManager as DjangoUserManager
from django.utils import timezone
from django.core.validators import RegexValidator
from django.core.exceptions import ValidationError, PermissionDenied
from django.db.models import Q, F, Case, When, Count, Max, Sum, Exists, OuterRef, Subquery
from django.core.cache import cache

from cloudinary.models import CloudinaryField
from cloudinary import CloudinaryImage

from celery import current_app

from planpals.shared.base_models import BaseModel
from planpals.auth.domain.entities import FriendshipStatus


class UserQuerySet(models.QuerySet['User']):

    def with_friends_count(self) -> 'UserQuerySet':
        return self.annotate(
            friends_count_annotated=Count(
                'friendships_as_a',
                filter=Q(friendships_as_a__status='accepted'),
                distinct=True
            ) + Count(
                'friendships_as_b',
                filter=Q(friendships_as_b__status='accepted'),
                distinct=True
            )
        )
    
    def with_plans_count(self) -> 'UserQuerySet':
        return self.annotate(
            # Truy vấn ngược, sử dụng related_name 'created_plans'
            # Tương tự count=Count('plan', filter=Q(plan__creator=F('id')))
            plans_count_annotated=Count('created_plans', distinct=True),
            personal_plans_count_annotated=Count(
                'created_plans',
                filter=Q(created_plans__plan_type='personal'),
                distinct=True
            ),
            group_plans_count_annotated=Count(
                'joined_groups__plans',
                filter=Q(joined_groups__plans__plan_type='group'),
                distinct=True
            )
        )
    
    def with_groups_count(self) -> 'UserQuerySet':
        return self.annotate(
            groups_count_annotated=Count(
                'joined_groups',
                filter=Q(joined_groups__is_active=True),
                distinct=True
            )
        )
    
    def with_friend_request_counts(self) -> 'UserQuerySet':
        return self.annotate(
            # Đếm số lượng yêu cầu kết bạn mà người dùng đã gửi đi
            pending_sent_count_annotated=Count(
                'initiated_friendships',
                filter=Q(initiated_friendships__status='pending'),
                distinct=True
            ),
            # Đếm số lượng yêu cầu kết bạn mà người dùng đã nhận nhưng chưa phản hồi
            pending_received_count_annotated=(
                Count(
                    'friendships_as_a',
                    filter=Q(friendships_as_a__status='pending') & ~Q(friendships_as_a__initiator_id=F('pk')),
                    distinct=True
                )
                + Count(
                    'friendships_as_b',
                    filter=Q(friendships_as_b__status='pending') & ~Q(friendships_as_b__initiator_id=F('pk')),
                    distinct=True
                )
            ),
            # Đếm số lượng mối quan hệ bị chặn liên quan đến người dùng
            blocked_count_annotated=(
                Count('friendships_as_a', filter=Q(friendships_as_a__status='blocked'), distinct=True)
                + Count('friendships_as_b', filter=Q(friendships_as_b__status='blocked'), distinct=True)
            )
        )

    def friends_of(self, user: Union['User', UUID]) -> 'UserQuerySet':
        return self.filter(
            Q(friendships_as_a__user_b=user, friendships_as_a__status=Friendship.ACCEPTED) |
            Q(friendships_as_b__user_a=user, friendships_as_b__status=Friendship.ACCEPTED)
        ).distinct()  # Removed bare select_related() — was fetching ALL FK relations
    
    def with_counts(self) -> 'UserQuerySet':
        return self.with_friends_count().with_plans_count().with_groups_count().with_friend_request_counts()
    
    def active(self) -> 'UserQuerySet':
        return self.filter(is_active=True)
    
    def online(self) -> 'UserQuerySet':
        return self.filter(is_online=True)


class UserManager(DjangoUserManager.from_queryset(UserQuerySet)):
    pass


class User(AbstractUser, BaseModel):
    phone_regex = RegexValidator(
        regex=r'^\+?1?\d{9,15}$',
        message="Phone number must have the format: '+999999999'. Maximum 15 numbers."
    )
    
    phone_number = models.CharField(
        validators=[phone_regex], 
        max_length=17, 
        blank=True,
        help_text="Phone number"
    )
    
    avatar = CloudinaryField(
        'image',
        blank=True, 
        null=True,
        folder='planpal/avatars',
        transformation={
            'width': 300,
            'height': 300,
            'crop': 'fill',
            'gravity': 'face',
            'quality': 'auto:good'
        },
        help_text="User avatar"
    )
    

    date_of_birth = models.DateField(
        blank=True, 
        null=True,
        help_text="User's date of birth"
    )
    
    bio = models.TextField(
        max_length=500, 
        blank=True,
        help_text="Introduction (maximum 500 characters)"
    )
    
    
    is_online = models.BooleanField(
        default=False,
        db_index=True, 
        help_text="User's online status"
    )
    
    last_seen = models.DateTimeField(
        default=timezone.now,
        db_index=True,
        help_text="User's last seen time"
    )
    
    
    fcm_token = models.CharField(
        max_length=255, 
        blank=True,
        help_text="Firebase Cloud Messaging token"
    )
    
    # Custom manager combining Django UserManager with our UserQuerySet
    objects = UserManager()

    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_users' 
        indexes = [
            # Kế thừa các indexes từ BaseModel
            *BaseModel.Meta.indexes,
            models.Index(fields=['first_name', 'last_name']),
            models.Index(fields=['is_online', 'last_seen']),
        ]

    def __str__(self) -> str:
        return f"{self.username} ({self.get_full_name()})"

    def update_last_seen(self) -> None:
        self.last_seen = timezone.now()
        self.save(update_fields=['last_seen'])

    def set_online_status(self, status: bool) -> None:
        self.is_online = status
        if not status:
            self.last_seen = timezone.now()
        self.save(update_fields=['is_online', 'last_seen'])

   
        
    @property
    def recent_conversations(self) -> QuerySet:
        from planpals.models import Conversation
        return Conversation.objects.for_user(self).with_last_message().active().order_by('-last_message_at')
        
    @property
    def personal_plans(self) -> QuerySet:
        return self.created_plans.filter(
            plan_type='personal'
        ).select_related().order_by('-created_at')

    @property
    def group_plans(self) -> QuerySet:
        from planpals.models import Plan
        return Plan.objects.filter(
            group__members=self,
            plan_type='group'
        ).select_related('group', 'creator').order_by('-created_at')

    @property
    def all_plans(self) -> QuerySet:
        from planpals.models import Plan
        return Plan.objects.filter(
            Q(creator=self, plan_type='personal') |
            Q(group__members=self, plan_type='group')
        ).select_related('group', 'creator').order_by('-created_at')

    @property
    def viewable_plans(self) -> QuerySet:
        from planpals.models import Plan
        return Plan.objects.filter(
            Q(creator=self) |  # Own plans
            Q(group__members=self) |  # Group plans
            Q(is_public=True)  # Public plans
        ).select_related('group', 'creator').distinct().order_by('-created_at')
    
    @property
    def friends(self) -> UserQuerySet:
        return User.objects.friends_of(self)


    @property
    def plans_count(self) -> int:
        if hasattr(self, 'plans_count_annotated'):
            return self.plans_count_annotated
        return self.all_plans.count()

    @property
    def personal_plans_count(self) -> int:
        if hasattr(self, 'personal_plans_count_annotated'):
            return self.personal_plans_count_annotated
        return self.personal_plans.count()

    @property
    def group_plans_count(self) -> int:
        if hasattr(self, 'group_plans_count_annotated'):
            return self.group_plans_count_annotated
        return self.group_plans.count()

    @property
    def groups_count(self) -> int:
        if hasattr(self, 'groups_count_annotated'):
            return self.groups_count_annotated
        return self.joined_groups.filter(is_active=True).count()

    @property
    def friends_count(self) -> int:
        if hasattr(self, 'friends_count_annotated'):
            return self.friends_count_annotated
        return Friendship.objects.for_user(self).accepted().count()

    @property
    def pending_sent_count(self) -> int:
        if hasattr(self, 'pending_sent_count_annotated'):
            return self.pending_sent_count_annotated
        return Friendship.objects.sent_by(self).count()

    @property
    def pending_received_count(self) -> int:
        if hasattr(self, 'pending_received_count_annotated'):
            return self.pending_received_count_annotated
        return Friendship.objects.pending_for(self).count()

    @property
    def blocked_count(self) -> int:
        if hasattr(self, 'blocked_count_annotated'):
            return self.blocked_count_annotated
        return Friendship.objects.for_user(self).blocked().count()

    @property
    def user_groups(self) -> QuerySet:
        return self.joined_groups
    
    @property
    def online_status(self) -> str:
        if self.is_online:
            return 'online'
        return 'offline'

    @property
    def has_avatar(self) -> bool:
        return bool(self.avatar)

    @property
    def avatar_url(self) -> Optional[str]:
        if not self.has_avatar:
            return None
        if self.avatar:
            cloudinary_image = CloudinaryImage(str(self.avatar))
            return cloudinary_image.build_url(secure=True)
        return None

    @property
    def avatar_thumb(self) -> Optional[str]:
        if not self.avatar:
            return None
        cloudinary_image = CloudinaryImage(str(self.avatar))
        return cloudinary_image.build_url(width=100, height=100, crop='fill', gravity='face', secure=True)

    @property
    def unread_messages_count(self) -> int:
        from planpals.models import Conversation, ChatMessage, MessageReadStatus
        cache_key = f"user_unread_count_{self.id}"
        cached_count = cache.get(cache_key)
        
        if cached_count is not None:
            return cached_count
        
        user_conversations = Conversation.objects.for_user(self).active()
        
        unread_messages = ChatMessage.objects.filter(
            conversation__in=user_conversations,
            is_deleted=False
        ).exclude(
            sender=self
        ).exclude(
            Exists(
                MessageReadStatus.objects.filter(
                    # Trỏ đến ChatMessage hiện tại
                    message=OuterRef('pk'),
                    user=self
                )
            )
        )
        
        count = unread_messages.count()
        
        cache.set(cache_key, count, 30)
        return count
    
    def clear_unread_cache(self) -> None:
        cache_key = f"user_unread_count_{self.id}"
        cache.delete(cache_key)
    
    @classmethod
    def clear_unread_cache_for_users(cls, user_ids: List[UUID]) -> None:
        cache_keys = [f"user_unread_count_{uid}" for uid in user_ids]
        cache.delete_many(cache_keys)
    

class FriendshipQuerySet(models.QuerySet['Friendship']):

    def accepted(self) -> 'FriendshipQuerySet':
        return self.filter(status=self.model.ACCEPTED)
    
    def pending(self) -> 'FriendshipQuerySet':
        return self.filter(status=self.model.PENDING)
    
    def rejected(self) -> 'FriendshipQuerySet':
        return self.filter(status=self.model.REJECTED)
    
    def blocked(self) -> 'FriendshipQuerySet':
        return self.filter(status=self.model.BLOCKED)
    
    
    # Trả về tổng số lượng bản ghi bị xóa và số bản ghi của mỗi user theo django
    def cleanup_old_rejected(self, days: int = 180) -> tuple[int, Dict[str, int]]:
        cutoff = timezone.now() - timezone.timedelta(days=days)
        return self.rejected().exclude(
            rejections__created_at__gte=cutoff
        ).delete()
    
    def for_user(self, user: Union['User', UUID]) -> 'FriendshipQuerySet':
        return self.filter(Q(user_a=user) | Q(user_b=user))

    def friends_of(self, user: Union['User', UUID]) -> 'FriendshipQuerySet':
        return self.accepted().for_user(user)

    def pending_for(self, user: Union['User', UUID]) -> 'FriendshipQuerySet':
        return self.pending().filter(
            Q(user_b=user) | Q(user_a=user)
        ).exclude(initiator=user)

    def sent_by(self, user: Union['User', UUID]) -> 'FriendshipQuerySet':
        return self.pending().filter(initiator=user)

    def between_users(self, user1: Union['User', UUID], user2: Union['User', UUID]) -> 'FriendshipQuerySet':
        user1_id = getattr(user1, 'id', user1)
        user2_id = getattr(user2, 'id', user2)
        
        if user1_id < user2_id:
            return self.filter(user_a_id=user1_id, user_b_id=user2_id)
        else:
            return self.filter(user_a_id=user2_id, user_b_id=user1_id)

    
class FriendshipRejection(BaseModel):

    friendship = models.ForeignKey(
        'Friendship',
        on_delete=models.CASCADE,
        related_name='rejections',
        help_text="Friendship record being rejected"
    )
    
    rejected_by = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='performed_rejections',
        help_text="User who performed the rejection"
    )

    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_friendship_rejections'
        
        indexes = [
            *BaseModel.Meta.indexes,
            models.Index(fields=['friendship', 'created_at']),
            models.Index(fields=['rejected_by', 'created_at']),
            models.Index(fields=['friendship', 'rejected_by']),
        ]
        
        ordering = ['-created_at']

    def clean(self) -> None:
        super().clean()
        
        if self.friendship and self.rejected_by:
            if self.rejected_by_id not in [self.friendship.user_a_id, self.friendship.user_b_id]:
                raise ValidationError("Only friendship participants can reject the request")

            if self.rejected_by_id == self.friendship.initiator_id:
                raise ValidationError("The initiator cannot reject their own request")
            
            if self.friendship.status != Friendship.PENDING:
                raise ValidationError("Can only reject pending friendship requests")

    def __str__(self) -> str:
        return f"Rejection: {self.friendship} by {self.rejected_by.username} at {self.created_at}"


class Friendship(BaseModel):    
    PENDING = 'pending'
    ACCEPTED = 'accepted'
    REJECTED = 'rejected'
    BLOCKED = 'blocked'
    
    
    REJECTION_COOLDOWN_HOURS = 24  # Hours before can resend after rejection
    MAX_REJECTION_COUNT = 3  # Max rejections before longer cooldown
    EXTENDED_COOLDOWN_DAYS = 7  # Extended cooldown after max rejections
    
    STATUS_CHOICES = [
        (PENDING, 'Đang chờ'),
        (ACCEPTED, 'Đã chấp nhận'),
        (REJECTED, 'Đã từ chối'),
        (BLOCKED, 'Đã chặn'),
    ]
    
    user_a = models.ForeignKey(
        User,
        null=True,
        on_delete=models.CASCADE,
        related_name='friendships_as_a',
        help_text="User with smaller UUID (canonical ordering)"
    )
    
    user_b = models.ForeignKey(
        User,
        null=True,
        on_delete=models.CASCADE,
        related_name='friendships_as_b', 
        help_text="User with larger UUID (canonical ordering)"
    )
    
    initiator = models.ForeignKey(
        User,
        null=True,
        on_delete=models.CASCADE,
        related_name='initiated_friendships',
        help_text="User who initiated this friendship request"
    )
    
    status = models.CharField(
        max_length=20,
        choices=STATUS_CHOICES,
        default=PENDING,
        db_index=True,
        help_text="Current status of friendship"
    )
    
    
    objects = FriendshipQuerySet.as_manager()

    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_friendships'

        # Ràng buộc ở DB-level
        constraints = [
            models.UniqueConstraint(
                fields=['user_a', 'user_b'],
                name='unique_canonical_friendship'
            ),
            models.CheckConstraint(
                condition=Q(user_a__isnull=False) & Q(user_b__isnull=False),
                name='both_users_must_exist'
            ),
            models.CheckConstraint(
                condition=~Q(user_a=F('user_b')),
                name='no_self_friendship'
            ),
        ]
        
        indexes = [
            *BaseModel.Meta.indexes,
            models.Index(fields=['user_a', 'status']),
            models.Index(fields=['user_b', 'status']),
            models.Index(fields=['initiator', 'status']),
            models.Index(fields=['status', 'created_at']),
            models.Index(fields=['user_a', 'user_b', 'status']),
        ]

    def __str__(self) -> str:
        if not (self.user_a and self.user_b and self.initiator):
            return f"Friendship({self.id}) - Incomplete"
        direction = "→" if self.initiator == self.user_a else "←"
        return f"{self.user_a.username} {direction} {self.user_b.username} ({self.get_status_display()})"

    def clean(self) -> None:
        super().clean()
        
        # Model-level validations
        if self.user_a_id and self.user_b_id:
            if self.user_a_id == self.user_b_id:
                raise ValidationError("Cannot create friendship with yourself")
        
        if self.initiator_id and self.user_a_id and self.user_b_id:
            if self.initiator_id not in [self.user_a_id, self.user_b_id]:
                raise ValidationError("Initiator must be one of the friendship participants")

    def save(self, *args: Any, **kwargs: Any) -> None:
        if self.user_a_id and self.user_b_id:
            if self.user_a_id > self.user_b_id:
                self.user_a_id, self.user_b_id = self.user_b_id, self.user_a_id
        
        self.clean()
        super().save(*args, **kwargs)

    # === Instance Methods ===
    
    def get_other_user(self, user : Union['User', UUID]) -> 'User':
        user_id = getattr(user, 'id', user)
        if user_id == self.user_a_id:
            return self.user_b
        elif user_id == self.user_b_id:
            return self.user_a
        else:
            raise ValueError("User is not a participant in this friendship")
    
    def get_receiver(self) -> 'User':
        return self.user_b if self.initiator == self.user_a else self.user_a

    def is_initiated_by(self, user : Union['User', UUID]) -> bool:
        user_id = getattr(user, 'id', user)
        return self.initiator_id == user_id

    def can_be_accepted_by(self, user : Union['User', UUID]) -> bool:
        return (
            self.status == self.PENDING and 
            not self.is_initiated_by(user) and
            user in [self.user_a, self.user_b]
        )
    
    def get_rejection_count(self) -> int:
        return self.rejections.count()

    def get_recent_rejection_count(self, days: int = 30) -> int:
        cutoff = timezone.now() - timedelta(days=days)
        return self.rejections.filter(created_at__gte=cutoff).count()
    
    def get_last_rejection(self) -> Optional['FriendshipRejection']:
        return self.rejections.first()  # Already ordered by -created_at

    def was_rejected_by(self, user : Union['User', UUID]) -> bool:
        return self.rejections.filter(rejected_by=user).exists()
    

    @classmethod
    def get_friendship_status(cls, user1 : Union['User', UUID], user2 : Union['User', UUID]) -> Optional[str]:
        friendship = cls.objects.between_users(user1, user2).first()
        return friendship.status if friendship else None
    
    # === Query Methods - Keep in Model ===
    @classmethod
    def are_friends(cls, user1 : Union['User', UUID], user2 : Union['User', UUID]) -> bool:
        return cls.objects.between_users(user1, user2).accepted().exists()
    
    @classmethod
    def is_blocked(cls, user1 : Union['User', UUID], user2 : Union['User', UUID]) -> bool:
        return cls.objects.between_users(user1, user2).blocked().exists()

    @classmethod
    def get_pending_requests(cls, user : Union['User', UUID]) -> 'FriendshipQuerySet':
        return cls.objects.pending_for(user).select_related(
            'initiator', 'user_a', 'user_b'
        ).order_by('-created_at')

    @classmethod
    def get_sent_requests(cls, user : Union['User', UUID]) -> 'FriendshipQuerySet':
        return cls.objects.sent_by(user).select_related(
            'user_a', 'user_b'
        ).order_by('-created_at')


    @classmethod
    def get_friendship(cls, user1 : Union['User', UUID], user2 : Union['User', UUID]) -> Optional['Friendship']:
        return cls.objects.between_users(user1, user2).select_related(
            'user_a', 'user_b', 'initiator'
        ).first()

    @classmethod
    def cleanup_old_rejected_friendships(cls, days: int = 180) -> Tuple[int, Dict[str, int]]:
        return cls.objects.cleanup_old_rejected(days)
