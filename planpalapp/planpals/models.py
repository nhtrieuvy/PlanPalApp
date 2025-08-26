from django.db import models
from django.contrib.auth.models import AbstractUser
from django.utils import timezone
from django.core.validators import RegexValidator
from django.core.exceptions import ValidationError
from django.db.models import Q
from cloudinary.models import CloudinaryField
from cloudinary import CloudinaryImage
from collections import defaultdict
import uuid

class BaseModel(models.Model):
    """
    Abstract base model với các fields và patterns chung
    Tất cả models khác sẽ kế thừa từ đây
    """
    
    # UUID primary key cho tất cả models
    id = models.UUIDField(
        primary_key=True,
        default=uuid.uuid4,
        editable=False,
        help_text="Unique identifier"
    )
    
    # Timestamps tự động
    created_at = models.DateTimeField(
        auto_now_add=True,
        db_index=True,
        help_text="Thời gian tạo"
    )
    
    updated_at = models.DateTimeField(
        auto_now=True,
        help_text="Thời gian cập nhật cuối"
    )

    class Meta:
        abstract = True  # Không tạo table riêng
        ordering = ['-created_at']  # Default ordering
        
        # Base indexes cho timestamps
        indexes = [
            models.Index(fields=['created_at']),
            models.Index(fields=['updated_at']),
        ]

    def save(self, *args, **kwargs):
        """Override save để chạy validation"""
        self.full_clean()  # Chạy tất cả validations
        super().save(*args, **kwargs)

    def __str__(self):
        """Default string representation"""
        return f"{self.__class__.__name__}({self.id})"


