"""
Serializers for PlanPal app

Handle data serialization/deserialization for API endpoints.
Includes validation, nested relationships, and computed fields.
Support for Cloudinary image/file uploads.
"""

from rest_framework import serializers
from django.contrib.auth import get_user_model
from django.db import models
from django.utils import timezone
from cloudinary import CloudinaryImage
from .models import (
    Plan, Group, GroupMembership, ChatMessage, 
    Friendship, PlanActivity, MessageReadStatus
)

User = get_user_model()


class UserSerializer(serializers.ModelSerializer):
    """Serializer cho User model với Cloudinary avatar support - OPTIMIZED"""
    # ✅ Use properties directly instead of SerializerMethodField
    full_name = serializers.CharField(source='display_name', read_only=True)
    initials = serializers.CharField(read_only=True)
    online_status = serializers.CharField(read_only=True)
    avatar_url = serializers.CharField(read_only=True)
    has_avatar = serializers.BooleanField(read_only=True)
    
    # Count properties
    plans_count = serializers.IntegerField(read_only=True)
    personal_plans_count = serializers.IntegerField(read_only=True)
    group_plans_count = serializers.IntegerField(read_only=True)
    groups_count = serializers.IntegerField(read_only=True)
    friends_count = serializers.IntegerField(read_only=True)
    unread_messages_count = serializers.IntegerField(read_only=True)
    
    # Legacy support
    is_recently_online = serializers.BooleanField(read_only=True)
    
    class Meta:
        model = User
        fields = [
            'id', 'username', 'email', 'first_name', 'last_name', 
            'display_name', 'full_name', 'initials',
            'phone_number', 'avatar', 'avatar_url', 'has_avatar',
            'date_of_birth', 'bio', 'is_online', 'last_seen', 
            'is_recently_online', 'online_status',
            'plans_count', 'personal_plans_count', 'group_plans_count',
            'groups_count', 'friends_count', 'unread_messages_count',
            'date_joined', 'is_active'
        ]
        read_only_fields = ['id', 'date_joined', 'last_seen', 'is_online']
    
    def get_avatar_url(self, obj):
        """Always return full Cloudinary URL for avatar (300x300)"""
        if obj.avatar:
            public_id = str(obj.avatar)
            if public_id:
                img = CloudinaryImage(public_id)
                return img.build_url(width=300, height=300, crop='fill', gravity='face')
        return None

    def get_avatar_thumbnail(self, obj):
        """Always return full Cloudinary URL for avatar thumbnail (100x100)"""
        if obj.avatar:
            public_id = str(obj.avatar)
            if public_id:
                img = CloudinaryImage(public_id)
                return img.build_url(width=100, height=100, crop='fill', gravity='face')
        return None


class UserCreateSerializer(serializers.ModelSerializer):
    """Serializer cho user registration"""
    password = serializers.CharField(write_only=True, min_length=8)
    password_confirm = serializers.CharField(write_only=True)
    
    class Meta:
        model = User
        fields = [
            'username', 'email', 'password', 'password_confirm',
            'first_name', 'last_name', 'phone_number', 'avatar'
        ]
    
    def validate_username(self, value):
        if User.objects.filter(username=value).exists():
            raise serializers.ValidationError("Username đã tồn tại")
        return value
    
    def validate_email(self, value):
        if User.objects.filter(email=value).exists():
            raise serializers.ValidationError("Email đã được sử dụng")
        return value
    
    def validate(self, attrs):
        if attrs['password'] != attrs['password_confirm']:
            raise serializers.ValidationError("Mật khẩu không khớp")
        return attrs
    
    def create(self, validated_data):
        validated_data.pop('password_confirm') # Xóa trường không cần thiết
        user = User.objects.create_user(**validated_data) # Giải nén dictionary thành keyword arguments
        return user


class UserProfileSerializer(serializers.ModelSerializer):
    """Serializer cho user profile - có thể edit"""
    
    class Meta:
        model = User
        fields = [
            'first_name', 'last_name', 'phone_number', 'avatar', 
            'date_of_birth', 'bio'
        ]
    
    def validate_avatar(self, value):
        if value and hasattr(value, 'size') and value.size > 5 * 1024 * 1024:  # 5MB limit
            raise serializers.ValidationError("Avatar không được vượt quá 5MB")
        # Note: Cloudinary fields don't need file size validation as they handle compression
        return value


