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


class BaseModel(models.Model):
    
    id = models.UUIDField(
        primary_key=True,
        default=uuid4,
        editable=False,
        help_text="Unique identifier"
    )
    
    created_at = models.DateTimeField(
        auto_now_add=True,
        db_index=True,
        help_text="Creation time"
    )
    
    updated_at = models.DateTimeField(
        auto_now=True,
        help_text="Last updated time"
    )
    
    is_active = models.BooleanField(
        default=True,
        db_index=True,
        help_text="Active status"
    )

    class Meta:
        abstract = True  # Không tạo table riêng
        ordering = ['-created_at']
        
        indexes = [
            models.Index(fields=['created_at']),
            models.Index(fields=['updated_at']),
        ]

    def save(self, *args: Any, **kwargs: Any) -> None:
        self.full_clean()  # Chạy tất cả validations
        super().save(*args, **kwargs)

    def __str__(self) -> str:
        return f"{self.__class__.__name__}({self.id})"


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
        ).select_related().distinct()
    
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
    def recent_conversations(self) -> QuerySet['Conversation']:
        return Conversation.objects.for_user(self).with_last_message().active().order_by('-last_message_at')
        
    @property
    def personal_plans(self) -> QuerySet['Plan']:
        return self.created_plans.filter(
            plan_type='personal'
        ).select_related().order_by('-created_at')

    @property
    def group_plans(self) -> QuerySet['Plan']:
        return Plan.objects.filter(
            group__members=self,
            plan_type='group'
        ).select_related('group', 'creator').order_by('-created_at')

    @property
    def all_plans(self) -> QuerySet['Plan']:
        return Plan.objects.filter(
            Q(creator=self, plan_type='personal') |
            Q(group__members=self, plan_type='group')
        ).select_related('group', 'creator').order_by('-created_at')

    @property
    def viewable_plans(self) -> QuerySet['Plan']:
        return Plan.objects.filter(
            Q(creator=self) |  # Own plans
            Q(group__members=self) |  # Group plans
            Q(is_public=True)  # Public plans
        ).select_related('group', 'creator').distinct().order_by('-created_at')
    
    @property
    def friends(self) -> UserQuerySet:
        return self.objects.friends_of(self)


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
    def user_groups(self) -> QuerySet['Group']:
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
    
    

class GroupQuerySet(models.QuerySet['Group']):
    
    def with_member_count(self) -> 'GroupQuerySet':
        return self.annotate(
            admin_count_annotated=Count(
                'memberships',
                distinct=True
            )
        )
    
    def with_admin_count(self) -> 'GroupQuerySet':
        return self.annotate(
            admin_count_annotated=Count(
                'memberships', 
                filter=Q(memberships__role=GroupMembership.ADMIN),
                distinct=True
            )
        )
    
    def with_plans_count(self) -> 'GroupQuerySet':
        return self.annotate(
            plans_count_annotated=Count('plans', distinct=True),
            active_plans_count_annotated=Count(
                'plans',
                filter=~Q(plans__status__in=['cancelled', 'completed']),
                distinct=True
            )
        )
    
    def with_full_stats(self) -> 'GroupQuerySet':
        return self.with_member_count().with_admin_count().with_plans_count()
    
    def active(self) -> 'GroupQuerySet':
        return self.filter(is_active=True)
    
    def for_user(self, user: Union['User', UUID]) -> 'GroupQuerySet':
        return self.filter(members=user)
    
    def administered_by(self, user: Union['User', UUID]) -> 'GroupQuerySet':
        return self.filter(
            memberships__user=user,
            memberships__role=GroupMembership.ADMIN
        )