class User(AbstractUser, BaseModel):
    """
    Custom User model kế thừa từ AbstractUser và BaseModel
    """
    
    # Remove id field vì đã có trong BaseModel
    
    # Phone number với validation
    phone_regex = RegexValidator(
        regex=r'^\+?1?\d{9,15}$', # Có thể có dấu +, số 1 ở đầu và từ 9 đến 15 số
        message="Phone number phải có format: '+999999999'. Tối đa 15 số."
    )
    phone_number = models.CharField(
        validators=[phone_regex], 
        max_length=17, 
        blank=True,
        help_text="Số điện thoại với mã quốc gia"
    )
    
    # Avatar với Cloudinary
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
        help_text="Ảnh đại diện người dùng"
    )
    

    date_of_birth = models.DateField(
        blank=True, 
        null=True,
        help_text="Ngày sinh của người dùng"
    )
    
    bio = models.TextField(
        max_length=500, 
        blank=True,
        help_text="Giới thiệu bản thân (tối đa 500 ký tự)"
    )
    
    
    is_online = models.BooleanField(
        default=False,
        db_index=True, 
        help_text="Trạng thái online của user"
    )
    
    last_seen = models.DateTimeField(
        default=timezone.now,
        db_index=True,
        help_text="Lần cuối user online"
    )
    
    
    fcm_token = models.CharField(
        max_length=255, 
        blank=True,
        help_text="Firebase Cloud Messaging token"
    )
    
    

    class Meta:
        db_table = 'planpal_users' 
        ordering = ['-created_at']  # Override BaseModel ordering
        indexes = [
            # Kế thừa base indexes từ BaseModel và thêm custom
            *BaseModel.Meta.indexes,
            models.Index(fields=['first_name', 'last_name']), #Tạo chỉ mục khi tìm kiếm theo tên đầy đủ
            models.Index(fields=['is_online', 'last_seen']), #Tạo chi chỉ mục cho trạng thái online và thời gian cuối cùng online
        ]

    def __str__(self):
        return f"{self.username} ({self.get_full_name()})"

    @property
    def display_name(self):
        """Tên hiển thị ưu tiên full name, fallback username"""
        full_name = f"{self.first_name} {self.last_name}".strip()
        return full_name if full_name else self.username

    @property
    def initials(self):
        """Lấy chữ cái đầu của tên để hiển thị avatar"""
        if self.first_name and self.last_name:
            return f"{self.first_name[0]}{self.last_name[0]}".upper()
        elif self.first_name:
            return self.first_name[0].upper()
        return self.username[0].upper() if self.username else "U"


    def update_last_seen(self):
        """Update last_seen timestamp"""
        self.last_seen = timezone.now()
        self.save(update_fields=['last_seen'])

    def set_online_status(self, status):
        """Set online status và update last_seen"""
        self.is_online = status
        if not status:  # Khi offline, update last_seen
            self.last_seen = timezone.now()
        self.save(update_fields=['is_online', 'last_seen'])

    def create_personal_plan(self, title, start_date, end_date, **kwargs):
        """
        Tạo kế hoạch cá nhân
        
        Args:
            title: Tiêu đề kế hoạch
            start_date, end_date: Thời gian chuyến đi
            **kwargs: Các field khác
        """
        plan = Plan.objects.create(
            creator=self,
            title=title,
            start_date=start_date,
            end_date=end_date,
            group=None,  # Personal plan không có group
            plan_type='personal',
            **kwargs
        )
        return plan

    def create_group_plan(self, group, title, start_date, end_date, **kwargs):
        """
        Tạo kế hoạch nhóm
        """
        return Plan.objects.create(
        group=group,
        creator=self,
        title=title,
        start_date=start_date,
        end_date=end_date,
        plan_type='group',
        **kwargs
    )

    
        
    def send_group_message(self, group, content, message_type='text', **kwargs):
        """
        Gửi tin nhắn vào group
        """
        return group.send_message(
            sender=self,
            content=content,
            message_type=message_type,
            **kwargs
        )

    # ✅ QUERY PROPERTIES - Trả về QuerySet để truy vấn
    @property
    def recent_conversations(self):
        """Lấy danh sách conversations gần đây - OPTIMIZED"""
        return Group.objects.filter(
            members=self,
            is_active=True
        ).annotate(
            last_message_time=models.Max('messages__created_at')
        ).order_by('-last_message_time').select_related('admin')
        
    @property
    def personal_plans(self):
        """Lấy tất cả personal plans của user"""
        return self.created_plans.filter(
            plan_type='personal'
        ).order_by('-created_at')

    @property
    def group_plans(self):
        """Lấy tất cả group plans mà user tham gia"""
        return Plan.objects.filter(
            group__members=self,
            plan_type='group'
        ).order_by('-created_at')

    @property
    def all_plans(self):
        """Lấy tất cả plans (personal + group)"""
        return Plan.objects.filter(
            Q(creator=self, plan_type='personal') |
            Q(group__members=self, plan_type='group')
        ).order_by('-created_at')

    @property
    def viewable_plans(self):
        """Lấy tất cả plans mà user có thể xem (bao gồm public)"""
        return Plan.objects.filter(
            Q(creator=self) |  # Own plans
            Q(group__members=self) |  # Group plans
            Q(is_public=True)  # Public plans
        ).distinct().order_by('-created_at')

    @property
    def friends(self):
        """Lấy danh sách bạn bè của user"""
        return Friendship.get_friends_queryset(self)

    # ✅ COUNT PROPERTIES - Tính toán và đếm
    @property
    def plans_count(self):
        """Tổng số kế hoạch (personal + group)"""
        return self.all_plans.count()

    @property
    def personal_plans_count(self):
        """Số lượng kế hoạch cá nhân"""
        return self.personal_plans.count()

    @property
    def group_plans_count(self):
        """Số lượng kế hoạch nhóm"""
        return self.group_plans.count()

    @property
    def groups_count(self):
        """Tổng số nhóm mà user tham gia"""
        return self.joined_groups.filter(is_active=True).count()

    @property
    def friends_count(self):
        """Tổng số bạn bè của user"""
        return self.friends.count()
        
    # ✅ STATUS AND VALIDATION PROPERTIES
    @property
    def is_recently_online(self):
        """Check xem user có online trong 5 phút gần đây không"""
        if self.is_online:
            return True
        return timezone.now() - self.last_seen < timezone.timedelta(minutes=5)
    
    @property
    def online_status(self):
        """Trả về trạng thái online: 'online', 'recently_online', 'offline'"""
        if self.is_online:
            return 'online'
        elif self.is_recently_online:
            return 'recently_online'
        return 'offline'

    @property
    def has_avatar(self):
        """Check xem user có avatar không"""
        return bool(self.avatar)

    @property
    def avatar_url(self):
        """Lấy URL avatar đầy đủ Cloudinary, fallback về initials nếu không có"""
        # If user does not have an avatar, return None so frontend can
        # render initials/text fallback instead of treating the value as a URL.
        if not self.has_avatar:
            return None
        # Sử dụng CloudinaryImage để tạo URL đầy đủ
        if self.avatar:
            cloudinary_image = CloudinaryImage(str(self.avatar))
            return cloudinary_image.build_url(secure=True)
        return None

    @property
    def avatar_thumb(self):
        """Thumbnail cho avatar (dùng trong summary/list)"""
        if not self.avatar:
            return None
        # Sử dụng CloudinaryImage để tạo thumbnail
        cloudinary_image = CloudinaryImage(str(self.avatar))
        return cloudinary_image.build_url(width=100, height=100, crop='fill', gravity='face', secure=True)

    @property
    def unread_messages_count(self):
        """Tổng số tin nhắn chưa đọc trong tất cả groups - OPTIMIZED"""
        from django.db.models import Count, Q
        
        # Single query to count unread messages across all groups
        return ChatMessage.objects.filter(
            group__members=self,
            group__is_active=True,
            is_deleted=False
        ).exclude(
            Q(sender=self) | Q(read_statuses__user=self)
        ).count()
    

