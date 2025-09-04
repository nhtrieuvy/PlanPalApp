import uuid
from collections import defaultdict
from decimal import Decimal

from django.db import models, transaction, IntegrityError
from django.db.models import constraints
from django.contrib.auth.models import AbstractUser
from django.utils import timezone
from django.core.validators import RegexValidator
from django.core.exceptions import ValidationError
from django.db.models import Q, F, Case, When, Count, Max, Sum, Exists, OuterRef, Subquery
from django.core.cache import cache

from cloudinary.models import CloudinaryField
from cloudinary import CloudinaryImage

class BaseModel(models.Model):
    
    id = models.UUIDField(
        primary_key=True,
        default=uuid.uuid4,
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

    class Meta:
        abstract = True  # Không tạo table riêng
        ordering = ['-created_at']
        
        indexes = [
            models.Index(fields=['created_at']),
            models.Index(fields=['updated_at']),
        ]

    def save(self, *args, **kwargs):
        self.full_clean()  # Chạy tất cả validations
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.__class__.__name__}({self.id})"


class UserQuerySet(models.QuerySet):

    def with_friends_count(self):
        """Annotate users with their friends count"""
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
    
    def with_plans_count(self):
        """Annotate users with their plans counts"""
        return self.annotate(
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
    
    def with_groups_count(self):
        """Annotate users with their active groups count"""
        return self.annotate(
            groups_count_annotated=Count(
                'joined_groups',
                filter=Q(joined_groups__is_active=True),
                distinct=True
            )
        )
    
    def with_friend_request_counts(self):
        """Annotate users with friend request related counts"""
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
    
    def with_counts(self):
        return self.with_friends_count().with_plans_count().with_groups_count().with_friend_request_counts()
    
    def with_cached_counts(self, cache_timeout=300):
        return self.with_counts()
    
    def active(self):
        return self.filter(is_active=True)
    
    def online(self):
        return self.filter(is_online=True)


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
    
    # Custom manager
    objects = UserQuerySet.as_manager()

    class Meta:
        db_table = 'planpal_users' 
        indexes = [
            # Kế thừa các indexes từ BaseModel
            *BaseModel.Meta.indexes,
            models.Index(fields=['first_name', 'last_name']),
            models.Index(fields=['is_online', 'last_seen']),
        ]

    def __str__(self):
        return f"{self.username} ({self.get_full_name()})"

    def update_last_seen(self):
        self.last_seen = timezone.now()
        self.save(update_fields=['last_seen'])

    def set_online_status(self, status):
        self.is_online = status
        if not status:
            self.last_seen = timezone.now()
        self.save(update_fields=['is_online', 'last_seen'])

    
    @transaction.atomic
    def create_personal_plan(self, title, start_date, end_date, **kwargs):
        return Plan.objects.create_plan_safe(
            creator=self,
            title=title,
            start_date=start_date,
            end_date=end_date,
            group=None,
            **kwargs
        )

    @transaction.atomic
    def create_group_plan(self, group, title, start_date, end_date, **kwargs):
        """Create group plan - permission validation should be in view layer"""
        return Plan.objects.create_plan_safe(
            creator=self,
            title=title,
            start_date=start_date,
            end_date=end_date,
            group=group,
            **kwargs
        )

    # === Messaging Methods ===
        
    def send_group_message(self, group, content, message_type='text', **kwargs):
        """Send group message - permission validation should be in view layer"""
        return group.send_message(
            sender=self,
            content=content,
            message_type=message_type,
            **kwargs
        )

    def get_or_create_direct_conversation(self, other_user):
        """Create direct conversation - permission validation should be in view layer"""
        if self == other_user:
            raise ValueError("Unable to create a conversation with yourself")
        
        return Conversation.get_or_create_direct_conversation(self, other_user)
    
    def send_direct_message(self, recipient, content, message_type='text', **kwargs):
        conversation, created = self.get_or_create_direct_conversation(recipient)
        return conversation.send_message(
            sender=self,
            content=content,
            message_type=message_type,
            **kwargs
        )

    # === Computed Properties - Plans ===
        
    @property
    def recent_conversations(self):
        return Conversation.objects.for_user(self).with_last_message().active().order_by('-last_message_at')
        
    @property
    def personal_plans(self):
        return self.created_plans.filter(
            plan_type='personal'
        ).select_related().order_by('-created_at')

    @property
    def group_plans(self):
        return Plan.objects.filter(
            group__members=self,
            plan_type='group'
        ).select_related('group', 'creator').order_by('-created_at')

    @property
    def all_plans(self):
        return Plan.objects.filter(
            Q(creator=self, plan_type='personal') |
            Q(group__members=self, plan_type='group')
        ).select_related('group', 'creator').order_by('-created_at')

    @property
    def viewable_plans(self):
        return Plan.objects.filter(
            Q(creator=self) |  # Own plans
            Q(group__members=self) |  # Group plans
            Q(is_public=True)  # Public plans
        ).select_related('group', 'creator').distinct().order_by('-created_at')
    
    @property
    def friends(self):
        return Friendship.get_friends_queryset(self)

    # === Computed Properties - Counts ===

    @property
    def plans_count(self):
        if hasattr(self, 'plans_count_annotated'):
            return self.plans_count_annotated
        return self.all_plans.count()

    @property
    def personal_plans_count(self):
        if hasattr(self, 'personal_plans_count_annotated'):
            return self.personal_plans_count_annotated
        return self.personal_plans.count()

    @property
    def group_plans_count(self):
        if hasattr(self, 'group_plans_count_annotated'):
            return self.group_plans_count_annotated
        return self.group_plans.count()

    @property
    def groups_count(self):
        if hasattr(self, 'groups_count_annotated'):
            return self.groups_count_annotated
        return self.joined_groups.filter(is_active=True).count()

    @property
    def friends_count(self):
        if hasattr(self, 'friends_count_annotated'):
            return self.friends_count_annotated
        return Friendship.objects.for_user(self).accepted().count()

    @property
    def pending_sent_count(self):
        if hasattr(self, 'pending_sent_count_annotated'):
            return self.pending_sent_count_annotated
        return Friendship.objects.sent_by(self).count()

    @property
    def pending_received_count(self):
        if hasattr(self, 'pending_received_count_annotated'):
            return self.pending_received_count_annotated
        return Friendship.objects.pending_for(self).count()

    @property
    def blocked_count(self):
        if hasattr(self, 'blocked_count_annotated'):
            return self.blocked_count_annotated
        return Friendship.objects.for_user(self).blocked().count()

    @property
    def user_groups(self):
        return self.joined_groups

    # === Computed Properties - Status & Media ===
    
    
    @property
    def online_status(self):
        if self.is_online:
            return 'online'
        return 'offline'

    @property
    def has_avatar(self):
        return bool(self.avatar)

    @property
    def avatar_url(self):
        if not self.has_avatar:
            return None
        if self.avatar:
            cloudinary_image = CloudinaryImage(str(self.avatar))
            return cloudinary_image.build_url(secure=True)
        return None

    @property
    def avatar_thumb(self):
        if not self.avatar:
            return None
        cloudinary_image = CloudinaryImage(str(self.avatar))
        return cloudinary_image.build_url(width=100, height=100, crop='fill', gravity='face', secure=True)

    @property
    def unread_messages_count(self):
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
    
    
    def get_or_create_direct_conversation(self, other_user):
        if self == other_user:
            raise ValueError("Unable to create a conversation with yourself")
        
        if not Friendship.are_friends(self, other_user):
            raise ValidationError("You can only chat with friends")

        return Conversation.get_or_create_direct_conversation(self, other_user)
    
    def send_direct_message(self, recipient, content, message_type='text', **kwargs):
        conversation, created = self.get_or_create_direct_conversation(recipient)
        return conversation.send_message(
            sender=self,
            content=content,
            message_type=message_type,
            **kwargs
        )
    
    def clear_unread_cache(self):
        cache_key = f"user_unread_count_{self.id}"
        cache.delete(cache_key)
    
    @classmethod
    def clear_unread_cache_for_users(cls, user_ids):
        cache_keys = [f"user_unread_count_{uid}" for uid in user_ids]
        cache.delete_many(cache_keys)
    

class FriendshipQuerySet(models.QuerySet):

    def accepted(self):
        return self.filter(status=self.model.ACCEPTED)
    
    def pending(self):
        return self.filter(status=self.model.PENDING)
    
    def rejected(self):
        return self.filter(status=self.model.REJECTED)
    
    def blocked(self):
        return self.filter(status=self.model.BLOCKED)
    
    def cleanup_old_rejected(self, days=180):
        cutoff = timezone.now() - timezone.timedelta(days=days)
        return self.rejected().exclude(
            rejections__created_at__gte=cutoff
        ).delete()
    
    def for_user(self, user):
        user_id = getattr(user, 'id', user)
        return self.filter(Q(user_a_id=user_id) | Q(user_b_id=user_id))
    
    def friends_of(self, user):
        return self.accepted().for_user(user)
    
    def pending_for(self, user):
        user_id = getattr(user, 'id', user)
        return self.pending().filter(
            Q(user_b_id=user_id) | Q(user_a_id=user_id)
        ).exclude(initiator_id=user_id)
    
    def sent_by(self, user):
        user_id = getattr(user, 'id', user)
        return self.pending().filter(initiator_id=user_id)
    
    def between_users(self, user1, user2):
        user1_id = getattr(user1, 'id', user1)
        user2_id = getattr(user2, 'id', user2)
        
        if user1_id < user2_id:
            return self.filter(user_a_id=user1_id, user_b_id=user2_id)
        else:
            return self.filter(user_a_id=user2_id, user_b_id=user1_id)
    
    def get_friends_ids(self, user):
        """Get friend IDs - OPTIMIZED with database-level computation"""
        user_id = getattr(user, 'id', user)
        
        # Use database CASE statement to avoid Python loop
        friend_ids = self.accepted().for_user(user).annotate(
            friend_id=Case(
                When(user_a_id=user_id, then=F('user_b_id')),
                default=F('user_a_id'),
                output_field=models.UUIDField()
            )
        ).values_list('friend_id', flat=True)
        
        return list(friend_ids)
    
    @transaction.atomic
    def create_friendship_safe(self, initiator, target, status=None):
        if initiator == target:
            raise ValidationError("Cannot create friendship with yourself")
        
        initiator_id = getattr(initiator, 'id', initiator)
        target_id = getattr(target, 'id', target)
        
        if initiator_id < target_id:
            user_a_id, user_b_id = initiator_id, target_id
        else:
            user_a_id, user_b_id = target_id, initiator_id
        
        status = status or self.model.PENDING
        
        try:
            friendship, created = self.get_or_create(
                user_a_id=user_a_id,
                user_b_id=user_b_id,
                defaults={
                    'initiator_id': initiator_id,
                    'status': status
                }
            )
            
            if not created and friendship.status == self.model.REJECTED and status == self.model.PENDING:
                rejections = friendship.rejections.all()[:self.model.MAX_REJECTION_COUNT + 1]
                
                if rejections:
                    last_rejection = rejections[0]
                    time_since_rejection = timezone.now() - last_rejection.created_at
                    rejection_count = len(rejections)
                    
                    # Determine cooldown period
                    if rejection_count >= self.model.MAX_REJECTION_COUNT:
                        cooldown_period = timezone.timedelta(days=self.model.EXTENDED_COOLDOWN_DAYS)
                        cooldown_msg = f"Must wait {self.model.EXTENDED_COOLDOWN_DAYS} days after {rejection_count} rejections"
                    else:
                        cooldown_period = timezone.timedelta(hours=self.model.REJECTION_COOLDOWN_HOURS)
                        cooldown_msg = f"Must wait {self.model.REJECTION_COOLDOWN_HOURS} hours after rejection"
                    
                    if time_since_rejection < cooldown_period:
                        remaining_time = cooldown_period - time_since_rejection
                        raise ValidationError(f"Cannot resend friend request yet. {cooldown_msg}. Time remaining: {remaining_time}")
                
                friendship.status = self.model.PENDING
                friendship.initiator_id = initiator_id
                friendship.save(update_fields=['status', 'initiator_id', 'updated_at'])
                created = False  
                
            return friendship, created

        # Bắt lỗi khi 2 request tạo cùng lúc
        except IntegrityError:
            return self.get(user_a_id=user_a_id, user_b_id=user_b_id), False


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

    def clean(self):
        super().clean()
        
        if self.friendship and self.rejected_by:
            if self.rejected_by_id not in [self.friendship.user_a_id, self.friendship.user_b_id]:
                raise ValidationError("Only friendship participants can reject the request")

            if self.rejected_by_id == self.friendship.initiator_id:
                raise ValidationError("The initiator cannot reject their own request")
            
            if self.friendship.status != Friendship.PENDING:
                raise ValidationError("Can only reject pending friendship requests")

    def __str__(self):
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
                check=Q(user_a__isnull=False) & Q(user_b__isnull=False),
                name='both_users_must_exist'
            ),
            models.CheckConstraint(
                check=~Q(user_a=F('user_b')),
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

    def __str__(self):
        if not (self.user_a and self.user_b and self.initiator):
            return f"Friendship({self.id}) - Incomplete"
        direction = "→" if self.initiator == self.user_a else "←"
        return f"{self.user_a.username} {direction} {self.user_b.username} ({self.get_status_display()})"

    def clean(self):
        super().clean()
        
        # Model-level validations
        if self.user_a_id and self.user_b_id:
            if self.user_a_id == self.user_b_id:
                raise ValidationError("Cannot create friendship with yourself")
        
        if self.initiator_id and self.user_a_id and self.user_b_id:
            if self.initiator_id not in [self.user_a_id, self.user_b_id]:
                raise ValidationError("Initiator must be one of the friendship participants")

    def save(self, *args, **kwargs):
        if self.user_a_id and self.user_b_id:
            if self.user_a_id > self.user_b_id:
                self.user_a_id, self.user_b_id = self.user_b_id, self.user_a_id
        
        self.clean()
        super().save(*args, **kwargs)

    # === Instance Methods ===
    
    def get_other_user(self, user):
        user_id = getattr(user, 'id', user)
        if user_id == self.user_a_id:
            return self.user_b
        elif user_id == self.user_b_id:
            return self.user_a
        else:
            raise ValueError("User is not a participant in this friendship")
    
    def get_receiver(self):
        return self.user_b if self.initiator == self.user_a else self.user_a
    
    def is_initiated_by(self, user):
        user_id = getattr(user, 'id', user)
        return self.initiator_id == user_id
    
    def can_be_accepted_by(self, user):
        return (
            self.status == self.PENDING and 
            not self.is_initiated_by(user) and
            user in [self.user_a, self.user_b]
        )

    @transaction.atomic
    def accept(self):
        self.status = self.ACCEPTED
        self.save(update_fields=['status', 'updated_at'])
        return True

    @transaction.atomic
    def reject(self, user=None):
        self.status = self.REJECTED
        self.save(update_fields=['status', 'updated_at'])
        
        # Create rejection record for cooldown tracking
        FriendshipRejection.objects.create(
            friendship=self,
            rejected_by=user or self.get_receiver()
        )
        
        return True

    # === Instance Methods - Rejection History ===
    
    def get_rejection_count(self):
        return self.rejections.count()
    
    def get_recent_rejection_count(self, days=30):
        cutoff = timezone.now() - timezone.timedelta(days=days)
        return self.rejections.filter(created_at__gte=cutoff).count()
    
    def get_last_rejection(self):
        return self.rejections.first()  # Already ordered by -created_at
    
    def was_rejected_by(self, user):
        user_id = getattr(user, 'id', user)
        return self.rejections.filter(rejected_by_id=user_id).exists()
    

    @transaction.atomic
    def block(self, blocking_user):
        self.status = self.BLOCKED
        self.initiator = blocking_user if hasattr(blocking_user, 'id') else User.objects.get(id=blocking_user)
        self.save(update_fields=['status', 'initiator', 'updated_at'])

    @transaction.atomic
    def unfriend(self):
        if self.status == self.ACCEPTED:
            self.delete()
            return True
        return False

    # === Class Methods ===

    @classmethod
    def get_friendship_status(cls, user1, user2):
        friendship = cls.objects.between_users(user1, user2).first()
        return friendship.status if friendship else None
    
    @classmethod
    def are_friends(cls, user1, user2):
        return cls.objects.between_users(user1, user2).accepted().exists()
    
    @classmethod
    def is_blocked(cls, user1, user2):
        return cls.objects.between_users(user1, user2).blocked().exists()
    
    @classmethod
    def get_friends_queryset(cls, user):
        user_id = getattr(user, 'id', user)
        
        return User.objects.filter(
            Q(friendships_as_a__user_b_id=user_id, friendships_as_a__status=cls.ACCEPTED) |
            Q(friendships_as_b__user_a_id=user_id, friendships_as_b__status=cls.ACCEPTED)
        ).select_related().distinct()

    @classmethod
    def get_pending_requests(cls, user):
        return cls.objects.pending_for(user).select_related(
            'initiator', 'user_a', 'user_b'
        ).order_by('-created_at')

    @classmethod
    def get_sent_requests(cls, user):
        return cls.objects.sent_by(user).select_related(
            'user_a', 'user_b'
        ).order_by('-created_at')

    @classmethod
    @transaction.atomic
    def create_friend_request(cls, initiator, target):
        return cls.objects.create_friendship_safe(initiator, target, cls.PENDING)

    @classmethod
    def get_friendship(cls, user1, user2):
        return cls.objects.between_users(user1, user2).select_related(
            'user_a', 'user_b', 'initiator'
        ).first()
    
    

    @classmethod
    def cleanup_old_rejected_friendships(cls, days=180):
        return cls.objects.cleanup_old_rejected(days)
    
    

class GroupQuerySet(models.QuerySet):
    
    def with_member_count(self):
        return self.annotate(
            member_count_annotated=Count('members', distinct=True)
        )
    
    def with_admin_count(self):
        return self.annotate(
            admin_count_annotated=Count(
                'memberships', 
                filter=Q(memberships__role=GroupMembership.ADMIN),
                distinct=True
            )
        )
    
    def with_plans_count(self):
        return self.annotate(
            plans_count_annotated=Count('plans', distinct=True),
            active_plans_count_annotated=Count(
                'plans',
                filter=~Q(plans__status__in=['cancelled', 'completed']),
                distinct=True
            )
        )
    
    def with_full_stats(self):
        return self.with_member_count().with_admin_count().with_plans_count()
    
    def active(self):
        return self.filter(is_active=True)
    
    def for_user(self, user):
        return self.filter(members=user)
    
    def administered_by(self, user):
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
    
    is_active = models.BooleanField(
        default=True,
        db_index=True,
        help_text="Is the group active?"
    )
    
    objects = GroupQuerySet.as_manager()

    class Meta:
        db_table = 'planpal_groups'
        
        indexes = [
            *BaseModel.Meta.indexes,
            models.Index(fields=['admin', 'is_active']),
            models.Index(fields=['is_active', 'created_at']),
        ]

    def __str__(self):
        return f"{self.name} (Admin: {self.admin.username})"

    def save(self, *args, **kwargs):
        # Cờ kiểm tra nếu là nhóm mới
        is_new = self._state.adding
        
        super().save(*args, **kwargs)
        
        if is_new and self.admin:
            GroupMembership.objects.get_or_create(
                group=self,
                user=self.admin,
                defaults={'role': GroupMembership.ADMIN}
            )
            
            Conversation.get_or_create_for_group(self)

    @property
    def has_avatar(self):
        return bool(self.avatar)

    @property
    def avatar_url(self):
        if not self.avatar:
            return None
        cloudinary_image = CloudinaryImage(str(self.avatar))
        return cloudinary_image.build_url(width=300, height=300, crop='fill', gravity='face', secure=True)

    @property
    def avatar_thumb(self):
        if not self.avatar:
            return None
        cloudinary_image = CloudinaryImage(str(self.avatar))
        return cloudinary_image.build_url(width=100, height=100, crop='fill', gravity='face', secure=True)

    @property
    def has_cover_image(self):
        return bool(self.cover_image)

    @property
    def cover_image_url(self):
        if not self.cover_image:
            return None
        cloudinary_image = CloudinaryImage(str(self.cover_image))
        return cloudinary_image.build_url(width=1200, height=600, crop='fill', gravity='center', secure=True)

    @property
    def member_count(self):
        if hasattr(self, 'member_count_annotated'):
            return self.member_count_annotated
        return self.members.count()

    @property
    def admin_count(self):
        if hasattr(self, 'admin_count_annotated'):
            return self.admin_count_annotated
        return self.get_admin_count()

    @property
    def plans_count(self):
        if hasattr(self, 'plans_count_annotated'):
            return self.plans_count_annotated
        return self.plans.count()

    @property
    def active_plans_count(self):
        if hasattr(self, 'active_plans_count_annotated'):
            return self.active_plans_count_annotated
        return self.plans.exclude(status__in=['cancelled', 'completed']).count()
    
    
    @transaction.atomic
    def add_member(self, user, role='member'):
        membership, created = GroupMembership.objects.get_or_create(
            user=user,
            group=self,
            defaults={'role': role}
        )
        
        if hasattr(self, 'conversation') and created:
            self.conversation.sync_group_participants()
        
        return membership, created

    @transaction.atomic
    def remove_member(self, user):
        try:
            membership = GroupMembership.objects.select_for_update().get(
                user=user, 
                group=self
            )
            
            if membership.role == GroupMembership.ADMIN:
                admin_memberships = GroupMembership.objects.select_for_update().filter(
                    group=self,
                    role=GroupMembership.ADMIN
                )
                
                other_admin_count = admin_memberships.exclude(user=user).count()
                
                if other_admin_count == 0:
                    raise ValueError("Không thể xóa admin cuối cùng. Nhóm phải có ít nhất một admin.")
            
            membership.delete()
            
            if hasattr(self, 'conversation'):
                self.conversation.sync_group_participants()
            
            return True
            
        except GroupMembership.DoesNotExist:
            return False

    def is_member(self, user):
        return GroupMembership.objects.filter(
            group=self,
            user=user
        ).exists()

    def is_admin(self, user):
        return GroupMembership.objects.filter(
            group=self,
            user=user,
            role=GroupMembership.ADMIN
        ).exists()

    def get_admins(self):
        return User.objects.filter(
            groupmembership__group=self,
            groupmembership__role=GroupMembership.ADMIN
        )
    
    def get_admin_count(self):
        if hasattr(self, 'admin_count_annotated'):
            return self.admin_count_annotated
        
        return GroupMembership.objects.filter(
            group=self,
            role=GroupMembership.ADMIN
        ).count()
    
    def get_user_role(self, user):
        try:
            membership = GroupMembership.objects.only('role').get(
                group=self,
                user=user
            )
            return membership.role
        except GroupMembership.DoesNotExist:
            return None
    
    def get_user_membership(self, user):
        try:
            return GroupMembership.objects.select_related('user').get(
                group=self,
                user=user
            )
        except GroupMembership.DoesNotExist:
            return None
    
    @transaction.atomic
    def promote_to_admin(self, user):
        try:
            membership = GroupMembership.objects.select_for_update().get(
                group=self, 
                user=user
            )
            return membership.promote_to_admin()
        except GroupMembership.DoesNotExist:
            return False
    
    @transaction.atomic
    def demote_from_admin(self, user):
        try:
            # Lock membership record
            membership = GroupMembership.objects.select_for_update().get(
                group=self, 
                user=user
            )
            return membership.demote_to_member()
        except GroupMembership.DoesNotExist:
            return False
    
    def get_member_roles(self):
        return dict(
            GroupMembership.objects.filter(group=self)
            .values_list('user_id', 'role')
        )
    
    def can_demote_user(self, user):
        user_role = self.get_user_role(user)
        if user_role != GroupMembership.ADMIN:
            return True
        
        return self.get_admin_count() > 1
    
    def can_remove_user(self, user):
        user_role = self.get_user_role(user)
        if user_role is None:
            return False
        if user_role != GroupMembership.ADMIN:
            return True
            
        return self.get_admin_count() > 1
        
    def send_message(self, sender, content, message_type='text', **kwargs):
        message = ChatMessage.objects.create(
            group=self,
            sender=sender,
            content=content,
            message_type=message_type,
            **kwargs
        )
        return message

    def get_recent_messages(self, limit=50):
        return self.messages.active().select_related('sender').order_by('-created_at')[:limit]

    def get_unread_messages_count(self, user):
        if not self.is_member(user):
            return 0
        
        return self.messages.filter(
            is_deleted=False
        ).exclude(
            Q(sender=user) | Q(read_statuses__user=user)
        ).count()

    def mark_messages_as_read(self, user, up_to_message=None):
        if not self.is_member(user):
            return
        
        messages = self.messages.filter(is_deleted=False).exclude(sender=user)
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


class GroupMembershipQuerySet(models.QuerySet):
    """Custom QuerySet for GroupMembership"""
    
    def admins(self):
        return self.filter(role=GroupMembership.ADMIN)
    
    def members(self):
        return self.filter(role=GroupMembership.MEMBER)
    
    def for_group(self, group):
        return self.filter(group=group)
    
    def for_user(self, user):
        return self.filter(user=user)


class GroupMembership(BaseModel):
    """
    Through model cho relationship User-Group
    Lưu thêm thông tin về role và thời gian join
    """
    
    # Các role trong nhóm
    ADMIN = 'admin'
    MEMBER = 'member'
    
    ROLE_CHOICES = [
        (ADMIN, 'Quản trị viên'),
        (MEMBER, 'Thành viên'),
    ]
    
    
    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        help_text="User trong nhóm"
    )
    
    group = models.ForeignKey(
        Group,
        on_delete=models.CASCADE,
        related_name='memberships',
        help_text="Nhóm"
    )
    
    # Role của user trong nhóm
    role = models.CharField(
        max_length=20,
        choices=ROLE_CHOICES,
        default=MEMBER,
        db_index=True,
        help_text="Vai trò trong nhóm"
    )
    
    # Thời gian join
    joined_at = models.DateTimeField(
        auto_now_add=True,
        help_text="Thời gian tham gia nhóm"
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
        
        ordering = ['joined_at']

    def __str__(self):
        return f"{self.user.username} in {self.group.name} ({self.get_role_display()})"

    def clean(self):
        """Validate membership rules"""
        super().clean()
        
        if self.pk and self.role == self.MEMBER:
            admin_count = GroupMembership.objects.filter(
                group=self.group,
                role=self.ADMIN
            ).exclude(pk=self.pk).count()
            
            if admin_count == 0:
                raise ValidationError("Nhóm phải có ít nhất một admin. Không thể hạ cấp admin cuối cùng.")

    def save(self, *args, **kwargs):
        """Override save to enforce business rules"""
        if self.pk and self.role == self.MEMBER:
            admin_count = GroupMembership.objects.filter(
                group=self.group,
                role=self.ADMIN
            ).exclude(pk=self.pk).count()
            
            if admin_count == 0:
                raise ValueError("Nhóm phải có ít nhất một admin")
        
        self.clean()
        super().save(*args, **kwargs)

    def promote_to_admin(self):
        """Thăng cấp thành admin"""
        if self.role == self.MEMBER:
            self.role = self.ADMIN
            self.save(update_fields=['role'])
            return True
        return False

    @transaction.atomic
    def demote_to_member(self):
        """
        Hạ cấp xuống member với row-level locking để tránh race condition
        khi nhiều admin bị demote cùng lúc
        """
        # Lock tất cả admin records của group để đảm bảo count chính xác
        admin_memberships = GroupMembership.objects.select_for_update().filter(
            group=self.group,
            role=self.ADMIN
        )
        
        # Đếm admin khác ngoài membership hiện tại
        other_admin_count = admin_memberships.exclude(pk=self.pk).count()
        
        if other_admin_count == 0:
            raise ValueError("Không thể hạ cấp admin cuối cùng. Nhóm phải có ít nhất một admin.")
        
        if self.role == self.ADMIN:
            self.role = self.MEMBER
            self.save(update_fields=['role'])
            return True
        return False

class PlanQuerySet(models.QuerySet):
    """Custom QuerySet for Plan with optimized methods"""
    
    def personal(self):
        """Filter personal plans"""
        return self.filter(plan_type='personal')
    
    def group_plans(self):
        """Filter group plans"""
        return self.filter(plan_type='group')
    
    def public(self):
        """Filter public plans"""
        return self.filter(is_public=True)
    
    def upcoming(self):
        """Filter upcoming plans"""
        return self.filter(status='upcoming')
    
    def ongoing(self):
        """Filter ongoing plans"""
        return self.filter(status='ongoing')
    
    def completed(self):
        """Filter completed plans"""
        return self.filter(status='completed')
    
    def active(self):
        """Filter active plans (not cancelled/completed)"""
        return self.exclude(status__in=['cancelled', 'completed'])
    
    def for_user(self, user):
        """Filter plans viewable by user"""
        return self.filter(
            Q(creator=user) |  # Own plans
            Q(group__members=user) |  # Group plans
            Q(is_public=True)  # Public plans
        ).distinct()
    
    def with_activity_count(self):
        """Annotate with activity count"""
        return self.annotate(
            activity_count_annotated=Count('activities', distinct=True)
        )
    
    def with_total_cost(self):
        """Annotate with total estimated cost"""
        return self.annotate(
            total_cost_annotated=Sum('activities__estimated_cost')
        )
    
    def with_stats(self):
        """Annotate with full statistics"""
        return self.with_activity_count().with_total_cost()
    
    def in_date_range(self, start_date=None, end_date=None):
        """Filter plans within date range"""
        queryset = self
        if start_date:
            queryset = queryset.filter(start_date__gte=start_date)
        if end_date:
            queryset = queryset.filter(end_date__lte=end_date)
        return queryset
    
    def overlapping_with(self, start_date, end_date):
        """Filter plans that overlap with given date range"""
        return self.filter(
            start_date__lt=end_date,
            end_date__gt=start_date
        )
    
    @transaction.atomic
    def create_plan_safe(self, creator, title, start_date, end_date, **kwargs):
        """
        Create plan với validation và conflict checking
        
        Args:
            creator: User tạo plan
            title: Tiêu đề plan
            start_date: Ngày bắt đầu
            end_date: Ngày kết thúc
            **kwargs: Các fields khác
            
        Returns:
            Plan: Created plan
            
        Raises:
            ValueError: Nếu có validation errors hoặc conflicts
        """
        group = kwargs.get('group')
        
        # Validate dates
        if end_date <= start_date:
            raise ValueError("Ngày kết thúc phải sau ngày bắt đầu")
        
        # Validate group permissions
        if group:
            if not group.is_member(creator):
                raise ValueError("Bạn không phải thành viên của nhóm này")
            
            # Check conflicting plans trong group (optional business rule)
            overlapping = self.filter(
                group=group,
                start_date__lt=end_date,
                end_date__gt=start_date,
                status__in=['upcoming', 'ongoing']
            )
            if overlapping.exists():
                raise ValueError("Nhóm đã có plan khác trong khoảng thời gian này")
        
        # Set plan_type automatically
        kwargs['plan_type'] = 'group' if group else 'personal'
        
        # Create plan
        plan = Plan.objects.create(
            creator=creator,
            title=title,
            start_date=start_date,
            end_date=end_date,
            **kwargs
        )
        
        return plan


class Plan(BaseModel):
    """
    Model quản lý kế hoạch du lịch
    Hỗ trợ cả Personal Plan (group=null) và Group Plan
    """
    
    
    # Thông tin cơ bản của kế hoạch
    title = models.CharField(
        max_length=200,
        help_text="Tiêu đề kế hoạch du lịch"
    )
    
    description = models.TextField(
        blank=True,
        help_text="Mô tả chi tiết về kế hoạch"
    )
    
    # Group có thể null cho personal plan
    group = models.ForeignKey(
        Group,
        on_delete=models.CASCADE,
        related_name='plans',
        blank=True,
        null=True,  # Cho phép null cho personal plan
        help_text="Nhóm sở hữu kế hoạch này (null nếu là personal plan)"
    )
    
    # Người tạo/sở hữu kế hoạch
    creator = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='created_plans',
        help_text="Người tạo/sở hữu kế hoạch"
    )
    
    # Loại kế hoạch
    PLAN_TYPES = [
        ('personal', 'Cá nhân'),
        ('group', 'Nhóm'),
    ]
    
    plan_type = models.CharField(
        max_length=20,
        choices=PLAN_TYPES,
        default='personal',
        db_index=True,
        help_text="Loại kế hoạch: cá nhân hoặc nhóm"
    )
    
    # Thời gian của chuyến đi
    start_date = models.DateTimeField(
        help_text="Thời gian bắt đầu chuyến đi"
    )
    
    end_date = models.DateTimeField(
        help_text="Thời gian kết thúc chuyến đi"
    )
    
    # # Ngân sách dự kiến
    # budget = models.DecimalField(
    #     max_digits=12,
    #     decimal_places=2,
    #     blank=True, 
    #     null=True,
    #     help_text="Ngân sách dự kiến (VND)"
    # )
    
    # Trạng thái công khai
    is_public = models.BooleanField(
        default=False,
        db_index=True,
        help_text="Có thể xem công khai không"
    )
    
    # Trạng thái kế hoạch
    STATUS_CHOICES = [
        ('upcoming', 'Sắp bắt đầu'),
        ('ongoing', 'Đang diễn ra'),
        ('completed', 'Đã hoàn thành'),
        ('cancelled', 'Đã hủy'),
    ]
    
    status = models.CharField(
        max_length=20,
        choices=STATUS_CHOICES,
        default='upcoming',  # đồng bộ với STATUS_CHOICES hiện tại
        db_index=True,
        help_text="Trạng thái kế hoạch"
    )
    
    # Remove timestamps vì đã có trong BaseModel
    
    # Custom manager - use QuerySet.as_manager()
    objects = PlanQuerySet.as_manager()

    class Meta:
        db_table = 'planpal_plans'
        
        indexes = [
            *BaseModel.Meta.indexes,
            # Index cho personal plans
            models.Index(fields=['creator', 'plan_type', 'status']),
            # Index cho group plans
            models.Index(fields=['group', 'status']),
            # Index cho tìm kiếm theo thời gian
            models.Index(fields=['start_date', 'end_date']),
            # Index cho public plans
            models.Index(fields=['is_public', 'plan_type', 'status']),
        ]

    def __str__(self):
        if self.is_personal():
            return f"{self.title} (Personal - {self.creator.username})"
        return f"{self.title} ({self.group.name})"

    def clean(self):
        """Validation cho plan"""
        
        # Validate date
        if self.start_date and self.end_date:
            if self.end_date <= self.start_date:
                raise ValidationError("Ngày kết thúc phải sau ngày bắt đầu")
        
        # Validate plan type consistency
        if self.plan_type == 'personal' and self.group is not None:
            raise ValidationError("Personal plan không thể có group")
        
        if self.plan_type == 'group' and self.group is None:
            raise ValidationError("Group plan phải có group")

    def _auto_status(self):
        """Chuẩn hoá & tự động cập nhật status dựa vào thời gian.

        Chuyển trạng thái theo timeline nếu chưa bị cancelled/completed.
        """
        now = timezone.now()
        if self.start_date and self.end_date:
            if self.status == 'upcoming' and now >= self.start_date:
                self.status = 'ongoing'
            if self.status == 'ongoing' and now > self.end_date:
                self.status = 'completed'

    def save(self, *args, **kwargs):
        """Override save để auto-set plan_type & auto status"""
        self.plan_type = 'personal' if self.group is None else 'group'
        self._auto_status()
        self.clean()
        super().save(*args, **kwargs)

    # Helper methods
    def is_personal(self):
        """Check xem có phải personal plan không"""
        return self.plan_type == 'personal'

    def is_group_plan(self):
        """Check xem có phải group plan không"""
        return self.plan_type == 'group'


    @property
    def collaborators(self):
        """Lấy danh sách những người có thể xem/edit plan"""
        if self.is_personal():
            return [self.creator]
        elif self.is_group_plan() and self.group:
            return list(self.group.members.all())
        return []

    
    @property
    def duration_days(self):
        """Tính số ngày của chuyến đi"""
        if self.start_date and self.end_date:
            return (self.end_date.date() - self.start_date.date()).days + 1
        return 0

    @property
    def activities_count(self):
        """Đếm số hoạt động trong kế hoạch - OPTIMIZED"""
        # Use annotated value if available, fallback to count()
        if hasattr(self, 'activity_count_annotated'):
            return self.activity_count_annotated
        return self.activities.count()

    @property
    def total_estimated_cost(self):
        """Tính tổng chi phí dự kiến từ các activities - OPTIMIZED"""
        # Use annotated value if available, fallback to aggregation
        if hasattr(self, 'total_cost_annotated'):
            return self.total_cost_annotated or 0
        
        result = self.activities.aggregate(
            total=Sum('estimated_cost')
        )['total']
        return result or 0

    def get_members(self):
        """Trả về queryset các user tham gia kế hoạch - OPTIMIZED"""
        if self.is_personal():
            return User.objects.filter(id=self.creator_id).select_related()
        if self.group_id:
            return self.group.members.select_related()
        return User.objects.none()

    def add_activity_with_place(self, title, start_time, end_time, place_id=None, **extra_data):
        """
        Add activity to plan with place lookup using Goong Map API - FAT MODEL
        
        Args:
            title: Activity title
            start_time: datetime object
            end_time: datetime object  
            place_id: Goong Map API place ID
            **extra_data: Other activity fields
        """
        # Get place details if place_id provided
        if place_id:
            from .services.goong_service import goong_service
            place_details = goong_service.get_place_details(place_id)
            if place_details:
                extra_data.update({
                    'location_name': place_details['name'],
                    'location_address': place_details['formatted_address'],
                    'latitude': place_details['latitude'],
                    'longitude': place_details['longitude'],
                })
        
        return self.add_activity(title, start_time, end_time, **extra_data)

    def notify_activity_added(self, updater):
        """Notify plan members about new activity - FAT MODEL"""
        from .services.notification_service import notification_service
        notification_service.notify_plan_update(
            plan_id=str(self.id),
            updater_name=updater.username,
            update_type='activity_added',
            updater_id=str(updater.id)
        )

    @transaction.atomic
    def add_activity(self, title, start_time, end_time, **kwargs):
        """
        Thêm hoạt động vào kế hoạch với conflict detection
        
        Args:
            title: Tên hoạt động
            start_time: Thời gian bắt đầu
            end_time: Thời gian kết thúc
            **kwargs: Các field khác của PlanActivity
            
        Raises:
            ValueError: Nếu thời gian không hợp lệ hoặc conflict
            Plan.DoesNotExist: Nếu plan bị xóa
        """
        # Lock plan để tránh concurrent modifications
        plan = Plan.objects.select_for_update().get(pk=self.pk)
        
        # Validate plan vẫn tồn tại và editable
        if plan.status in ['cancelled', 'completed']:
            raise ValueError(f"Không thể thêm activity vào plan đã {plan.get_status_display().lower()}")
        
        # Validate thời gian nằm trong khoảng của plan
        if start_time.date() < plan.start_date.date() or end_time.date() > plan.end_date.date():
            raise ValueError("Hoạt động phải nằm trong thời gian của kế hoạch")
        
        # Check time conflicts với activities hiện tại
        conflicting_activity = plan.check_activity_overlap(start_time, end_time)
        if conflicting_activity:
            raise ValueError(
                f"Xung đột thời gian với activity '{conflicting_activity.title}' "
                f"({conflicting_activity.start_time} - {conflicting_activity.end_time})"
            )
        
        # Auto-assign order nếu chưa có
        if 'order' not in kwargs:
            # Get max order cho ngày này, atomic increment
            same_date_activities = plan.activities.filter(
                start_time__date=start_time.date()
            )
            max_order = same_date_activities.aggregate(
                max_order=models.Max('order')
            )['max_order'] or 0
            kwargs['order'] = max_order + 1
        
        # Tạo activity
        activity = PlanActivity.objects.create(
            plan=plan,
            title=title,
            start_time=start_time,
            end_time=end_time,
            **kwargs
        )
        
        # Update plan updated_at để invalidate cache/notify clients
        plan.save(update_fields=['updated_at'])
        
        return activity

    @property
    def activities_by_date(self):
        """Lấy activities nhóm theo ngày - Dictionary - OPTIMIZED"""
        activities = self.activities.order_by('start_time').select_related()
        result = defaultdict(list)
        
        for activity in activities:
            date = activity.start_time.date()
            result[date].append(activity)
        
        return dict(result)

    def get_activities_by_date(self, date):
        """Lấy các hoạt động trong ngày cụ thể"""
        return self.activities.filter(
            start_time__date=date
        ).order_by('start_time')

    def check_activity_overlap(self, start_time, end_time, exclude_id=None):
        """
        Check and return overlapping activity - FAT MODEL
        
        Args:
            start_time: Thời gian bắt đầu
            end_time: Thời gian kết thúc  
            exclude_id: Loại trừ activity ID này (khi update)
            
        Returns:
            PlanActivity object if overlap found, None otherwise
        """
        queryset = self.activities.filter(
            start_time__lt=end_time,
            end_time__gt=start_time
        )
        
        if exclude_id:
            queryset = queryset.exclude(id=exclude_id)
            
        return queryset.first()  # Return first overlapping activity

    def has_time_conflict(self, start_time, end_time, exclude_activity=None):
        """
        Check xem có xung đột thời gian với activities khác không
        
        Args:
            start_time: Thời gian bắt đầu
            end_time: Thời gian kết thúc  
            exclude_activity: Loại trừ activity này (khi update)
        """
        queryset = self.activities.filter(
            start_time__lt=end_time, #less than để tạo truy vấn <
            end_time__gt=start_time #greater than để tạo truy vấn >
        )
        
        if exclude_activity:
            queryset = queryset.exclude(id=exclude_activity.id)
            
        return queryset.exists()


    @transaction.atomic
    def start_trip(self, user=None):
        """
        Bắt đầu chuyến đi với conflict detection
        
        Args:
            user: User thực hiện action (để log/permission check)
            
        Returns:
            bool: True nếu thành công, False nếu không thể start
            
        Raises:
            ValueError: Nếu plan không thể start (wrong status, conflicts)
        """
        # Lock plan để tránh concurrent status changes
        plan = Plan.objects.select_for_update().get(pk=self.pk)
        
        # Validate current status
        if plan.status != 'upcoming':
            raise ValueError(f"Không thể bắt đầu chuyến đi từ trạng thái '{plan.get_status_display()}'")
        
        # Business validation
        if not plan.activities.exists():
            raise ValueError("Không thể bắt đầu chuyến đi không có hoạt động nào")
        
        # Check date validity (optional - could be auto-status logic)
        now = timezone.now()
        if plan.start_date > now:
            raise ValueError("Chưa đến thời gian bắt đầu chuyến đi")
        
        # Update status atomically
        updated_count = Plan.objects.filter(
            pk=plan.pk,
            status='upcoming'  # Double-check trước khi update
        ).update(
            status='ongoing',
            updated_at=timezone.now()
        )
        
        if updated_count == 0:
            raise ValueError("Plan đã bị thay đổi bởi user khác")
        
        # Refresh instance
        self.refresh_from_db()
        return True

    @transaction.atomic
    def complete_trip(self, user=None):
        """
        Hoàn thành chuyến đi với validation
        """
        plan = Plan.objects.select_for_update().get(pk=self.pk)
        
        if plan.status != 'ongoing':
            raise ValueError(f"Không thể hoàn thành từ trạng thái '{plan.get_status_display()}'")
        
        updated_count = Plan.objects.filter(
            pk=plan.pk,
            status='ongoing'
        ).update(
            status='completed',
            updated_at=timezone.now()
        )
        
        if updated_count == 0:
            raise ValueError("Plan đã bị thay đổi bởi user khác")
        
        self.refresh_from_db()
        return True
    
    @transaction.atomic
    def cancel_trip(self, user=None, reason=None):
        """
        Hủy chuyến đi với validation và cleanup
        """
        plan = Plan.objects.select_for_update().get(pk=self.pk)
        
        if plan.status in ['cancelled', 'completed']:
            raise ValueError(f"Không thể hủy plan đã {plan.get_status_display().lower()}")
        
        # Permission check (nếu cần)
        if user and plan.is_group_plan():
            if not plan.group.is_admin(user):
                raise ValueError("Chỉ admin mới có thể hủy group plan")
        
        updated_count = Plan.objects.filter(
            pk=plan.pk,
            status__in=['upcoming', 'ongoing']
        ).update(
            status='cancelled',
            updated_at=timezone.now()
        )
        
        if updated_count == 0:
            raise ValueError("Plan đã bị thay đổi bởi user khác")
        
        self.refresh_from_db()
        return True

    @transaction.atomic
    def reorder_activities(self, activity_id_order_pairs, date=None):
        """
        Reorder activities cho một ngày cụ thể, thread-safe
        
        Args:
            activity_id_order_pairs: List of (activity_id, new_order) tuples
            date: Date để reorder (None = reorder all)
            
        Returns:
            int: Số activities được update
            
        Raises:
            ValueError: Nếu có conflicts hoặc invalid data
        """
        # Lock plan để prevent concurrent reordering
        plan = Plan.objects.select_for_update().get(pk=self.pk)
        
        if plan.status in ['cancelled', 'completed']:
            raise ValueError("Không thể reorder activities của plan đã hoàn thành/hủy")
        
        # Validate all activities belong to this plan
        activity_ids = [aid for aid, _ in activity_id_order_pairs]
        activities_qs = plan.activities.filter(id__in=activity_ids)
        
        if date:
            activities_qs = activities_qs.filter(start_time__date=date)
        
        if activities_qs.count() != len(activity_ids):
            raise ValueError("Một số activities không tồn tại hoặc không thuộc plan này")
        
        # Lock activities để prevent concurrent edits
        activities = list(activities_qs.select_for_update())
        activity_dict = {act.id: act for act in activities}
        
        # Validate orders không duplicate
        orders = [order for _, order in activity_id_order_pairs]
        if len(set(orders)) != len(orders):
            raise ValueError("Các order values không được trùng lặp")
        
        # Bulk update với optimized queries
        updates = []
        for activity_id, new_order in activity_id_order_pairs:
            activity = activity_dict[activity_id]
            if activity.order != new_order:
                activity.order = new_order
                updates.append(activity)
        
        if updates:
            PlanActivity.objects.bulk_update(updates, ['order', 'updated_at'])
            
            # Touch plan updated_at
            plan.save(update_fields=['updated_at'])
        
        return len(updates)

    @transaction.atomic  
    def update_activity_safe(self, activity_id, **update_fields):
        """
        Update activity với conflict detection bằng updated_at
        
        Args:
            activity_id: ID của activity
            **update_fields: Fields để update (có thể có 'expected_updated_at')
            
        Returns:
            PlanActivity: Updated activity
            
        Raises:
            ValueError: Nếu có conflicts hoặc validation errors
        """
        # Expected updated_at để optimistic locking
        expected_updated_at = update_fields.pop('expected_updated_at', None)
        
        # Lock cả plan và activity
        plan = Plan.objects.select_for_update().get(pk=self.pk)
        
        try:
            activity = plan.activities.select_for_update().get(id=activity_id)
        except PlanActivity.DoesNotExist:
            raise ValueError("Activity không tồn tại hoặc đã bị xóa")
        
        # Optimistic locking check
        if expected_updated_at and activity.updated_at != expected_updated_at:
            raise ValueError(
                "Activity đã được thay đổi bởi user khác. "
                "Vui lòng refresh và thử lại."
            )
        
        # Validate plan status
        if plan.status in ['cancelled', 'completed']:
            raise ValueError("Không thể sửa activity của plan đã hoàn thành/hủy")
        
        # Time conflict checking (nếu update start/end time)
        if 'start_time' in update_fields or 'end_time' in update_fields:
            new_start = update_fields.get('start_time', activity.start_time)
            new_end = update_fields.get('end_time', activity.end_time)
            
            conflicting = plan.check_activity_overlap(
                new_start, new_end, exclude_id=activity.id
            )
            if conflicting:
                raise ValueError(f"Xung đột thời gian với activity '{conflicting.title}'")
        
        # Apply updates
        for field, value in update_fields.items():
            setattr(activity, field, value)
        
        activity.save()
        
        # Touch plan updated_at
        plan.save(update_fields=['updated_at'])
        
        return activity

    @transaction.atomic
    def delete_activity_safe(self, activity_id, user=None):
        """
        Xóa activity với permission và conflict checking
        """
        plan = Plan.objects.select_for_update().get(pk=self.pk)
        
        if plan.status in ['cancelled', 'completed']:
            raise ValueError("Không thể xóa activity của plan đã hoàn thành/hủy")
        
        try:
            activity = plan.activities.select_for_update().get(id=activity_id)
        except PlanActivity.DoesNotExist:
            raise ValueError("Activity không tồn tại hoặc đã bị xóa")
        
        # Permission check cho group plans
        if user and plan.is_group_plan():
            if not (plan.group.is_admin(user) or activity.created_by == user):
                raise ValueError("Chỉ admin hoặc người tạo mới có thể xóa activity")
        
        activity.delete()
        
        # Touch plan updated_at
        plan.save(update_fields=['updated_at'])
        
        return True