class Group(BaseModel):

    name = models.CharField(
        max_length=100,
        help_text="Group name"
    )
    
    description = models.TextField(
        blank=True,
        help_text="Group description"
    )
    
    avatar = CloudinaryField(
        'image',
        blank=True, 
        null=True,
        folder='planpal/groups/avatars',
        transformation={
            'width': 300,
            'height': 300,
            'crop': 'fill',
            'gravity': 'face',
            'quality': 'auto:good'
        },
        help_text="Group avatar"
    )
    
    cover_image = CloudinaryField(
        'image',
        blank=True, 
        null=True,
        folder='planpal/groups/covers',
        transformation={
            'width': 1200,
            'height': 400,
            'crop': 'fill',
            'gravity': 'center',
            'quality': 'auto:good'
        },
        help_text="Group cover image"
    )

    
    admin = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='administered_groups',
        help_text="Group admin"
    )
    
    members = models.ManyToManyField(
        User,
        through='GroupMembership',
        related_name='joined_groups',
        help_text="Group members"
    )
    
    objects = GroupQuerySet.as_manager()

    class Meta:
        db_table = 'planpal_groups'
        
        indexes = [
            *BaseModel.Meta.indexes,
            models.Index(fields=['admin', 'is_active']),
            models.Index(fields=['is_active', 'created_at']),
        ]

    def __str__(self) -> str:
        return f"{self.name} (Admin: {self.admin.username})"

    def save(self, *args: Any, **kwargs: Any) -> None:
        # Cờ kiểm tra nếu là nhóm mới
        is_new = self._state.adding
        
        super().save(*args, **kwargs)
        
        if is_new and self.admin:
            GroupMembership.objects.get_or_create(
                group=self,
                user=self.admin,
                defaults={'role': GroupMembership.ADMIN}
            )
            
            # Create group conversation - avoid circular import by using direct model approach
            try:
                self.conversation
            except Conversation.DoesNotExist:
                Conversation.objects.create(
                    conversation_type='group',
                    group=self
                )

    @property
    def has_avatar(self) -> bool: 
        return bool(self.avatar)

    @property
    def avatar_url(self) -> Optional[str]:
        if not self.avatar:
            return None
        cloudinary_image = CloudinaryImage(str(self.avatar))
        return cloudinary_image.build_url(width=300, height=300, crop='fill', gravity='face', secure=True)

    @property
    def avatar_thumb(self) -> Optional[str]:
        if not self.avatar:
            return None
        cloudinary_image = CloudinaryImage(str(self.avatar))
        return cloudinary_image.build_url(width=100, height=100, crop='fill', gravity='face', secure=True)

    @property
    def has_cover_image(self) -> bool:
        return bool(self.cover_image)

    @property
    def cover_image_url(self) -> Optional[str]:
        if not self.cover_image:
            return None
        cloudinary_image = CloudinaryImage(str(self.cover_image))
        return cloudinary_image.build_url(width=1200, height=600, crop='fill', gravity='center', secure=True)

    @property
    def member_count(self) -> int:
        if hasattr(self, 'member_count_annotated'):
            return self.member_count_annotated
        return self.memberships.count()

    @property
    def admin_count(self) -> int:
        if hasattr(self, 'admin_count_annotated'):
            return self.admin_count_annotated
        return self.get_admin_count()

    @property
    def plans_count(self) -> int:
        if hasattr(self, 'plans_count_annotated'):
            return self.plans_count_annotated
        return self.plans.count()

    @property
    def active_plans_count(self) -> int:
        if hasattr(self, 'active_plans_count_annotated'):
            return self.active_plans_count_annotated
        return self.plans.exclude(status__in=['cancelled', 'completed']).count()
    


    def is_member(self, user: Union['User', UUID]) -> bool:
        return GroupMembership.objects.filter(
            group=self,
            user=user
        ).exists()

    def is_admin(self, user: Union['User', UUID]) -> bool:
        return GroupMembership.objects.filter(
            group=self,
            user=user,
            role=GroupMembership.ADMIN
        ).exists()

    def get_admins(self) -> QuerySet['User']:
        return User.objects.filter(
            groupmembership__group=self,
            groupmembership__role=GroupMembership.ADMIN
        )
    
    def get_admin_count(self) -> int:
        if hasattr(self, 'admin_count_annotated'):
            return self.admin_count_annotated
        
        return GroupMembership.objects.filter(
            group=self,
            role=GroupMembership.ADMIN
        ).count()


    def get_user_membership(self, user: Union[UUID, 'User']) -> Optional['GroupMembership']:
        try:
            return GroupMembership.objects.select_related('user').get(
                group=self,
                user=user
            )
        except GroupMembership.DoesNotExist:
            return None
    
    def get_user_role(self, user: Union[UUID, 'User']) -> Optional[str]:
        """Get the role of a user in this group"""
        membership = self.get_user_membership(user)
        return membership.role if membership else None
    


    def get_member_roles(self) -> Dict[UUID, str]:
        return dict(
            GroupMembership.objects.filter(group=self)
            .values_list('user_id', 'role')
        )

    def get_recent_messages(self, limit: int = 50) -> QuerySet['ChatMessage']:
        return self.messages.active().select_related('sender').order_by('-created_at')