class Friendship(BaseModel):
    """
    Optimized Friendship model với consistent naming
    Sử dụng pattern: user -> friend với status
    """
    
    # Các trạng thái của lời mời kết bạn
    PENDING = 'pending'
    ACCEPTED = 'accepted'
    REJECTED = 'rejected'
    BLOCKED = 'blocked'
    
    STATUS_CHOICES = [
        (PENDING, 'Đang chờ'),
        (ACCEPTED, 'Đã chấp nhận'),
        (REJECTED, 'Đã từ chối'),
        (BLOCKED, 'Đã chặn'),
    ]
    
    # ✅ CONSISTENT NAMING - user/friend instead of sender/receiver
    user = models.ForeignKey(
        User, 
        on_delete=models.CASCADE,
        related_name='sent_friendships',
        help_text="User who sent the friend request"
    )
    
    friend = models.ForeignKey(
        User, 
        on_delete=models.CASCADE,
        related_name='received_friendships',
        help_text="User who received the friend request"
    )
    
    status = models.CharField(
        max_length=20, 
        choices=STATUS_CHOICES, 
        default=PENDING,
        db_index=True,
        help_text="Trạng thái lời mời kết bạn"
    )

    class Meta:
        db_table = 'planpal_friendships'
        unique_together = ('user', 'friend')
        indexes = [
            *BaseModel.Meta.indexes,
            # ✅ OPTIMIZED INDEXES for common queries
            models.Index(fields=['user', 'status']),
            models.Index(fields=['friend', 'status']),
            models.Index(fields=['status', 'created_at']),
            # ✅ COMPOSITE INDEX for friendship checks
            models.Index(fields=['user', 'friend', 'status']),
        ]

    def __str__(self):
        return f"{self.user.username} -> {self.friend.username} ({self.get_status_display()})"

    def clean(self):
        """Validate friendship data"""
        if self.user == self.friend:
            raise ValidationError("Không thể gửi lời mời kết bạn cho chính mình")

    @classmethod
    def _validate_friend_request(cls, user, friend):
        """Private method for friend request validation"""
        if user == friend:
            raise ValidationError("Không thể gửi lời mời kết bạn cho chính mình")

    def save(self, *args, **kwargs):
        self.clean()
        super().save(*args, **kwargs)

    # ✅ OPTIMIZED CLASS METHODS
    @classmethod
    def get_friendship_status(cls, user1, user2):
        """Get friendship status between two users - SINGLE QUERY"""
        try:
            friendship = cls.objects.select_related('user', 'friend').get(
                models.Q(user=user1, friend=user2) | 
                models.Q(user=user2, friend=user1)
            )
            return friendship.status
        except cls.DoesNotExist:
            return None
    
    @classmethod
    def are_friends(cls, user1, user2):
        """Check if users are friends - OPTIMIZED SINGLE QUERY"""
        return cls.objects.filter(
            models.Q(user=user1, friend=user2) | 
            models.Q(user=user2, friend=user1),
            status=cls.ACCEPTED
        ).exists()
    
    @classmethod
    def get_friends_queryset(cls, user):
        """Get friends queryset - OPTIMIZED with single query"""
        # Use EXISTS subquery instead of subquery with values_list for better performance
        friend_ids = cls.objects.filter(
            Q(user=user, status=cls.ACCEPTED) | Q(friend=user, status=cls.ACCEPTED)
        ).values_list(
            models.Case(
                models.When(user=user, then='friend_id'),
                default='user_id',
                output_field=models.UUIDField()
            ),
            flat=True
        )
        
        return User.objects.filter(id__in=friend_ids)

    @classmethod
    def get_pending_requests(cls, user):
        """Lấy các lời mời kết bạn đang chờ - OPTIMIZED"""
        return cls.objects.filter(
            friend=user,
            status=cls.PENDING
        ).select_related('user').order_by('-created_at')

    @classmethod
    def get_sent_requests(cls, user):
        """Lấy các lời mời đã gửi - OPTIMIZED"""
        return cls.objects.filter(
            user=user,
            status=cls.PENDING
        ).select_related('friend').order_by('-created_at')

    # ✅ OPTIMIZED INSTANCE METHODS
    def accept(self):
        """Accept friend request"""
        if self.status == self.PENDING:
            self.status = self.ACCEPTED
            self.save(update_fields=['status', 'updated_at'])
            return True
        return False

    def reject(self):
        """Reject friend request"""
        if self.status == self.PENDING:
            self.status = self.REJECTED
            self.save(update_fields=['status', 'updated_at'])
            return True
        return False

    def block(self):
        """Block user"""
        self.status = self.BLOCKED
        self.save(update_fields=['status', 'updated_at'])

    @classmethod
    def create_friend_request(cls, user, friend):
        """Create friend request - FIXED duplicate logic"""
        # Use centralized validation
        cls._validate_friend_request(user, friend)
        
        # FIXED: Check existing friendship in both directions first
        existing_friendship = cls.get_friendship(user, friend)
        
        if existing_friendship:
            # Handle existing friendship
            if existing_friendship.status == cls.REJECTED:
                # Allow re-sending after rejection
                existing_friendship.status = cls.PENDING
                existing_friendship.save(update_fields=['status', 'updated_at'])
                return existing_friendship, False
            else:
                # Return existing friendship
                return existing_friendship, False
        
        # Create new friendship request (user -> friend direction)
        friendship = cls.objects.create(
            user=user,
            friend=friend,
            status=cls.PENDING
        )
        
        return friendship, True

    @classmethod
    def get_friendship(cls, user1, user2):
        """
        Get friendship object between 2 users - OPTIMIZED SINGLE QUERY
        
        Returns:
            Friendship object or None
        """
        try:
            return cls.objects.select_related('user', 'friend').get(
                models.Q(user=user1, friend=user2) | 
                models.Q(user=user2, friend=user1)
            )
        except cls.DoesNotExist:
            return None