class PlanActivity(BaseModel):
    """
    Model quản lý các hoạt động trong kế hoạch
    Mỗi activity có thời gian, địa điểm và chi phí cụ thể
    """
    
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
        help_text="Kế hoạch chứa hoạt động này"
    )
    
    # Thông tin cơ bản
    title = models.CharField(
        max_length=200,
        help_text="Tên hoạt động"
    )
    
    description = models.TextField(
        blank=True,
        help_text="Mô tả chi tiết hoạt động"
    )
    
    # Loại hoạt động
    activity_type = models.CharField(
        max_length=20,
        choices=ACTIVITY_TYPES,
        default='other',
        db_index=True,
        help_text="Loại hoạt động"
    )
    
    # Thời gian
    start_time = models.DateTimeField(
        help_text="Thời gian bắt đầu hoạt động"
    )
    
    end_time = models.DateTimeField(
        help_text="Thời gian kết thúc hoạt động"
    )
    
    # Thông tin địa điểm
    location_name = models.CharField(
        max_length=200,
        blank=True,
        help_text="Tên địa điểm"
    )
    
    location_address = models.TextField(
        blank=True,
        help_text="Địa chỉ chi tiết"
    )
    
    # Tọa độ GPS
    latitude = models.DecimalField(
        max_digits=9,   # Tổng 9 chữ số
        decimal_places=6,  # 6 chữ số thập phân (độ chính xác ~10cm)
        blank=True, 
        null=True,
        help_text="Vĩ độ"
    )
    
    longitude = models.DecimalField(
        max_digits=9,
        decimal_places=6,
        blank=True, 
        null=True,
        help_text="Kinh độ"
    )
    
    # Goong Map API ID (nếu có)
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
        help_text="Chi phí dự kiến (VND)"
    )
    
    # Ghi chú
    notes = models.TextField(
        blank=True,
        help_text="Ghi chú thêm"
    )
    
    # Thứ tự trong ngày
    order = models.PositiveIntegerField(
        default=0,
        help_text="Thứ tự hoạt động trong ngày"
    )
    
    # Trạng thái hoàn thành
    is_completed = models.BooleanField(
        default=False,
        help_text="Hoạt động đã hoàn thành chưa"
    )
    
    # Version field cho optimistic locking
    version = models.PositiveIntegerField(
        default=1,
        help_text="Version cho conflict detection"
    )
    
    # Remove timestamps vì đã có trong BaseModel

    class Meta:
        db_table = 'planpal_plan_activities'
        ordering = ['start_time', 'order']
        
        indexes = [
            *BaseModel.Meta.indexes,
            # Index cho query activities của plan
            models.Index(fields=['plan', 'start_time']),
            # Index cho query theo loại hoạt động
            models.Index(fields=['activity_type', 'start_time']),
            # Index cho query theo ngày + order
            models.Index(fields=['plan', 'start_time', 'order']),
            # Index cho time conflict detection
            models.Index(fields=['plan', 'start_time', 'end_time']),
        ]

    def __str__(self):
        return f"{self.plan.title} - {self.title} ({self.start_time.strftime('%H:%M')})"

    def clean(self):
        """Validation cho activity với business rules"""
        super().clean()
        
        # Validate thời gian
        if self.start_time and self.end_time:
            if self.end_time <= self.start_time:
                raise ValidationError("Thời gian kết thúc phải sau thời gian bắt đầu")
            
            # Validate duration không quá 24h
            duration = self.end_time - self.start_time
            if duration.total_seconds() > 24 * 3600:
                raise ValidationError("Hoạt động không được dài quá 24 giờ")
        
        # Validate thuộc về plan timeline
        if self.plan_id and self.start_time and self.end_time:
            plan = self.plan
            if self.start_time.date() < plan.start_date.date():
                raise ValidationError("Activity không thể bắt đầu trước ngày bắt đầu plan")
            if self.end_time.date() > plan.end_date.date():
                raise ValidationError("Activity không thể kết thúc sau ngày kết thúc plan")
        
        # Validate location coordinates
        if self.latitude is not None and not (-90 <= self.latitude <= 90):
            raise ValidationError("Vĩ độ phải từ -90 đến 90")
        
        if self.longitude is not None and not (-180 <= self.longitude <= 180):
            raise ValidationError("Kinh độ phải từ -180 đến 180")
        
        # Validate cost
        if self.estimated_cost is not None and self.estimated_cost < 0:
            raise ValidationError("Chi phí không được âm")

    def save(self, *args, **kwargs):
        """Override save để auto-increment version và validate"""
        
        # Increment version cho optimistic locking (chỉ khi update)
        if self.pk:
            self.version = F('version') + 1
        
        # Run full clean before save
        self.clean()
        
        super().save(*args, **kwargs)
        
        # Refresh để lấy version mới sau khi save
        if self.pk:
            self.refresh_from_db(fields=['version'])

    def check_time_conflict(self, exclude_self=True):
        """
        Check xung đột thời gian với activities khác trong plan
        
        Returns:
            QuerySet: Các activities xung đột
        """
        conflicts = self.plan.activities.filter(
            start_time__lt=self.end_time,
            end_time__gt=self.start_time
        )
        
        if exclude_self and self.pk:
            conflicts = conflicts.exclude(pk=self.pk)
        
        return conflicts

    @property
    def duration_minutes(self):
        """Tính thời lượng activity theo phút"""
        if self.start_time and self.end_time:
            return int((self.end_time - self.start_time).total_seconds() / 60)
        return 0

    @property
    def is_today(self):
        """Check xem activity có phải hôm nay không"""
        if self.start_time:
            return self.start_time.date() == timezone.now().date()
        return False

    @property
    def can_complete(self):
        """Check xem có thể đánh dấu hoàn thành không"""
        # Chỉ có thể complete activities trong quá khứ hoặc hiện tại
        return self.start_time <= timezone.now() if self.start_time else False
            
        if self.longitude is not None and not (-180 <= self.longitude <= 180):
            raise ValidationError("Kinh độ phải từ -180 đến 180")

    def save(self, *args, **kwargs):
        """Override save để chạy validation"""
        self.clean()
        super().save(*args, **kwargs)