class GroupMembershipQuerySet(models.QuerySet['GroupMembership']):
    def admins(self) -> 'GroupMembershipQuerySet':
        return self.filter(role=GroupMembership.ADMIN)
    
    def members(self) -> 'GroupMembershipQuerySet':
        return self.filter(role=GroupMembership.MEMBER)
    
    def for_group(self, group: Union['Group', int]) -> 'GroupMembershipQuerySet':
        return self.filter(group=group)
    
    def for_user(self, user: Union['User', UUID]) -> 'GroupMembershipQuerySet':
        return self.filter(user=user)


class GroupMembership(BaseModel):
    ADMIN = 'admin'
    MEMBER = 'member'
    
    ROLE_CHOICES = [
        (ADMIN, 'Quản trị viên'),
        (MEMBER, 'Thành viên'),
    ]
    
    
    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        help_text="Member user"
    )
    
    group = models.ForeignKey(
        Group,
        on_delete=models.CASCADE,
        related_name='memberships',
        help_text="Group"
    )
    
    role = models.CharField(
        max_length=20,
        choices=ROLE_CHOICES,
        default=MEMBER,
        db_index=True,
        help_text="Role"
    )
    
    objects = GroupMembershipQuerySet.as_manager()

    class Meta:
        db_table = 'planpal_group_memberships'
        # Đảm bảo user chỉ có 1 membership trong 1 group
        unique_together = ('user', 'group')
        
        indexes = [
            *BaseModel.Meta.indexes,
            # Index cho query members của group
            models.Index(fields=['group', 'role']),
            # Index cho query groups của user
            models.Index(fields=['user', 'role']),
        ]
        

    def __str__(self) -> str:
        return f"{self.user.username} in {self.group.name} ({self.get_role_display()})"

    def clean(self) -> None:
        super().clean()
        
        if self.pk and self.role == self.MEMBER:
            admin_count = GroupMembership.objects.filter(
                group=self.group,
                role=self.ADMIN
            ).exclude(pk=self.pk).count()
            
            if admin_count == 0:
                raise ValidationError("Group must have at least one admin")

    def save(self, *args: Any, **kwargs: Any) -> None:
        if self.pk and self.role == self.MEMBER:
            admin_count = GroupMembership.objects.filter(
                group=self.group,
                role=self.ADMIN
            ).exclude(pk=self.pk).count()
            
            if admin_count == 0:
                raise ValueError("Group must have at least one admin")

        self.clean()
        super().save(*args, **kwargs)



class PlanQuerySet(models.QuerySet['Plan']):
    
    def personal(self) -> 'PlanQuerySet':
        return self.filter(plan_type='personal')
    
    def group_plans(self) -> 'PlanQuerySet':
        return self.filter(plan_type='group')
    
    def public(self) -> 'PlanQuerySet':
        return self.filter(is_public=True)
    
    def upcoming(self) -> 'PlanQuerySet':
        return self.filter(status='upcoming')
    
    def ongoing(self) -> 'PlanQuerySet':
        return self.filter(status='ongoing')
    
    def completed(self) -> 'PlanQuerySet':
        return self.filter(status='completed')
    
    def active(self) -> 'PlanQuerySet':
        return self.exclude(status__in=['cancelled', 'completed'])
    
    def for_user(self, user: Union['User', UUID]) -> 'PlanQuerySet':
        return self.filter(
            Q(creator=user) |  # Own plans
            Q(group__members=user) |  # Group plans
            Q(is_public=True)  # Public plans
        ).distinct()
    
    def with_activity_count(self) -> 'PlanQuerySet':
        return self.annotate(
            activity_count_annotated=Count('activities', distinct=True)
        )
    
    def with_total_cost(self) -> 'PlanQuerySet':
        return self.annotate(
            total_cost_annotated=Sum('activities__estimated_cost')
        )
    
    def with_stats(self) -> 'PlanQuerySet':
        return self.with_activity_count().with_total_cost()
    
    def in_date_range(self, start_date: Optional[datetime] = None, end_date: Optional[datetime] = None) -> 'PlanQuerySet':
        queryset = self
        if start_date:
            queryset = queryset.filter(start_date__gte=start_date)
        if end_date:
            queryset = queryset.filter(end_date__lte=end_date)
        return queryset
    
    def plans_need_status_update(self) -> 'PlanQuerySet':
        now = timezone.now()
        return self.filter(
            Q(
                status='upcoming',
                start_date__lte=now
            ) | Q(
                status='ongoing',
                end_date__lt=now
            )
        )
    