class GroupQuerySet(models.QuerySet):
    """Custom QuerySet for Group with optimized methods"""
    
    def with_member_count(self):
        """Annotate with member count"""
        return self.annotate(
            member_count_annotated=models.Count('members', distinct=True)
        )
    
    def with_admin_count(self):
        """Annotate with admin count"""
        return self.annotate(
            admin_count_annotated=models.Count(
                'memberships', 
                filter=models.Q(memberships__role=GroupMembership.ADMIN),
                distinct=True
            )
        )
    
    def active(self):
        """Filter active groups"""
        return self.filter(is_active=True)
    
    def for_user(self, user):
        """Filter groups for specific user"""
        return self.filter(members=user)


class GroupManager(models.Manager):
    """Custom Manager for Group"""
    
    def get_queryset(self):
        return GroupQuerySet(self.model, using=self._db)
    
    def with_member_count(self):
        return self.get_queryset().with_member_count()
    
    def with_admin_count(self):
        return self.get_queryset().with_admin_count()
    
    def active(self):
        return self.get_queryset().active()
    
    def for_user(self, user):
        return self.get_queryset().for_user(user)


class Group(BaseModel):
    """
    Model quản lý nhóm du lịch
    Một nhóm có thể có nhiều thành viên và nhiều kế hoạch
    """
    
    # Remove id field vì đã có trong BaseModel
    
    # Thông tin cơ bản của nhóm
    name = models.CharField(
        max_length=100,
        help_text="Tên nhóm du lịch"
    )
    
    description = models.TextField(
        blank=True,
        help_text="Mô tả về nhóm"
    )
    
    # Avatar cho nhóm với Cloudinary (display nhỏ)
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
        help_text="Ảnh đại diện nhóm"
    )
    
    # Cover image cho nhóm với Cloudinary (header lớn)
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
        help_text="Ảnh bìa của nhóm"
    )

    
    # Admin của nhóm (người tạo)
    admin = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='administered_groups',
        help_text="Người quản trị nhóm"
    )
    
    # Many-to-Many relationship với User thông qua GroupMembership
    members = models.ManyToManyField(
        User,
        through='GroupMembership',
        related_name='joined_groups',
        help_text="Các thành viên trong nhóm"
    )
    
    # Trạng thái nhóm
    is_active = models.BooleanField(
        default=True,
        db_index=True,
        help_text="Nhóm có đang hoạt động không"
    )
    
    # Remove timestamps vì đã có trong BaseModel
    
    # Custom manager
    objects = GroupManager()

    class Meta:
        db_table = 'planpal_groups'
        
        indexes = [
            *BaseModel.Meta.indexes,
            # Index cho tìm kiếm groups của admin
            models.Index(fields=['admin', 'is_active']),
            # Index cho tìm kiếm groups theo thời gian
            models.Index(fields=['is_active', 'created_at']),
        ]

    def __str__(self):
        return f"{self.name} (Admin: {self.admin.username})"

    def save(self, *args, **kwargs):
        """Override save để auto-add admin membership và validate"""
        # Check if this is a new instance by looking at _state.adding
        is_new = self._state.adding
        
        super().save(*args, **kwargs)
        
        # Auto-add admin as member on create
        if is_new and self.admin:
            GroupMembership.objects.get_or_create(
                group=self,
                user=self.admin,
                defaults={'role': GroupMembership.ADMIN}
            )

    # -------- AVATAR PROPERTIES --------
    @property
    def has_avatar(self):
        return bool(self.avatar)

    @property
    def avatar_url(self):
        """Avatar URL đầy đủ (ưu tiên cho display nhỏ)"""
        if not self.avatar:
            return None
        cloudinary_image = CloudinaryImage(str(self.avatar))
        return cloudinary_image.build_url(width=300, height=300, crop='fill', gravity='face', secure=True)

    @property
    def avatar_thumb(self):
        """Avatar thumbnail (dùng trong list/card)"""
        if not self.avatar:
            return None
        cloudinary_image = CloudinaryImage(str(self.avatar))
        return cloudinary_image.build_url(width=100, height=100, crop='fill', gravity='face', secure=True)

    # -------- COVER IMAGE PROPERTIES --------
    @property
    def has_cover_image(self):
        return bool(self.cover_image)

    @property
    def cover_image_url(self):
        """Cover image URL đầy đủ (chất lượng bình thường)"""
        if not self.cover_image:
            return None
        # Sử dụng CloudinaryImage để tạo URL đầy đủ
        cloudinary_image = CloudinaryImage(str(self.cover_image))
        return cloudinary_image.build_url(width=1200, height=600, crop='fill', gravity='center', secure=True)

    
    @property
    def initials(self):
        """Lấy chữ cái viết tắt (initials) từ tên nhóm để hiển thị avatar.

        - Nếu tên nhóm có >= 2 từ thì lấy chữ cái đầu của hai từ đầu.
        - Nếu chỉ có 1 từ thì lấy hai ký tự đầu của từ đó (hoặc 1 ký tự nếu tên chỉ có 1 ký tự).
        - Nếu không có tên, trả về 'G' làm fallback.
        """
        if not self.name:
            return 'G'

        parts = [p for p in self.name.split() if p]
        if len(parts) >= 2:
            return (parts[0][0] + parts[1][0]).upper()

        # Single word: take up to first two characters
        return self.name[:2].upper()
    
    @property
    def member_count(self):
        """Đếm số thành viên trong nhóm - OPTIMIZED"""
        # Use annotated value if available, fallback to count()
        if hasattr(self, 'member_count_annotated'):
            return self.member_count_annotated
        return self.members.count()

    @property
    def plans_count(self):
        """Đếm số kế hoạch trong nhóm - OPTIMIZED"""
        return self.plans.count()

    @property
    def active_plans_count(self):
        """Đếm số kế hoạch đang hoạt động - OPTIMIZED"""
        return self.plans.exclude(status__in=['cancelled', 'completed']).count()

    def add_member(self, user, role='member'):
        """
        Thêm thành viên vào nhóm
        
        Args:
            user: User instance
            role: 'admin' hoặc 'member'
        """
        membership, created = GroupMembership.objects.get_or_create(
            user=user,
            group=self,
            defaults={'role': role}
        )
        return membership, created

    def remove_member(self, user):
        """
        Xóa thành viên khỏi nhóm
        Kiểm tra không để nhóm không có admin
        """
        try:
            membership = GroupMembership.objects.get(user=user, group=self)
            
            # If removing an admin, check if there will be at least one admin left
            if membership.role == GroupMembership.ADMIN:
                admin_count = GroupMembership.objects.filter(
                    group=self,
                    role=GroupMembership.ADMIN
                ).exclude(user=user).count()
                
                if admin_count == 0:
                    raise ValueError("Không thể xóa admin cuối cùng. Nhóm phải có ít nhất một admin.")
            
            membership.delete()
            return True
        except GroupMembership.DoesNotExist:
            return False

    def is_member(self, user):
        """Check xem user có phải thành viên không"""
        return self.members.filter(id=user.id).exists()

    def is_admin(self, user):
        """
        Check xem user có phải admin không - OPTIMIZED
        Chỉ kiểm tra membership role, không ưu tiên admin field nữa
        """
        return GroupMembership.objects.filter(
            group=self,
            user=user,
            role=GroupMembership.ADMIN
        ).exists()

    def get_admins(self):
        """Lấy danh sách các admin của nhóm - OPTIMIZED"""
        return User.objects.filter(
            groupmembership__group=self,
            groupmembership__role=GroupMembership.ADMIN
        )
    
    def get_admin_count(self):
        """Đếm số admin hiện tại trong nhóm - OPTIMIZED với single query"""
        return GroupMembership.objects.filter(
            group=self,
            role=GroupMembership.ADMIN
        ).count()
    
    def promote_to_admin(self, user):
        """
        Thăng cấp user lên admin
        """
        try:
            membership = GroupMembership.objects.get(group=self, user=user)
            return membership.promote_to_admin()
        except GroupMembership.DoesNotExist:
            return False
    
    def demote_from_admin(self, user):
        """
        Hạ cấp user xuống member
        """
        try:
            membership = GroupMembership.objects.get(group=self, user=user)
            return membership.demote_to_member()
        except GroupMembership.DoesNotExist:
            return False
    
    def bulk_update_member_roles(self, user_role_pairs):
        """
        Batch update roles for multiple users - OPTIMIZED
        
        Args:
            user_role_pairs: List of (user_id, role) tuples
        
        Example:
            group.bulk_update_member_roles([
                (user1.id, 'admin'),
                (user2.id, 'member')
            ])
        """
        # Validate that at least one admin will remain
        admin_users = [user_id for user_id, role in user_role_pairs if role == GroupMembership.ADMIN]
        current_admin_count = self.get_admin_count()
        users_being_demoted = [user_id for user_id, role in user_role_pairs if role == GroupMembership.MEMBER]
        
        # Count how many current admins are being demoted
        demoted_admin_count = GroupMembership.objects.filter(
            group=self,
            user_id__in=users_being_demoted,
            role=GroupMembership.ADMIN
        ).count()
        
        # Calculate final admin count
        final_admin_count = current_admin_count - demoted_admin_count + len(admin_users)
        
        if final_admin_count == 0:
            raise ValueError("Nhóm phải có ít nhất một admin")
        
        # Perform batch update
        memberships_to_update = []
        for user_id, role in user_role_pairs:
            try:
                membership = GroupMembership.objects.get(group=self, user_id=user_id)
                membership.role = role
                memberships_to_update.append(membership)
            except GroupMembership.DoesNotExist:
                continue
        
        if memberships_to_update:
            GroupMembership.objects.bulk_update(memberships_to_update, ['role'])
        
        return len(memberships_to_update)
    
    def get_member_roles(self):
        """
        Lấy mapping user_id -> role cho tất cả members - OPTIMIZED
        
        Returns:
            Dict: {user_id: role}
        """
        return dict(
            GroupMembership.objects.filter(group=self)
            .values_list('user_id', 'role')
        )
    
    def can_demote_user(self, user):
        """
        Kiểm tra xem có thể hạ cấp user này không
        Chỉ kiểm tra không để nhóm không có admin
        """
        # Cannot demote if this is the last admin
        if self.get_admin_count() <= 1:
            try:
                membership = GroupMembership.objects.get(group=self, user=user)
                return membership.role != GroupMembership.ADMIN
            except GroupMembership.DoesNotExist:
                return False
            
        return True
    
    def can_remove_user(self, user):
        """
        Kiểm tra xem có thể xóa user này khỏi nhóm không
        Chỉ kiểm tra không để nhóm không có admin
        """
        # If user is admin and this is the last admin, cannot remove
        try:
            membership = GroupMembership.objects.get(group=self, user=user)
            if membership.role == GroupMembership.ADMIN and self.get_admin_count() <= 1:
                return False
        except GroupMembership.DoesNotExist:
            return False
            
        return True
        
    def send_message(self, sender, content, message_type='text', **kwargs):
        """
        Gửi tin nhắn vào group - chỉ tạo object, permission check ở view layer
        
        Args:
            sender: User gửi tin nhắn
            content: Nội dung tin nhắn
            message_type: Loại tin nhắn
            **kwargs: Các field khác
        """
        message = ChatMessage.objects.create(
            group=self,
            sender=sender,
            content=content,
            message_type=message_type,
            **kwargs
        )
        return message

    def get_recent_messages(self, limit=50):
        """Lấy tin nhắn gần đây với limit tùy chỉnh - OPTIMIZED"""
        return self.messages.active().select_related('sender').order_by('-created_at')[:limit]

    def get_unread_messages_count(self, user):
        """Đếm số tin nhắn chưa đọc của user - OPTIMIZED"""
        if not self.is_member(user):
            return 0
        
        # Single query to count unread messages
        return self.messages.filter(
            is_deleted=False
        ).exclude(
            models.Q(sender=user) | models.Q(read_statuses__user=user)
        ).count()

    def mark_messages_as_read(self, user, up_to_message=None):
        """
        Đánh dấu tin nhắn đã đọc
        
        Args:
            user: User đọc tin nhắn
            up_to_message: Đọc đến tin nhắn này (None = tất cả)
        """
        if not self.is_member(user):
            return
        
        messages = self.messages.filter(is_deleted=False)
        if up_to_message:
            messages = messages.filter(created_at__lte=up_to_message.created_at)
        
        # Tạo read status cho các message chưa đọc
        for message in messages.exclude(sender=user):
            MessageReadStatus.objects.get_or_create(
                message=message,
                user=user
            )