class ConversationQuerySet(models.QuerySet):
    """Custom QuerySet for Conversation with optimized methods"""
    
    def active(self):
        """Get active conversations"""
        return self.filter(is_active=True)
    
    def for_user(self, user):
        """Get conversations for specific user (both direct and group)"""
        return self.filter(
            Q(conversation_type='direct', participants=user) |
            Q(conversation_type='group', group__members=user)
        ).distinct()
    
    def direct_chats(self):
        """Get only direct (1-1) conversations"""
        return self.filter(conversation_type='direct')
    
    def group_chats(self):
        """Get only group conversations"""
        return self.filter(conversation_type='group')
    
    def with_last_message(self):
        """Annotate with last message info - OPTIMIZED"""
        # Subquery to get the latest message for each conversation
        last_message_subquery = ChatMessage.objects.filter(
            conversation=OuterRef('pk'),
            is_deleted=False
        ).order_by('-created_at')
        
        return self.annotate(
            last_message_time=Subquery(last_message_subquery.values('created_at')[:1]),
            last_message_content=Subquery(last_message_subquery.values('content')[:1]),
            last_message_sender_id=Subquery(last_message_subquery.values('sender_id')[:1])
        ).select_related('group').prefetch_related('participants')
    
    def get_direct_conversation(self, user1, user2):
        """Get direct conversation between two users"""
        return self.direct_chats().filter(
            participants=user1
        ).filter(
            participants=user2
        ).first()