class Plan(BaseModel):
    title = models.CharField(
        max_length=200,
        help_text="Title of the plan"
    )
    
    description = models.TextField(
        blank=True,
        help_text="Detailed description of the plan"
    )
    
    group = models.ForeignKey(
        Group,
        on_delete=models.CASCADE,
        related_name='plans',
        blank=True,
        null=True,
        help_text="Group associated with the plan (null for personal plans)"
    )
    
    creator = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='created_plans',
        help_text="Creator/owner of the plan"
    )
    
    PLAN_TYPES = [
        ('personal', 'Cá nhân'),
        ('group', 'Nhóm'),
    ]
    
    plan_type = models.CharField(
        max_length=20,
        choices=PLAN_TYPES,
        default='personal',
        db_index=True,
        help_text="Type of plan: personal or group"
    )
    
    start_date = models.DateTimeField(
        help_text="Start date of the trip"
    )
    
    end_date = models.DateTimeField(
        help_text="End date of the trip"
    )
    
    # Trạng thái công khai
    is_public = models.BooleanField(
        default=False,
        db_index=True,
        help_text="Is the plan public?"
    )
    
    STATUS_CHOICES = [
        ('upcoming', 'Sắp bắt đầu'),
        ('ongoing', 'Đang diễn ra'),
        ('completed', 'Đã hoàn thành'),
        ('cancelled', 'Đã hủy'),
    ]
    
    status = models.CharField(
        max_length=20,
        choices=STATUS_CHOICES,
        default='upcoming',
        db_index=True,
        help_text="Current status of the plan"
    )

    scheduled_start_task_id = models.CharField(
        max_length=255,
        null=True,
        blank=True,
        help_text="Celery task id scheduled to start this plan"
    )

    scheduled_end_task_id = models.CharField(
        max_length=255,
        null=True,
        blank=True,
        help_text="Celery task id scheduled to complete this plan"
    )
    
    objects = PlanQuerySet.as_manager()

    class Meta:
        db_table = 'planpal_plans'
        
        indexes = [
            *BaseModel.Meta.indexes,
            models.Index(fields=['creator', 'plan_type', 'status']),
            models.Index(fields=['group', 'status']),
            models.Index(fields=['start_date', 'end_date']),
            models.Index(fields=['is_public', 'plan_type', 'status']),
        ]

    def __str__(self) -> str:
        if self.is_personal():
            return f"{self.title} (Personal - {self.creator.username})"
        return f"{self.title} ({self.group.name})"

    def clean(self) -> None:   
        # Validate date
        if self.start_date and self.end_date:
            if self.end_date <= self.start_date:
                raise ValidationError("End date must be after start date")

        # Validate plan type consistency
        if self.plan_type == 'personal' and self.group is not None:
            raise ValidationError("Personal plan cannot have a group")

        if self.plan_type == 'group' and self.group is None:
            raise ValidationError("Group plan must have a group")

    def _auto_status(self) -> bool:
        if not (self.start_date and self.end_date):
            return False
            
        now = timezone.now()
        original_status = self.status
        
        if self.status == 'upcoming' and now >= self.start_date:
            self.status = 'ongoing'
            
        elif self.status == 'ongoing' and now > self.end_date:
            self.status = 'completed'
        
        return self.status != original_status

    def save(self, *args: Any, **kwargs: Any) -> None:
        self.plan_type = 'personal' if self.group is None else 'group'
        status_changed = self._auto_status()
        # True khi chưa được lưu vào DB, kiểm tra xem đang xử lý plan mới hay cập nhật plan cũ
        is_new = self._state.adding
        
        dates_changed = False
        if not is_new and self.pk:
            update_fields = kwargs.get('update_fields', None)
            if update_fields is None or 'start_date' in update_fields or 'end_date' in update_fields:
                try:
                    old_plan = Plan.objects.only('start_date', 'end_date').get(pk=self.pk)
                    dates_changed = (
                        old_plan.start_date != self.start_date or 
                        old_plan.end_date != self.end_date
                    )
                except Plan.DoesNotExist:
                    is_new = True
                    dates_changed = False
        
        self.clean()
        super().save(*args, **kwargs)
        
        if is_new or dates_changed:
            if self.status == 'upcoming':
                try:
                    self.schedule_celery_tasks()
                except Exception:
                    pass
        
        if status_changed:
            pass  # Could add logging/notifications here

    def is_personal(self) -> bool:
        return self.plan_type == 'personal'

    def is_group_plan(self) -> bool:
        return self.plan_type == 'group'


    @property
    def collaborators(self) -> List['User']:
        if self.is_personal():
            return [self.creator]
        elif self.is_group_plan() and self.group:
            return list(self.group.members.all())
        return []

    
    @property
    def duration_days(self) -> int:
        if self.start_date and self.end_date:
            return (self.end_date.date() - self.start_date.date()).days + 1
        return 0

    @property
    def activities_count(self) -> int:
        if hasattr(self, 'activity_count_annotated'):
            return self.activity_count_annotated
        return self.activities.count()

    @property
    def total_estimated_cost(self) -> Decimal:
        if hasattr(self, 'total_cost_annotated'):
            return self.total_cost_annotated or Decimal('0')
        
        result = self.activities.aggregate(
            total=Sum('estimated_cost')
        )['total']
        return result or Decimal('0')

    def get_members(self) -> QuerySet['User']:
        if self.is_personal():
            return User.objects.filter(id=self.creator_id).select_related()
        if self.group_id:
            return self.group.members.select_related()
        return User.objects.none()


    @property
    def activities_by_date(self) -> Dict[date, List['PlanActivity']]:
        activities = self.activities.order_by('start_time').select_related()
        result = defaultdict(list)
        
        for activity in activities:
            date_key = activity.start_time.date()
            result[date_key].append(activity)
        
        return dict(result)

    def get_activities_by_date(self, date: date) -> QuerySet['PlanActivity']:
        return self.activities.filter(
            start_time__date=date
        ).order_by('start_time')

    def check_activity_overlap(self, start_time: datetime, end_time: datetime, exclude_id: Optional[str] = None) -> Optional['PlanActivity']:
        queryset = self.activities.filter(
            start_time__lt=end_time,
            end_time__gt=start_time
        )
        
        if exclude_id:
            queryset = queryset.exclude(id=exclude_id)
            
        return queryset.first()

    def has_time_conflict(self, start_time: datetime, end_time: datetime, exclude_activity: Optional['PlanActivity'] = None) -> bool:
        queryset = self.activities.filter(
            start_time__lt=end_time,
            end_time__gt=start_time 
        )
        
        if exclude_activity:
            queryset = queryset.exclude(id=exclude_activity.id)
            
        return queryset.exists()

    # @transaction.atomic
    # def reorder_activities(self, activity_id_order_pairs: List[Tuple[str, int]], date: Optional[date] = None) -> None:
    #     # Lock plan để prevent concurrent reordering
    #     plan = Plan.objects.select_for_update().get(pk=self.pk)
        
    #     if plan.status in ['cancelled', 'completed']:
    #         raise ValueError("Activities of completed/cancelled plans cannot be reordered")
        
    #     # Validate all activities belong to this plan
    #     activity_ids = [aid for aid, _ in activity_id_order_pairs]
    #     activities_qs = plan.activities.filter(id__in=activity_ids)
        
    #     if date:
    #         activities_qs = activities_qs.filter(start_time__date=date)
        
    #     if activities_qs.count() != len(activity_ids):
    #         raise ValueError("Một số activities không tồn tại hoặc không thuộc plan này")
        
    #     # Lock activities để prevent concurrent edits
    #     activities = list(activities_qs.select_for_update())
    #     activity_dict = {act.id: act for act in activities}
        
    #     # Validate orders không duplicate
    #     orders = [order for _, order in activity_id_order_pairs]
    #     if len(set(orders)) != len(orders):
    #         raise ValueError("Các order values không được trùng lặp")
        
    #     # Bulk update với optimized queries
    #     updates = []
    #     for activity_id, new_order in activity_id_order_pairs:
    #         activity = activity_dict[activity_id]
    #         if activity.order != new_order:
    #             activity.order = new_order
    #             updates.append(activity)
        
    #     if updates:
    #         PlanActivity.objects.bulk_update(updates, ['order', 'updated_at'])
            
    #         # Touch plan updated_at
    #         plan.save(update_fields=['updated_at'])
        
    #     return len(updates)