class GroupMembershipQuerySet(models.QuerySet):
    """Custom QuerySet for GroupMembership"""
    
    def admins(self):
        """Filter admin memberships"""
        return self.filter(role=GroupMembership.ADMIN)
    
    def members(self):
        """Filter member memberships"""
        return self.filter(role=GroupMembership.MEMBER)
    
    def for_group(self, group):
        """Filter memberships for specific group"""
        return self.filter(group=group)
    
    def for_user(self, user):
        """Filter memberships for specific user"""
        return self.filter(user=user)


class GroupMembershipManager(models.Manager):
    """Custom Manager for GroupMembership"""
    
    def get_queryset(self):
        return GroupMembershipQuerySet(self.model, using=self._db)
    
    def admins(self):
        return self.get_queryset().admins()
    
    def members(self):
        return self.get_queryset().members()
    
    def for_group(self, group):
        return self.get_queryset().for_group(group)
    
    def for_user(self, user):
        return self.get_queryset().for_user(user)


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
    
    # Remove id field vì đã có trong BaseModel
    
    # Foreign keys
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
    
    # Custom manager
    objects = GroupMembershipManager()

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
        
        # If demoting to MEMBER, ensure at least one admin remains
        if self.pk and self.role == self.MEMBER:
            # Count current admins excluding this membership
            admin_count = GroupMembership.objects.filter(
                group=self.group,
                role=self.ADMIN
            ).exclude(pk=self.pk).count()
            
            if admin_count == 0:
                raise ValidationError("Nhóm phải có ít nhất một admin. Không thể hạ cấp admin cuối cùng.")

    def save(self, *args, **kwargs):
        """Override save to enforce business rules"""
        # Ensure at least one admin remains when demoting
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

    def demote_to_member(self):
        """
        Hạ cấp xuống member
        Chỉ kiểm tra không để nhóm không có admin
        """
        # Prevent demoting last admin
        admin_count = GroupMembership.objects.filter(
            group=self.group,
            role=self.ADMIN
        ).exclude(pk=self.pk).count()
        
        if admin_count == 0:
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
        """Filter active plans (not cancelled or completed)"""
        return self.exclude(status__in=['cancelled', 'completed'])
    
    def for_user(self, user):
        """Filter plans accessible by user"""
        return self.filter(
            models.Q(creator=user) |  # Own plans
            models.Q(group__members=user) |  # Group plans
            models.Q(is_public=True)  # Public plans
        ).distinct()
    
    def with_activity_count(self):
        """Annotate with activity count"""
        return self.annotate(
            activity_count_annotated=models.Count('activities', distinct=True)
        )
    
    def with_total_cost(self):
        """Annotate with total estimated cost"""
        return self.annotate(
            total_cost_annotated=models.Sum('activities__estimated_cost')
        )