class Conversation(BaseModel):
    """
    Model quản lý cuộc trò chuyện - hỗ trợ cả chat 1-1 và group chat
    Tương tự như Messenger/Zalo conversation list
    """
    
    CONVERSATION_TYPES = [
        ('direct', 'Chat 1-1'),
        ('group', 'Chat nhóm'),
    ]
    
    conversation_type = models.CharField(
        max_length=10,
        choices=CONVERSATION_TYPES,
        db_index=True,
        help_text="Loại cuộc trò chuyện"
    )
    
    # For group conversations
    group = models.OneToOneField(
        Group,
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name='conversation',
        help_text="Nhóm (chỉ cho group chat)"
    )
    
    # For direct conversations (many-to-many for flexibility)
    participants = models.ManyToManyField(
        User,
        related_name='conversations',
        help_text="Người tham gia (cho chat 1-1: 2 users, group: auto sync từ group members)"
    )
    
    # Conversation metadata
    name = models.CharField(
        max_length=200,
        blank=True,
        help_text="Tên cuộc trò chuyện (auto-generate nếu để trống)"
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
        help_text="Avatar cuộc trò chuyện"
    )
    
    # Denormalized fields for performance
    last_message_at = models.DateTimeField(
        null=True,
        blank=True,
        db_index=True,
        help_text="Thời gian tin nhắn cuối cùng (denormalized)"
    )
    
    is_active = models.BooleanField(
        default=True,
        db_index=True,
        help_text="Cuộc trò chuyện có đang hoạt động không"
    )
    
    # Custom manager
    objects = ConversationQuerySet.as_manager()

    class Meta:
        db_table = 'planpal_conversations'
        indexes = [
            *BaseModel.Meta.indexes,
            models.Index(fields=['conversation_type', 'is_active']),
            models.Index(fields=['last_message_at']),
            models.Index(fields=['is_active', 'last_message_at']),
        ]

    def __str__(self):
        if self.conversation_type == 'group' and self.group:
            return f"Group: {self.group.name}"
        elif self.conversation_type == 'direct':
            participants = list(self.participants.all()[:2])
            if len(participants) == 2:
                return f"Direct: {participants[0].username} & {participants[1].username}"
        return f"Conversation {self.id}"

    def clean(self):
        """Validation for conversation"""
        if self.conversation_type == 'group' and not self.group:
            raise ValidationError("Group conversation phải có group")
        
        if self.conversation_type == 'direct' and self.group:
            raise ValidationError("Direct conversation không được có group")

    def save(self, *args, **kwargs):
        self.clean()
        super().save(*args, **kwargs)
        
        # Auto-generate name if empty
        if not self.name:
            self._auto_generate_name()

    def _auto_generate_name(self):
        """Auto-generate conversation name"""
        if self.conversation_type == 'group' and self.group:
            self.name = self.group.name
        elif self.conversation_type == 'direct':
            participants = list(self.participants.all()[:2])
            if len(participants) == 2:
                self.name = f"{participants[0].get_full_name()} & {participants[1].get_full_name()}"
        
        if self.name and self.pk:
            Conversation.objects.filter(pk=self.pk).update(name=self.name)

    # === Properties ===
    
    @property
    def avatar_url(self):
        """Get conversation avatar URL"""
        if self.avatar:
            cloudinary_image = CloudinaryImage(str(self.avatar))
            return cloudinary_image.build_url(secure=True)
        
        # Fallback to group avatar for group conversations
        if self.conversation_type == 'group' and self.group and self.group.avatar:
            return self.group.avatar_url
        
        return None

    @property
    def display_name(self):
        """Get display name for conversation"""
        if self.name:
            return self.name
        
        if self.conversation_type == 'group' and self.group:
            return self.group.name
        
        # For direct chat, show other participant's name
        participants = list(self.participants.all()[:2])
        if len(participants) == 2:
            return f"{participants[0].get_full_name()} & {participants[1].get_full_name()}"
        
        return "Cuộc trò chuyện"

    def get_other_participant(self, user):
        """Get the other participant in direct conversation"""
        if self.conversation_type != 'direct':
            return None
        
        participants = self.participants.exclude(id=user.id)
        return participants.first()

    @property
    def participant_count(self):
        """Get number of participants"""
        if self.conversation_type == 'group' and self.group:
            return self.group.member_count
        return self.participants.count()

    # === Methods ===
    
    def send_message(self, sender, content, message_type='text', **kwargs):
        """Send message to conversation"""
        message = ChatMessage.objects.create(
            conversation=self,
            sender=sender,
            content=content,
            message_type=message_type,
            **kwargs
        )
        
        # Update last_message_at automatically handled in ChatMessage.save()
        return message

    def update_last_message_time(self, timestamp=None):
        """Update denormalized last_message_at field"""
        if timestamp is None:
            timestamp = timezone.now()
        
        self.last_message_at = timestamp
        self.save(update_fields=['last_message_at'])

    def get_unread_count_for_user(self, user):
        """Get unread message count for specific user"""
        return self.messages.active().exclude(
            Q(sender=user) | Q(read_statuses__user=user)
        ).count()

    def mark_as_read_for_user(self, user, up_to_message=None):
        """Mark messages as read for user"""
        messages = self.messages.active().exclude(sender=user)
        
        if up_to_message:
            messages = messages.filter(created_at__lte=up_to_message.created_at)
        
        # Get unread message IDs
        unread_message_ids = messages.exclude(
            read_statuses__user=user
        ).values_list('id', flat=True)
        
        # Bulk create read statuses
        if unread_message_ids:
            read_statuses = [
                MessageReadStatus(message_id=msg_id, user=user)
                for msg_id in unread_message_ids
            ]
            MessageReadStatus.objects.bulk_create(read_statuses, ignore_conflicts=True)

    # === Class Methods ===
    
    @classmethod
    def get_or_create_direct_conversation(cls, user1, user2):
        """Get or create direct conversation between two users"""
        if user1 == user2:
            raise ValueError("Cannot create conversation with yourself")
        
        # Try to find existing conversation
        conversation = cls.objects.get_direct_conversation(user1, user2)
        
        if conversation:
            return conversation, False
        
        # Create new direct conversation
        conversation = cls.objects.create(conversation_type='direct')
        conversation.participants.add(user1, user2)
        conversation._auto_generate_name()
        
        return conversation, True

    @classmethod
    def create_group_conversation(cls, group):
        """Create conversation for group"""
        conversation = cls.objects.create(
            conversation_type='group',
            group=group,
            name=group.name
        )
        
        # Sync participants with group members
        conversation.sync_group_participants()
        
        return conversation

    @classmethod
    def get_or_create_for_group(cls, group):
        """Get or create conversation for existing group (migration helper)"""
        try:
            return group.conversation, False
        except cls.DoesNotExist:
            return cls.create_group_conversation(group), True

    def sync_group_participants(self):
        """Sync participants with group members (for group conversations)"""
        if self.conversation_type != 'group' or not self.group:
            return
        
        # Clear and re-add all group members
        self.participants.clear()
        self.participants.add(*self.group.members.all())