class GroupMembershipSerializer(serializers.ModelSerializer):
    """Serializer cho GroupMembership"""
    user = UserSerializer(read_only=True)
    
    class Meta:
        model = GroupMembership
        fields = [
            'id', 'user', 'role', 'joined_at'
        ]
        read_only_fields = ['id', 'joined_at']


class GroupSerializer(serializers.ModelSerializer):
    """Serializer cho Group model với Cloudinary cover image support - OPTIMIZED"""
    admin = UserSerializer(read_only=True)
    memberships = GroupMembershipSerializer(many=True, read_only=True)
    
    # ✅ Use properties directly
    member_count = serializers.IntegerField(source='member_count', read_only=True)
    plans_count = serializers.IntegerField(source='plans_count', read_only=True)
    active_plans_count = serializers.IntegerField(source='active_plans_count', read_only=True)
    
    # Computed fields that need context
    is_member = serializers.SerializerMethodField()
    user_role = serializers.SerializerMethodField()
    can_edit = serializers.SerializerMethodField()
    can_delete = serializers.SerializerMethodField()
    cover_image_url = serializers.SerializerMethodField()
    cover_image_thumbnail = serializers.SerializerMethodField()
    
    class Meta:
        model = Group
        fields = [
            'id', 'name', 'description', 'cover_image', 'cover_image_url', 
            'cover_image_thumbnail', 'admin', 'memberships', 'member_count', 
            'plans_count', 'active_plans_count', 'is_active', 'is_member', 
            'user_role', 'can_edit', 'can_delete', 'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'admin', 'created_at', 'updated_at']
    
    def get_member_count(self, obj):
        return obj.member_count
    
    def get_is_member(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            return obj.is_member(request.user)
        return False
    
    def get_user_role(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            try:
                membership = GroupMembership.objects.get(
                    group=obj, user=request.user
                )
                return membership.role
            except GroupMembership.DoesNotExist:
                return None
        return None
    
    def get_can_edit(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            return obj.is_admin(request.user)
        return False
    
    def get_can_delete(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            return obj.admin == request.user
        return False
    
    def get_cover_image_url(self, obj):
        """Get Cloudinary cover image URL với transformation"""
        if obj.cover_image:
            if hasattr(obj.cover_image, 'build_url'):
                return obj.cover_image.build_url(
                    width=1200, height=400, crop='fill', gravity='center'
                )
            return obj.cover_image.url
        return None
    
    def get_cover_image_thumbnail(self, obj):
        """Get cover image thumbnail for lists"""
        if obj.cover_image:
            if hasattr(obj.cover_image, 'build_url'):
                return obj.cover_image.build_url(
                    width=300, height=200, crop='fill', gravity='center'
                )
            return obj.cover_image.url
        return None
    
    def create(self, validated_data):
        request = self.context.get('request')
        validated_data['admin'] = request.user
        group = super().create(validated_data)
        
        # Auto-add creator as admin member
        GroupMembership.objects.create(
            group=group,
            user=request.user,
            role=GroupMembership.ADMIN
        )
        return group


class GroupCreateSerializer(serializers.ModelSerializer):
    """Serializer riêng cho tạo group"""
    
    class Meta:
        model = Group
        fields = ['name', 'description', 'cover_image']
    
    def validate_name(self, value):
        if len(value.strip()) < 3:
            raise serializers.ValidationError("Tên nhóm phải có ít nhất 3 ký tự")
        return value.strip()


class PlanActivitySerializer(serializers.ModelSerializer):
    """Serializer cho PlanActivity - OPTIMIZED"""
    # ✅ Use properties directly
    duration_hours = serializers.FloatField(source='duration_hours', read_only=True)
    duration_display = serializers.CharField(source='duration_display', read_only=True)
    activity_type_display = serializers.CharField(source='activity_type_display', read_only=True)
    has_location = serializers.BooleanField(source='has_location', read_only=True)
    maps_url = serializers.CharField(source='maps_url', read_only=True)
    
    class Meta:
        model = PlanActivity
        fields = [
            'id', 'plan', 'title', 'description', 'activity_type', 'activity_type_display',
            'start_time', 'end_time', 'duration_hours', 'duration_display',
            'location_name', 'location_address', 'latitude', 'longitude', 'goong_place_id', 
            'has_location', 'maps_url', 'estimated_cost', 'notes', 'order', 
            'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'created_at', 'updated_at']
    
    def validate(self, attrs):
        """Enhanced validation with overlap checking - FAT SERIALIZER"""
        start_time = attrs.get('start_time')
        end_time = attrs.get('end_time')
        
        # Basic time validation
        if start_time and end_time:
            if end_time <= start_time:
                raise serializers.ValidationError(
                    "Thời gian kết thúc phải sau thời gian bắt đầu"
                )
        
        # Check for overlapping activities if plan is set
        plan = attrs.get('plan') or (self.instance and self.instance.plan)
        if plan and start_time and end_time:
            # Use model method for business logic
            overlapping = plan.check_activity_overlap(
                start_time, end_time, 
                exclude_id=self.instance.id if self.instance else None
            )
            if overlapping:
                raise serializers.ValidationError(
                    f"Hoạt động bị trùng với: {overlapping.title}"
                )
        return attrs


class PlanSerializer(serializers.ModelSerializer):
    """Serializer cho Plan model - OPTIMIZED"""
    creator = UserSerializer(read_only=True)
    group = GroupSerializer(read_only=True)
    activities = PlanActivitySerializer(many=True, read_only=True)
    
    # Write fields
    group_id = serializers.UUIDField(write_only=True, required=False, allow_null=True)
    
    # ✅ Use properties directly
    duration_days = serializers.IntegerField(source='duration_days', read_only=True)
    duration_display = serializers.CharField(source='duration_display', read_only=True)
    activities_count = serializers.IntegerField(source='activities_count', read_only=True)
    total_estimated_cost = serializers.DecimalField(source='total_estimated_cost', max_digits=12, decimal_places=2, read_only=True)
    budget_vs_estimated = serializers.JSONField(source='budget_vs_estimated', read_only=True)
    is_over_budget = serializers.BooleanField(source='is_over_budget', read_only=True)
    status_display = serializers.CharField(source='status_display', read_only=True)
    
    # Computed fields that need context
    can_view = serializers.SerializerMethodField()
    can_edit = serializers.SerializerMethodField()
    collaborators = serializers.SerializerMethodField()
    
    class Meta:
        model = Plan
        fields = [
            'id', 'title', 'description', 'start_date', 'end_date', 'budget',
            'is_public', 'status', 'status_display', 'plan_type', 'creator', 'group', 'group_id',
            'activities', 'duration_days', 'duration_display', 'activities_count', 
            'total_estimated_cost', 'budget_vs_estimated', 'is_over_budget',
            'can_view', 'can_edit', 'collaborators',
            'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'creator', 'plan_type', 'created_at', 'updated_at']
    
    def get_duration_days(self, obj):
        # Using property directly
        return obj.duration_days
    
    def get_activities_count(self, obj):
        # Using property directly  
        return obj.activities_count
    
    def get_total_estimated_cost(self, obj):
        # Using property directly
        return obj.total_estimated_cost
    
    def get_can_view(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            user = request.user
            
            # Creator luôn xem được
            if obj.creator == user:
                return True
            
            # Public plans ai cũng xem được
            if obj.is_public:
                return True
            
            # Group plans: members xem được
            if obj.is_group_plan() and obj.group:
                return obj.group.is_member(user)
            
            return False
        return obj.is_public
    
    def get_can_edit(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            user = request.user
            
            # Creator luôn edit được
            if obj.creator == user:
                return True
            
            # Group plans: admins có thể edit
            if obj.is_group_plan() and obj.group:
                return obj.group.is_admin(user)
            
            return False
        return False
    
    def get_collaborators(self, obj):
        # Using property
        collaborators = obj.collaborators
        return UserSerializer(collaborators, many=True, context=self.context).data
    
    def validate(self, attrs):
        if attrs.get('start_date') and attrs.get('end_date'):
            if attrs['end_date'] <= attrs['start_date']:
                raise serializers.ValidationError(
                    "Ngày kết thúc phải sau ngày bắt đầu"
                )
        
        # Validate group access
        group_id = attrs.get('group_id')
        if group_id:
            try:
                group = Group.objects.get(id=group_id)
                request = self.context.get('request')
                if request and request.user.is_authenticated:
                    if not group.is_member(request.user):
                        raise serializers.ValidationError(
                            "Bạn không phải thành viên của nhóm này"
                        )
            except Group.DoesNotExist:
                raise serializers.ValidationError("Nhóm không tồn tại")
        
        return attrs
    
    def create(self, validated_data):
        request = self.context.get('request')
        validated_data['creator'] = request.user
        return super().create(validated_data)


class PlanCreateSerializer(serializers.ModelSerializer):
    """Serializer đơn giản cho tạo plan"""
    group_id = serializers.UUIDField(required=False, allow_null=True)
    
    class Meta:
        model = Plan
        fields = [
            'title', 'description', 'start_date', 'end_date', 
            'budget', 'is_public', 'group_id'
        ]
    
    def validate_title(self, value):
        if len(value.strip()) < 3:
            raise serializers.ValidationError("Tiêu đề phải có ít nhất 3 ký tự")
        return value.strip()


class ChatMessageSerializer(serializers.ModelSerializer):
    """Serializer cho ChatMessage với Cloudinary attachment support - OPTIMIZED"""
    sender = UserSerializer(read_only=True)
    reply_to = serializers.SerializerMethodField()
    
    # ✅ Use properties directly
    attachment_size_display = serializers.CharField(source='attachment_size_display', read_only=True)
    attachment_url = serializers.CharField(source='attachment_url', read_only=True)
    location_url = serializers.CharField(source='location_url', read_only=True)
    
    # Computed fields that need context
    can_edit = serializers.SerializerMethodField()
    can_delete = serializers.SerializerMethodField()
    attachment_thumbnail = serializers.SerializerMethodField()
    
    class Meta:
        model = ChatMessage
        fields = [
            'id', 'group', 'sender', 'message_type', 'content',
            'attachment', 'attachment_url', 'attachment_thumbnail',
            'attachment_name', 'attachment_size', 'attachment_size_display',
            'latitude', 'longitude', 'location_name', 'location_url',
            'reply_to', 'is_edited', 'is_deleted',
            'can_edit', 'can_delete', 'created_at', 'updated_at'
        ]
        read_only_fields = [
            'id', 'sender', 'is_edited', 'is_deleted', 
            'created_at', 'updated_at'
        ]
    
    def get_reply_to(self, obj):
        if obj.reply_to:
            return {
                'id': obj.reply_to.id,
                'sender': obj.reply_to.sender.username if obj.reply_to.sender else 'System',
                'content': obj.reply_to.content[:100] + '...' if len(obj.reply_to.content) > 100 else obj.reply_to.content
            }
        return None
    
    def get_can_edit(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            user = request.user
            
            # Chỉ sender mới edit được
            if obj.sender != user:
                return False
            
            # System messages không thể edit
            if obj.message_type == 'system':
                return False
            
            # Check time limit (15 minutes)
            time_limit = timezone.timedelta(minutes=15)
            return timezone.now() - obj.created_at <= time_limit
        return False
    
    def get_can_delete(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            user = request.user
            
            # Sender có thể delete
            if obj.sender == user:
                return True
            
            # Group admin có thể delete
            if obj.group.is_admin(user):
                return True
            
            return False
        return False
    
    def get_attachment_size_display(self, obj):
        return obj.get_attachment_size_display()
    
    def get_attachment_url(self, obj):
        """Get Cloudinary attachment URL"""
        if obj.attachment:
            if hasattr(obj.attachment, 'build_url'):
                return obj.attachment.build_url()
            return obj.attachment.url
        return None
    
    def get_attachment_thumbnail(self, obj):
        """Get attachment thumbnail for images"""
        if obj.attachment and obj.message_type == 'image':
            if hasattr(obj.attachment, 'build_url'):
                return obj.attachment.build_url(
                    width=300, height=300, crop='fill', gravity='center'
                )
            return obj.attachment.url
        return None
    
    def get_location_url(self, obj):
        return obj.get_location_url()
    
    def validate(self, attrs):
        # Location messages cần coordinates
        if attrs.get('message_type') == 'location':
            if not (attrs.get('latitude') and attrs.get('longitude')):
                raise serializers.ValidationError(
                    "Location message cần có tọa độ"
                )
        return attrs
    
    def create(self, validated_data):
        request = self.context.get('request')
        validated_data['sender'] = request.user
        return super().create(validated_data)


class FriendshipSerializer(serializers.ModelSerializer):
    """General Friendship serializer for admin/internal use"""
    user = UserSerializer(read_only=True)
    friend = UserSerializer(read_only=True)
    friend_info = serializers.SerializerMethodField()
    
    class Meta:
        model = Friendship
        fields = [
            'id', 'user', 'friend', 'friend_info', 'status',
            'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'user', 'friend', 'created_at', 'updated_at']
    
    def get_friend_info(self, obj):
        """Get friend info based on current user"""
        request = self.context.get('request')
        if not request or not request.user.is_authenticated:
            return None
        current_user = request.user
        # Determine friend user
        friend_user = obj.friend if obj.user == current_user else obj.user
        return {
            'id': friend_user.id,
            'username': friend_user.username,
            'full_name': friend_user.display_name,
            'avatar_url': friend_user.avatar.url if friend_user.avatar else None,
            'is_online': friend_user.is_online,
            'last_seen': friend_user.last_seen
        }


class FriendRequestSerializer(serializers.Serializer):
    """Dedicated serializer for sending friend requests"""
    friend_id = serializers.UUIDField()
    message = serializers.CharField(max_length=200, required=False, allow_blank=True)
    
    def validate_friend_id(self, value):
        request = self.context['request']
        user = request.user
        
        # Check if friend exists
        try:
            friend_user = User.objects.get(id=value)
        except User.DoesNotExist:
            raise serializers.ValidationError("User not found")
        
        # Cannot send to yourself
        if friend_user == user:
            raise serializers.ValidationError("Cannot send friend request to yourself")
        
        # Check existing friendship - Use optimized single query
        existing = Friendship.objects.filter(
            models.Q(user=user, friend=friend_user) |
            models.Q(user=friend_user, friend=user)
        ).first()
        
        if existing:
            if existing.status == 'pending':
                raise serializers.ValidationError("Friend request already sent")
            elif existing.status == 'accepted':
                raise serializers.ValidationError("Already friends")
            elif existing.status == 'blocked':
                raise serializers.ValidationError("Cannot send friend request")
        
        self.validated_friend = friend_user
        return value
    
    def create(self, validated_data):
        request = self.context['request']
        friendship = Friendship.objects.create(
            user=request.user,
            friend=self.validated_friend,
            status='pending'
        )
        return friendship


class FriendsListSerializer(serializers.ModelSerializer):
    """Optimized serializer for friends list"""
    friendship_since = serializers.SerializerMethodField()
    mutual_friends_count = serializers.SerializerMethodField()
    
    class Meta:
        model = User
        fields = [
            'id', 'username', 'first_name', 'last_name', 
            'avatar', 'is_online', 'last_seen', 'friendship_since',
            'mutual_friends_count'
        ]
    
    def get_friendship_since(self, obj):
        """Get friendship date - optimized with context"""
        friendships_map = self.context.get('friendships_map', {})
        friendship = friendships_map.get(obj.id)
        return friendship.created_at if friendship else None
    
    def get_mutual_friends_count(self, obj):
        """Get mutual friends count - can be optimized with prefetch"""
        request = self.context.get('request')
        if not request or not request.user.is_authenticated:
            return 0
        
        # This could be optimized with a separate query or cached
        return 0  # Placeholder - implement if needed


class MessageReadStatusSerializer(serializers.ModelSerializer):
    """Serializer cho MessageReadStatus"""
    user = UserSerializer(read_only=True)
    
    class Meta:
        model = MessageReadStatus
        fields = ['id', 'message', 'user', 'read_at']
        read_only_fields = ['id', 'user', 'read_at']


# Summary serializers for list views
class PlanSummarySerializer(serializers.ModelSerializer):
    """Serializer tóm tắt cho Plan list view"""
    creator = UserSerializer(read_only=True)
    group_name = serializers.CharField(source='group.name', read_only=True)
    duration_days = serializers.SerializerMethodField()
    
    class Meta:
        model = Plan
        fields = [
            'id', 'title', 'start_date', 'end_date', 'is_public', 
            'status', 'creator', 'group_name', 'duration_days', 'created_at'
        ]
    
    def get_duration_days(self, obj):
        return obj.duration_days


class GroupSummarySerializer(serializers.ModelSerializer):
    """Serializer tóm tắt cho Group list view"""
    admin = UserSerializer(read_only=True)
    member_count = serializers.SerializerMethodField()
    
    class Meta:
        model = Group
        fields = [
            'id', 'name', 'description', 'admin', 'member_count', 
            'is_active', 'created_at'
        ]
    
    def get_member_count(self, obj):
        return obj.member_count