class PlanManager(models.Manager):
    """Custom Manager for Plan"""
    
    def get_queryset(self):
        return PlanQuerySet(self.model, using=self._db)
    
    def personal(self):
        return self.get_queryset().personal()
    
    def group_plans(self):
        return self.get_queryset().group_plans()
    
    def public(self):
        return self.get_queryset().public()
    
    def upcoming(self):
        return self.get_queryset().upcoming()
    
    def ongoing(self):
        return self.get_queryset().ongoing()
    
    def completed(self):
        return self.get_queryset().completed()
    
    def active(self):
        return self.get_queryset().active()
    
    def for_user(self, user):
        return self.get_queryset().for_user(user)
    
    def with_activity_count(self):
        return self.get_queryset().with_activity_count()
    
    def with_total_cost(self):
        return self.get_queryset().with_total_cost()


class Plan(BaseModel):
    """
    Model quản lý kế hoạch du lịch
    Hỗ trợ cả Personal Plan (group=null) và Group Plan
    """
    
    # Remove id field vì đã có trong BaseModel
    
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
    
    # Custom manager
    objects = PlanManager()

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
    def duration_display(self):
        """Hiển thị thời lượng chuyến đi dễ đọc"""
        days = self.duration_days
        if days == 0:
            return "Chưa xác định"
        elif days == 1:
            return "1 ngày"
        else:
            return f"{days} ngày"

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
            total=models.Sum('estimated_cost')
        )['total']
        return result or 0

    

    @property
    def status_display(self):
        """Hiển thị trạng thái plan dễ đọc"""
        status_map = {
            'upcoming': '⏳ Sắp bắt đầu',
            'ongoing': '🏃 Đang diễn ra',
            'completed': '✅ Đã hoàn thành',
            'cancelled': '❌ Đã hủy',
        }
        return status_map.get(self.status, self.status)

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

    def add_activity(self, title, start_time, end_time, **kwargs):
        """
        Thêm hoạt động vào kế hoạch
        
        Args:
            title: Tên hoạt động
            start_time: Thời gian bắt đầu
            end_time: Thời gian kết thúc
            **kwargs: Các field khác của PlanActivity
        """
        # Validate thời gian nằm trong khoảng của plan
        if start_time.date() < self.start_date.date() or end_time.date() > self.end_date.date():
            raise ValueError("Hoạt động phải nằm trong thời gian của kế hoạch")
        
        # Tạo activity
        activity = PlanActivity.objects.create(
            plan=self,
            title=title,
            start_time=start_time,
            end_time=end_time,
            **kwargs
        )
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


    def start_trip(self):
        """Bắt đầu chuyến đi"""
        if self.status == 'upcoming':
            self.status = 'ongoing'
            self.save(update_fields=['status', 'updated_at'])
            return True
        return False

    def complete_trip(self):
        """Hoàn thành chuyến đi"""
        if self.status == 'ongoing':
            self.status = 'completed'
            self.save(update_fields=['status', 'updated_at'])
            return True
        return False
    
    def cancel_trip(self):
        """Hủy chuyến đi"""
        if self.status not in ['cancelled', 'completed']:
            self.status = 'cancelled'
            self.save(update_fields=['status', 'updated_at'])
            return True
        return False


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
            # Index cho query theo ngày
            models.Index(fields=['start_time']),
        ]

    def __str__(self):
        return f"{self.plan.title} - {self.title}"

    def clean(self):
        """Validation cho activity"""
        
        # Validate thời gian
        if self.start_time and self.end_time:
            if self.end_time <= self.start_time:
                raise ValidationError("Thời gian kết thúc phải sau thời gian bắt đầu")
        
        # Validate location coordinates
        if self.latitude is not None and not (-90 <= self.latitude <= 90):
            raise ValidationError("Vĩ độ phải từ -90 đến 90")
            
        if self.longitude is not None and not (-180 <= self.longitude <= 180):
            raise ValidationError("Kinh độ phải từ -180 đến 180")

    def save(self, *args, **kwargs):
        """Override save để chạy validation"""
        self.clean()
        super().save(*args, **kwargs)

    @property
    def duration_hours(self):
        """Tính thời lượng hoạt động (giờ)"""
        if self.start_time and self.end_time:
            duration = self.end_time - self.start_time
            return duration.total_seconds() / 3600
        return 0

    @property
    def duration_display(self):
        """Hiển thị thời lượng dễ đọc"""
        hours = self.duration_hours
        if hours == 0:
            return "Chưa xác định"
        elif hours < 1:
            minutes = int(hours * 60)
            return f"{minutes} phút"
        elif hours < 24:
            return f"{hours:.1f} giờ"
        else:
            days = int(hours / 24)
            remaining_hours = hours % 24
            if remaining_hours == 0:
                return f"{days} ngày"
            return f"{days} ngày {remaining_hours:.1f} giờ"

    @property
    def activity_type_display(self):
        """Hiển thị loại hoạt động với icon"""
        type_icons = {
            'eating': '🍽️ Ăn uống',
            'resting': '🛏️ Nghỉ ngơi',
            'moving': '🚗 Di chuyển',
            'sightseeing': '🏛️ Tham quan',
            'shopping': '🛍️ Mua sắm',
            'entertainment': '🎭 Giải trí',
            'event': '🎉 Sự kiện',
            'sport': '🏅 Thể thao',
            'study': '📚 Học tập',
            'work': '💼 Công việc',
            'other': '📝 Khác',
        }
        return type_icons.get(self.activity_type, self.activity_type)

    @property
    def has_location(self):
        """Check xem có thông tin địa điểm không"""
        return bool(self.latitude and self.longitude)

    @property
    def maps_url(self):
        """Tạo URL Google Maps cho địa điểm"""
        if self.has_location:
            return f"https://www.google.com/maps?q={self.latitude},{self.longitude}"
        elif self.location_name:
            return f"https://www.google.com/maps/search/{self.location_name}"
        return None