class ChatMessageQuerySet(models.QuerySet):
    """Custom QuerySet for ChatMessage with optimized methods"""
    
    def active(self):
        """Filter non-deleted messages"""
        return self.filter(is_deleted=False)
    
    def for_conversation(self, conversation):
        """Filter messages for specific conversation"""
        return self.filter(conversation=conversation)
    
    def for_user(self, user):
        """Filter messages sent by specific user"""
        return self.filter(sender=user)
    
    def recent(self, limit=50):
        """Get recent messages with limit"""
        return self.order_by('-created_at')[:limit]
    
    def with_read_status(self, user):
        """Annotate with read status for specific user"""
        return self.annotate(
            is_read_by_user=Exists(
                MessageReadStatus.objects.filter(
                    message=OuterRef('pk'),
                    user=user
                )
            )
        )
    
    def unread_for_user(self, user):
        """Filter unread messages for user"""
        return self.active().exclude(sender=user).exclude(
            Exists(
                MessageReadStatus.objects.filter(
                    message=OuterRef('pk'),
                    user=user
                )
            )
        )
    
    def by_type(self, message_type):
        """Filter by message type"""
        return self.filter(message_type=message_type)
    
    def with_attachments(self):
        """Filter messages with attachments"""
        return self.exclude(attachment='')
    """Custom QuerySet for ChatMessage"""
    
    def active(self):
        return self.filter(is_deleted=False)
    
    def for_conversation(self, conversation):
        return self.filter(conversation=conversation)
    
    def for_group(self, group):
        """DEPRECATED: Use for_conversation instead"""
        return self.filter(group=group)
    
    def by_user(self, user):
        return self.filter(sender=user)
    
    def text_messages(self):
        return self.filter(message_type='text')
    
    def system_messages(self):
        return self.filter(message_type='system')
    
    def with_attachments(self):
        return self.exclude(attachment='')
    
    def recent(self, limit=50):
        return self.order_by('-created_at')[:limit]