class PlanActivity(BaseModel):    
    # Các loại hoạt động cụ thể hơn
    ACTIVITY_TYPES = [
        ('eating', 'Ăn uống'),
        ('resting', 'Nghỉ ngơi'),
        ('moving', 'Di chuyển'),
        ('sightseeing', 'Tham quan'),
        ('shopping', 'Mua sắm'),
        ('entertainment', 'Giải trí'),
        ('event', 'Sự kiện'),
        ('sport', 'Thể thao'),
        ('study', 'Học tập'),
        ('work', 'Công việc'),
        ('other', 'Khác'),
    ]
    
    # Remove id field vì đã có trong BaseModel
    
    # Thuộc về plan nào
    plan = models.ForeignKey(
        Plan,
        on_delete=models.CASCADE,
        related_name='activities',
        help_text="Plan of this activity"
    )
    
    # Thông tin cơ bản
    title = models.CharField(
        max_length=200,
        help_text="Activity name"
    )
    
    description = models.TextField(
        blank=True,
        help_text="Activity description"
    )
    
    # Loại hoạt động
    activity_type = models.CharField(
        max_length=20,
        choices=ACTIVITY_TYPES,
        default='other',
        db_index=True,
        help_text="Activity type"
    )
    
    # Thời gian
    start_time = models.DateTimeField(
        help_text="Start time of the activity"
    )
    
    end_time = models.DateTimeField(
        help_text="End time of the activity"
    )
    
    # Thông tin địa điểm
    location_name = models.CharField(
        max_length=200,
        blank=True,
        help_text="Name of the location"
    )
    
    location_address = models.TextField(
        blank=True,
        help_text="Detailed address"
    )
    
    # Tọa độ GPS
    latitude = models.DecimalField(
        max_digits=9,   # Tổng 9 chữ số
        decimal_places=6,  # 6 chữ số thập phân (độ chính xác ~10cm)
        blank=True, 
        null=True,
        help_text="Latitude"
    )
    
    longitude = models.DecimalField(
        max_digits=9,
        decimal_places=6,
        blank=True, 
        null=True,
        help_text="Longitude"
    )
    
    goong_place_id = models.CharField(
        max_length=200,
        blank=True,
        help_text="Goong Map API place ID"
    )
    
    # Chi phí dự kiến
    estimated_cost = models.DecimalField(
        max_digits=10,
        decimal_places=2,
        blank=True, 
        null=True,
        help_text="Estimated cost (VND)"
    )
    
    # Ghi chú
    notes = models.TextField(
        blank=True,
        help_text="Additional notes"
    )
    
    # Thứ tự trong ngày
    order = models.PositiveIntegerField(
        default=0,
        help_text="Order of activity in the day"
    )
    
    # Trạng thái hoàn thành
    is_completed = models.BooleanField(
        default=False,
        help_text="Has the activity been completed?"
    )
    
    # Version field cho optimistic locking
    version = models.PositiveIntegerField(
        default=1,
        help_text="Version cho conflict detection"
    )
    
    class Meta:
        db_table = 'planpal_plan_activities'
        ordering = ['start_time']  # Đơn giản, chỉ theo thời gian
        
        indexes = [
            *BaseModel.Meta.indexes,
            # Index cho query activities của plan
            models.Index(fields=['plan', 'start_time']),
            # Index cho query theo loại hoạt động
            models.Index(fields=['activity_type', 'start_time']),
            # Index cho time conflict detection
            models.Index(fields=['plan', 'start_time', 'end_time']),
        ]

    def __str__(self) -> str:
        return f"{self.plan.title} - {self.title} ({self.start_time.strftime('%H:%M')})"

    def clean(self) -> None:
        super().clean()
        self._validate_time_bounds()
        self._validate_within_plan_timeline()
        self._validate_coordinates()
        self._validate_estimated_cost()

    def _validate_time_bounds(self) -> None:
        if self.start_time and self.end_time:
            if self.end_time <= self.start_time:
                raise ValidationError("End time must be after start time")

            duration = self.end_time - self.start_time
            if duration.total_seconds() > 24 * 3600:
                raise ValidationError("Activity duration must not exceed 24 hours")

    def _validate_within_plan_timeline(self) -> None:
        if self.plan_id and self.start_time and self.end_time:
            plan = self.plan
            if self.start_time.date() < plan.start_date.date():
                raise ValidationError("Activity cannot start before plan start date")
            if self.end_time.date() > plan.end_date.date():
                raise ValidationError("Activity cannot end after plan end date")

    def _validate_coordinates(self) -> None:
        if self.latitude is not None and not (-90 <= self.latitude <= 90):
            raise ValidationError("Latitude must be between -90 and 90")

        if self.longitude is not None and not (-180 <= self.longitude <= 180):
            raise ValidationError("Longitude must be between -180 and 180")

    def _validate_estimated_cost(self) -> None:
        if self.estimated_cost is not None and self.estimated_cost < 0:
            raise ValidationError("Estimated cost must be non-negative")

    def save(self, *args: Any, **kwargs: Any) -> None:        
        # Run clean validation before any save logic
        self.clean()
        
        # For updates only, use F() expression for version increment  
        is_creating = self._state.adding
        if not is_creating:  # This is an update
            self.version = F('version') + 1
        # For creates, version defaults to 1 from field definition
        
        # Call Model.save() directly, skip BaseModel.save() to avoid double full_clean()
        super(BaseModel, self).save(*args, **kwargs)
        
        # Refresh version field after update
        if not is_creating:
            self.refresh_from_db(fields=['version'])

    def check_time_conflict(self, exclude_self: bool = True) -> QuerySet['PlanActivity']:
        conflicts = self.plan.activities.filter(
            start_time__lt=self.end_time,
            end_time__gt=self.start_time
        )
        
        if exclude_self and self.pk:
            conflicts = conflicts.exclude(pk=self.pk)
        
        return conflicts

    @property
    def duration_hours(self) -> int:
        if self.start_time and self.end_time:
            return int((self.end_time - self.start_time).total_seconds() / 60)
        return 0

    @property
    def is_today(self) -> bool:
        if self.start_time:
            return self.start_time.date() == timezone.now().date()
        return False

    @property
    def can_complete(self) -> bool:
        return self.start_time <= timezone.now() if self.start_time else False

    @property
    def has_location(self) -> bool:
        if self.latitude is not None and self.longitude is not None:
            return True
        if self.goong_place_id:
            return bool(str(self.goong_place_id).strip())
        if self.location_name:
            return bool(str(self.location_name).strip())
        return False