class ChatMessageQuerySet(models.QuerySet):
    """Custom QuerySet for ChatMessage"""
    
    def active(self):
        """Filter non-deleted messages"""
        return self.filter(is_deleted=False)
    
    def for_group(self, group):
        """Filter messages for specific group"""
        return self.filter(group=group)
    
    def by_user(self, user):
        """Filter messages by specific user"""
        return self.filter(sender=user)
    
    def text_messages(self):
        """Filter text messages"""
        return self.filter(message_type='text')
    
    def system_messages(self):
        """Filter system messages"""
        return self.filter(message_type='system')
    
    def with_attachments(self):
        """Filter messages with attachments"""
        return self.exclude(attachment='')
    
    def recent(self, limit=50):
        """Get recent messages"""
        return self.order_by('-created_at')[:limit]


class ChatMessageManager(models.Manager):
    """Custom Manager for ChatMessage"""
    
    def get_queryset(self):
        return ChatMessageQuerySet(self.model, using=self._db)
    
    def active(self):
        return self.get_queryset().active()
    
    def for_group(self, group):
        return self.get_queryset().for_group(group)
    
    def by_user(self, user):
        return self.get_queryset().by_user(user)
    
    def text_messages(self):
        return self.get_queryset().text_messages()
    
    def system_messages(self):
        return self.get_queryset().system_messages()
    
    def with_attachments(self):
        return self.get_queryset().with_attachments()
    
    def recent(self, limit=50):
        return self.get_queryset().recent(limit)