class ChatMessage(BaseModel):
    """
    Model quản lý tin nhắn trong conversation (cả 1-1 và group chat)
    Hỗ trợ text, image, file attachments
    """
    
    # Loại tin nhắn
    MESSAGE_TYPES = [
        ('text', 'Văn bản'),
        ('image', 'Hình ảnh'),
        ('file', 'File đính kèm'),
        ('location', 'Vị trí'),
        ('system', 'Thông báo hệ thống'),
    ]
    
    # Thuộc về conversation nào
    conversation = models.ForeignKey(
        Conversation,
        on_delete=models.CASCADE,
        related_name='messages',
        null=True,  # Keep nullable to handle existing messages
        blank=True,
        help_text="Cuộc trò chuyện chứa tin nhắn này"
    )
    
    # DEPRECATED: Keep for backward compatibility, will be removed later
    group = models.ForeignKey(
        Group,
        on_delete=models.CASCADE,
        related_name='legacy_messages',
        null=True,
        blank=True,
        help_text="DEPRECATED: Sử dụng conversation thay thế"
    )
    
    # Người gửi tin nhắn
    sender = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='sent_messages',
        null=True,  # Null cho system messages
        blank=True,
        help_text="Người gửi tin nhắn"
    )
    
    # Loại tin nhắn
    message_type = models.CharField(
        max_length=20,
        choices=MESSAGE_TYPES,
        default='text',
        db_index=True,
        help_text="Loại tin nhắn"
    )
    
    # Nội dung tin nhắn
    content = models.TextField(
        help_text="Nội dung tin nhắn"
    )
    
    # File đính kèm với Cloudinary
    attachment = CloudinaryField(
        'auto',  # auto: support both image and raw files
        blank=True,
        null=True,
        folder='planpal/messages/attachments',
        resource_type='auto',  # auto detect file type
        help_text="File đính kèm (hình ảnh, document)"
    )
    
    # Metadata cho file
    attachment_name = models.CharField(
        max_length=255,
        blank=True,
        help_text="Tên gốc của file"
    )
    
    attachment_size = models.PositiveIntegerField(
        blank=True,
        null=True,
        help_text="Kích thước file (bytes)"
    )
    
    # Location data (cho message type = location)
    latitude = models.DecimalField(
        max_digits=9,
        decimal_places=6,
        blank=True,
        null=True,
        help_text="Vĩ độ của location"
    )
    
    longitude = models.DecimalField(
        max_digits=9,
        decimal_places=6,
        blank=True,
        null=True,
        help_text="Kinh độ của location"
    )
    
    location_name = models.CharField(
        max_length=200,
        blank=True,
        help_text="Tên địa điểm"
    )
    
    # Reply to message (threading)
    reply_to = models.ForeignKey(
        'self',
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name='replies',
        help_text="Tin nhắn được reply"
    )
    
    # Message status
    is_edited = models.BooleanField(
        default=False,
        help_text="Tin nhắn đã được chỉnh sửa"
    )
    
    is_deleted = models.BooleanField(
        default=False,
        db_index=True,
        help_text="Tin nhắn đã bị xóa (soft delete)"
    )
    
    # Remove timestamps vì đã có trong BaseModel
    
    # Custom manager - use QuerySet.as_manager()
    objects = ChatMessageQuerySet.as_manager()

    class Meta:
        db_table = 'planpal_chat_messages'
        ordering = ['created_at']
        
        indexes = [
            *BaseModel.Meta.indexes,
            # NEW: Index cho conversation (primary)
            models.Index(fields=['conversation', 'created_at']),
            models.Index(fields=['conversation', 'is_deleted', 'created_at']),
            # LEGACY: Index cho group (backward compatibility)
            models.Index(fields=['group', 'created_at']),
            models.Index(fields=['group', 'is_deleted', 'created_at']),
            # Index cho query messages của user
            models.Index(fields=['sender', 'created_at']),
            # Index cho query theo type
            models.Index(fields=['message_type', 'created_at']),
        ]

    def __str__(self):
        if self.conversation:
            location = f"in {self.conversation.display_name}"
        elif self.group:
            location = f"in {self.group.name} (legacy)"
        else:
            location = "unknown location"
            
        if self.sender:
            return f"{self.sender.username} {location}: {self.content[:50]}..."
        return f"System message {location}: {self.content[:50]}..."

    def clean(self):
        """Validation cho message"""
        
        # System messages không cần sender
        if self.message_type == 'system' and self.sender is not None:
            raise ValidationError("System message không được có sender")
        
        # Non-system messages cần sender
        if self.message_type != 'system' and self.sender is None:
            raise ValidationError("Message cần có sender")
        
        # Location messages cần coordinates
        if self.message_type == 'location':
            if not (self.latitude and self.longitude):
                raise ValidationError("Location message cần có coordinates")

    @property
    def is_text_message(self):
        """Check xem có phải text message không"""
        return self.message_type == 'text'

    @property
    def is_image_message(self):
        """Check xem có phải image message không"""
        return self.message_type == 'image'

    @property
    def is_file_message(self):
        """Check xem có phải file message không"""
        return self.message_type == 'file'

    @property
    def is_location_message(self):
        """Check xem có phải location message không"""
        return self.message_type == 'location'

    @property
    def has_attachment(self):
        """Check xem có attachment không"""
        return bool(self.attachment)

    def soft_delete(self):
        """Soft delete message"""
        self.is_deleted = True
        self.content = "[Tin nhắn đã bị xóa]"
        self.save(update_fields=['is_deleted', 'content', 'updated_at'])

    def save(self, *args, **kwargs):
        """Override save để update conversation last_message_at và clear caches"""
        # First call clean if not called yet
        if not hasattr(self, '_clean_called'):
            self.clean()
            self._clean_called = True
            
        super().save(*args, **kwargs)
        
        # Update conversation's last_message_at (denormalized field)
        if self.conversation and not self.is_deleted:
            self.conversation.update_last_message_time(self.created_at)
        
        # Clear unread cache for conversation participants
        if self.conversation:
            participant_ids = list(self.conversation.participants.values_list('id', flat=True))
            User.clear_unread_cache_for_users(participant_ids)

    @classmethod
    def create_system_message(cls, conversation=None, group=None, content=""):
        """
        Tạo system message cho conversation hoặc group (legacy)
        
        Args:
            conversation: Conversation instance (preferred)
            group: Group instance (legacy, for backward compatibility)
            content: Nội dung thông báo
        """
        if conversation:
            return cls.objects.create(
                conversation=conversation,
                sender=None,
                message_type='system',
                content=content
            )
        elif group:
            # Legacy support - find or create conversation for group
            group_conversation, _ = Conversation.get_or_create_for_group(group)
            return cls.objects.create(
                conversation=group_conversation,
                group=group,  # Keep for backward compatibility
                sender=None,
                message_type='system',
                content=content
            )
        else:
            raise ValueError("Either conversation or group must be provided")


class MessageReadStatus(BaseModel):
    """
    Model theo dõi trạng thái đã đọc của tin nhắn
    Để hiển thị tin nhắn chưa đọc
    """
    
    # Remove id field vì đã có trong BaseModel
    
    # Message được đọc
    message = models.ForeignKey(
        ChatMessage,
        on_delete=models.CASCADE,
        related_name='read_statuses',
        help_text="Tin nhắn được đọc"
    )
    
    # User đã đọc
    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='message_read_statuses',
        help_text="User đã đọc tin nhắn"
    )
    
    # Thời gian đọc
    read_at = models.DateTimeField(
        auto_now_add=True,
        help_text="Thời gian đọc tin nhắn"
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

    def __str__(self):
        return f"{self.user.username} read message {self.message.id}"