class ConversationQuerySet(models.QuerySet['Conversation']):    
    def active(self) -> 'ConversationQuerySet':
        return self.filter(is_active=True)
    
    def for_user(self, user: Union['User', UUID]) -> 'ConversationQuerySet':
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
            last_message_time=Subquery(last_message_subquery.values('created_at')[:1]),
            last_message_content=Subquery(last_message_subquery.values('content')[:1]),
            last_message_sender_id=Subquery(last_message_subquery.values('sender_id')[:1])
        ).select_related('group')

    def get_direct_conversation(self, user1: Union['User', UUID], user2: Union['User', UUID]) -> Optional['Conversation']:
        user1_id = getattr(user1, 'id', user1)
        user2_id = getattr(user2, 'id', user2)
        
        # Canonical ordering
        if user1_id < user2_id:
            return self.filter(
                conversation_type='direct',
                user_a=user1_id,
                user_b=user2_id
            ).first()
        else:
            return self.filter(
                conversation_type='direct',
                user_a=user2_id,
                user_b=user1_id
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
        Group,
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name='conversation',
        help_text="Group (only for group conversations)"
    )
    
    user_a = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name='direct_conversations_as_a',
        help_text="First participant in direct conversation (smaller UUID)"
    )
    
    user_b = models.ForeignKey(
        User,
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
            models.Index(fields=['user_a', 'user_b']),    # Direct conversations
            models.Index(fields=['last_message_at']),
            models.Index(fields=['is_active', 'last_message_at']),
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
    def participants(self) -> QuerySet[User]:
        if self.conversation_type == 'group' and self.group:
            return self.group.members.all()
        elif self.conversation_type == 'direct' and self.user_a and self.user_b:
            return User.objects.filter(id__in=[self.user_a_id, self.user_b_id])
        return User.objects.none()

    
    def get_avatar_url(self, current_user: Optional['User'] = None) -> Optional[str]:
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

    

    def get_other_participant(self, user: 'User') -> Optional['User']:
        if self.conversation_type != 'direct':
            return None
        return self.user_b if self.user_a_id == user.id else self.user_a

    def is_participant(self, user: 'User') -> bool:
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
    
    def for_conversation(self, conversation: Union['Conversation', int]) -> 'ChatMessageQuerySet':
        return self.filter(conversation=conversation)
    
    def for_group(self, group: Union['Group', int]) -> 'ChatMessageQuerySet':
        return self.filter(group=group)
    
    def for_user(self, user: Union['User', int]) -> 'ChatMessageQuerySet':
        return self.filter(sender=user)
    
    def by_user(self, user: Union['User', int]) -> 'ChatMessageQuerySet':
        return self.filter(sender=user)
    
    def recent(self, limit: int = 50) -> 'ChatMessageQuerySet':
        return self.order_by('-created_at')[:limit]
    
    def with_read_status(self, user: Union['User', int]) -> 'ChatMessageQuerySet':
        return self.annotate(
            is_read_by_user=Exists(
                MessageReadStatus.objects.filter(
                    message=OuterRef('pk'),
                    user=user
                )
            )
        )
    
    def unread_for_user(self, user: Union['User', int]) -> 'ChatMessageQuerySet':
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
        User,
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
        help_text="Message content"
    )
    
    attachment = CloudinaryField(
        'auto',
        blank=True,
        null=True,
        folder='planpal/messages/attachments',
        resource_type='auto',  # auto detect file type
        help_text="Attachment file (image, document, etc.)"
    )
    
    attachment_name = models.CharField(
        max_length=255,
        blank=True,
        help_text="Original file name"
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
            if not (self.latitude and self.longitude):
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

    def soft_delete(self):
        self.is_deleted = True
        self.content = "[Tin nhắn đã bị xóa]"
        self.save(update_fields=['is_deleted', 'content', 'updated_at'])

    def save(self, *args: Any, **kwargs: Any) -> None:
        if not hasattr(self, '_clean_called'):
            self.clean()
            self._clean_called = True
            
        super().save(*args, **kwargs)
        
        # Update conversation's last message time (simple model logic)
        if self.conversation and not self.is_deleted:
            if not self.conversation.last_message_at or self.created_at > self.conversation.last_message_at:
                self.conversation.last_message_at = self.created_at
                self.conversation.save(update_fields=['last_message_at'])
        
        # Clear unread message cache for participants
        if self.conversation:
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
        User,
        on_delete=models.CASCADE,
        related_name='message_read_statuses',
        help_text="User who has read the message"
    )
    
    read_at = models.DateTimeField(
        auto_now_add=True,
        help_text="Time when the message was read"
    )

    class Meta:
        db_table = 'planpal_message_read_statuses'
        # Mỗi user chỉ đọc 1 message 1 lần
        unique_together = ('message', 'user')
        
        indexes = [
            *BaseModel.Meta.indexes,
            # Index cho query read status của message
            models.Index(fields=['message', 'read_at']),
            # Index cho query read status của user
            models.Index(fields=['user', 'read_at']),
        ]
        
        ordering = ['read_at']

    def __str__(self) -> str:
        return f"{self.user.username} read message {self.message.id}"


try:
    from django.db.models.signals import post_save
    from django.dispatch import receiver
    import logging

    @receiver(post_save, sender=Plan)
    def _plan_post_save_schedule(sender, instance, created, **kwargs):
        try:
            if instance.status in ['cancelled', 'completed']:
                instance.revoke_scheduled_tasks()
                return

            instance.schedule_celery_tasks()
        except Exception:
            pass
except Exception:
    pass