class ChatMessage(BaseModel):
    """
    Model quản lý tin nhắn trong group chat
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
    
    # Remove id field vì đã có trong BaseModel
    
    # Thuộc về group nào
    group = models.ForeignKey(
        Group,
        on_delete=models.CASCADE,
        related_name='messages',
        help_text="Nhóm chứa tin nhắn này"
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
    
    # Custom manager
    objects = ChatMessageManager()

    class Meta:
        db_table = 'planpal_chat_messages'
        ordering = ['created_at']
        
        indexes = [
            *BaseModel.Meta.indexes,
            # Index cho query messages của group
            models.Index(fields=['group', 'created_at']),
            # Index cho query messages của user
            models.Index(fields=['sender', 'created_at']),
            # Index cho query theo type
            models.Index(fields=['message_type', 'created_at']),
            # Index cho active messages
            models.Index(fields=['group', 'is_deleted', 'created_at']),
        ]

    def __str__(self):
        if self.sender:
            return f"{self.sender.username} in {self.group.name}: {self.content[:50]}..."
        return f"System message in {self.group.name}: {self.content[:50]}..."

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

    def save(self, *args, **kwargs):
        """Override save để chạy validation"""
        self.clean()
        super().save(*args, **kwargs)

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

    @property
    def attachment_url(self):
        """Lấy URL của attachment"""
        if self.attachment:
            return self.attachment.url
        return None

    @property
    def attachment_size_display(self):
        """Format kích thước file cho display"""
        if not self.attachment_size:
            return None
        
        # Convert bytes to human readable format
        size = self.attachment_size
        for unit in ['B', 'KB', 'MB', 'GB']:
            if size < 1024:
                return f"{size:.1f} {unit}"
            size /= 1024
        return f"{size:.1f} TB"

    @property
    def location_url(self):
        """Tạo Google Maps URL cho location"""
        if self.is_location_message and self.latitude and self.longitude:
            return f"https://www.google.com/maps?q={self.latitude},{self.longitude}"
        return None


    def soft_delete(self):
        """Soft delete message"""
        self.is_deleted = True
        self.content = "[Tin nhắn đã bị xóa]"
        self.save(update_fields=['is_deleted', 'content', 'updated_at'])

    @classmethod
    def create_system_message(cls, group, content):
        """
        Tạo system message
        
        Args:
            group: Group instance
            content: Nội dung thông báo
        """
        return cls.objects.create(
            group=group,
            sender=None,
            message_type='system',
            content=content
        )


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
