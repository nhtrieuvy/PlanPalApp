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
from .models import (
    Plan, Group, GroupMembership, ChatMessage, 
    Friendship, PlanActivity, MessageReadStatus
)

User = get_user_model()


class UserSerializer(serializers.ModelSerializer):
    """Full User serializer - dùng trực tiếp model properties (zero extra queries)."""
    full_name = serializers.CharField(source='display_name', read_only=True)
    initials = serializers.CharField(read_only=True)
    online_status = serializers.CharField(read_only=True)
    avatar_url = serializers.CharField(read_only=True)
    has_avatar = serializers.BooleanField(read_only=True)
    plans_count = serializers.IntegerField(read_only=True)
    personal_plans_count = serializers.IntegerField(read_only=True)
    group_plans_count = serializers.IntegerField(read_only=True)
    groups_count = serializers.IntegerField(read_only=True)
    friends_count = serializers.IntegerField(read_only=True)
    unread_messages_count = serializers.IntegerField(read_only=True)
    is_recently_online = serializers.BooleanField(read_only=True)

    class Meta:
        model = User
        fields = [
            'id', 'username', 'email', 'first_name', 'last_name',
            'display_name', 'full_name', 'initials', 'phone_number',
            'avatar', 'avatar_url', 'has_avatar',
            'date_of_birth', 'bio', 'is_online', 'last_seen', 'is_recently_online', 'online_status',
            'plans_count', 'personal_plans_count', 'group_plans_count', 'groups_count',
            'friends_count', 'unread_messages_count', 'date_joined', 'is_active'
        ]
        read_only_fields = ['id', 'date_joined', 'last_seen', 'is_online']


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


class UserSummarySerializer(serializers.ModelSerializer):
    """Enhanced user summary with optimized performance"""
    # Use properties instead of SerializerMethodField for better performance
    avatar_thumb = serializers.CharField(read_only=True)
    avatar_url = serializers.CharField(read_only=True)
    
    class Meta:
        model = User
        fields = [
            'id', 'username', 'display_name', 'initials', 'is_online', 
            'avatar_thumb', 'avatar_url', 'first_name', 
            'last_name', 'email', 'date_joined', 'last_seen'
        ]
    
    def to_representation(self, instance):
        """OPTIMIZED: Add computed fields in to_representation for better caching"""
        data = super().to_representation(instance)
        # Add full_name without using SerializerMethodField
        data['full_name'] = f"{instance.first_name} {instance.last_name}".strip() or instance.username
        return data


class GroupMembershipSerializer(serializers.ModelSerializer):
    """Serializer cho GroupMembership"""
    user = UserSummarySerializer(read_only=True)
    
    class Meta:
        model = GroupMembership
        fields = [
            'id', 'user', 'role', 'joined_at'
        ]
        read_only_fields = ['id', 'joined_at']


class GroupSerializer(serializers.ModelSerializer):
    """Full group detail serializer."""
    admin = UserSummarySerializer(read_only=True)
    memberships = GroupMembershipSerializer(many=True, read_only=True)
    member_count = serializers.IntegerField(read_only=True)
    plans_count = serializers.IntegerField(read_only=True)
    active_plans_count = serializers.IntegerField(read_only=True)
    
    # Avatar properties
    avatar_url = serializers.CharField(read_only=True)
    # avatar_thumb = serializers.CharField(read_only=True)
    # has_avatar = serializers.BooleanField(read_only=True)
    
    # Cover image properties
    cover_image_url = serializers.CharField(read_only=True)
    # has_cover_image = serializers.BooleanField(read_only=True)
    
    initials = serializers.CharField(read_only=True)
    is_member = serializers.SerializerMethodField()
    user_role = serializers.SerializerMethodField()
    can_edit = serializers.SerializerMethodField()
    can_delete = serializers.SerializerMethodField()

    class Meta:
        model = Group
        fields = [
            'id', 'name', 'description', 
            'avatar_url',
            'cover_image', 'cover_image_url',
            'initials',
            'admin', 'memberships', 'member_count', 'plans_count', 'active_plans_count',
            'is_active', 'is_member', 'user_role', 'can_edit', 'can_delete', 'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'admin', 'created_at', 'updated_at']
    
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

    
    def create(self, validated_data):
        request = self.context.get('request')
        validated_data['admin'] = request.user
        group = super().create(validated_data)
        
        # # Auto-add creator as admin member
        # GroupMembership.objects.create(
        #     group=group,
        #     user=request.user,
        #     role=GroupMembership.ADMIN
        # )
        return group


class GroupCreateSerializer(serializers.ModelSerializer):
    """Serializer riêng cho tạo group"""

    avatar_thumb = serializers.CharField(read_only=True)
    avatar_url = serializers.CharField(read_only=True)
    has_avatar = serializers.BooleanField(read_only=True)
    cover_image_url = serializers.CharField(read_only=True)
    has_cover_image = serializers.BooleanField(read_only=True)
    
    initials = serializers.CharField(read_only=True)
    member_count = serializers.IntegerField(read_only=True)
    admin = UserSummarySerializer(read_only=True)
    
    class Meta:
        model = Group
        fields = [
            'id', 'name', 'description', 
            'avatar', 'avatar_thumb', 'avatar_url', 'has_avatar', 'cover_image_url', 'has_cover_image',
            'initials', 'member_count', 'admin', 'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'admin', 'created_at', 'updated_at']

    def validate_name(self, value):
        if len(value.strip()) < 3:
            raise serializers.ValidationError("Tên nhóm phải có ít nhất 3 ký tự")
        return value.strip()
    
    def create(self, validated_data):
        """Create group và auto-add creator thành admin member"""
        request = self.context.get('request')
        validated_data['admin'] = request.user
        group = super().create(validated_data)
        
        # # Auto-add creator as admin member
        # GroupMembership.objects.create(
        #     group=group,
        #     user=request.user,
        #     role=GroupMembership.ADMIN
        # )
        return group


class GroupSummarySerializer(serializers.ModelSerializer):
    """Lightweight group summary (list views)."""
    member_count = serializers.IntegerField(read_only=True)
    avatar_thumb = serializers.CharField(read_only=True)
    initials = serializers.CharField(read_only=True)
    class Meta:
        model = Group
        fields = ['id', 'name', 'description', 'member_count', 'avatar_thumb', 'initials']


class PlanActivitySerializer(serializers.ModelSerializer):
    """Serializer cho PlanActivity - OPTIMIZED"""
    # ✅ Use properties directly
    duration_hours = serializers.FloatField(read_only=True)
    duration_display = serializers.CharField(read_only=True)
    activity_type_display = serializers.CharField(read_only=True)
    has_location = serializers.BooleanField(read_only=True)
    maps_url = serializers.CharField(read_only=True)

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
    creator = UserSummarySerializer(read_only=True)
    group = GroupSummarySerializer(read_only=True)
    activities = PlanActivitySerializer(many=True, read_only=True)
    
    # Write fields
    group_id = serializers.UUIDField(write_only=True, required=False, allow_null=True)
    # Convenience read field for frontend badges
    group_name = serializers.CharField(source='group.name', read_only=True)
    
    # ✅ Use properties directly
    duration_days = serializers.IntegerField(read_only=True)
    duration_display = serializers.CharField( read_only=True)
    activities_count = serializers.IntegerField( read_only=True)
    total_estimated_cost = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True)
    status_display = serializers.CharField(read_only=True)

    # Computed fields that need context
    can_view = serializers.SerializerMethodField()
    can_edit = serializers.SerializerMethodField()
    collaborators = UserSummarySerializer(many=True, read_only=True)

    class Meta:
        model = Plan
        fields = [
            'id', 'title', 'description', 'start_date', 'end_date',
            'is_public', 'status', 'status_display', 'plan_type', 'creator', 'group', 'group_id', 'group_name',
            'activities', 'duration_days', 'duration_display', 'activities_count', 
            'total_estimated_cost', 'can_view', 'can_edit', 'collaborators',
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
        
        # Validate group access and plan_type consistency on update
        group_id = attrs.get('group_id')
        instance = getattr(self, 'instance', None)
        if instance:
            if instance.plan_type == 'personal' and group_id:
                raise serializers.ValidationError("Kế hoạch cá nhân không thể gán nhóm")
            if instance.plan_type == 'group' and ('group_id' in attrs) and group_id is None:
                raise serializers.ValidationError("Kế hoạch nhóm phải thuộc một nhóm")

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

    def update(self, instance, validated_data):
        """Apply group_id changes respecting plan_type rules."""
        if 'group_id' in validated_data:
            group_id = validated_data.pop('group_id')
        else:
            group_id = None

        if instance.plan_type == 'personal':
            # Ensure personal plan has no group
            validated_data['group'] = None
        else:
            # Group plan: update group if provided
            if group_id is not None:
                try:
                    group = Group.objects.get(id=group_id)
                except Group.DoesNotExist:
                    raise serializers.ValidationError("Nhóm không tồn tại")
                validated_data['group'] = group
        return super().update(instance, validated_data)


class PlanCreateSerializer(serializers.ModelSerializer):
    """Serializer đơn giản cho tạo plan"""
    plan_type = serializers.ChoiceField(choices=[('personal', 'Cá nhân'), ('group', 'Nhóm')], required=True)
    group_id = serializers.UUIDField(required=False, allow_null=True)
    
    class Meta:
        model = Plan
        fields = [
            'title', 'description', 'start_date', 'end_date', 
            'is_public', 'plan_type', 'group_id'
        ]
    

    def validate_title(self, value):
        if len(value.strip()) < 3:
            raise serializers.ValidationError("Tiêu đề phải có ít nhất 3 ký tự")
        return value.strip()

    def validate(self, attrs):
        """Validate dates, plan type, and group access"""
        if attrs.get('start_date') and attrs.get('end_date'):
            if attrs['end_date'] <= attrs['start_date']:
                raise serializers.ValidationError(
                    "Ngày kết thúc phải sau ngày bắt đầu"
                )
        plan_type = attrs.get('plan_type')
        group_id = attrs.get('group_id')
        if plan_type == 'group':
            if not group_id:
                raise serializers.ValidationError("Kế hoạch nhóm cần chọn nhóm")
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
        elif plan_type == 'personal':
            attrs['group_id'] = None
        else:
            raise serializers.ValidationError("Loại kế hoạch không hợp lệ")
        return attrs

    def create(self, validated_data):
        # Set default status to 'upcoming' on creation
        validated_data['status'] = 'upcoming'
        # Handle group assignment for group plans
        plan_type = validated_data.get('plan_type')
        group_id = validated_data.pop('group_id', None)
        if plan_type == 'group' and group_id:
            try:
                group = Group.objects.get(id=group_id)
                validated_data['group'] = group
            except Group.DoesNotExist:
                pass  # Will be handled by validation
        else:
            validated_data['group'] = None
        return super().create(validated_data)


class PlanSummarySerializer(serializers.ModelSerializer):
    """Serializer tóm tắt cho Plan list view"""
    creator = UserSummarySerializer(read_only=True)
    group_name = serializers.CharField(source='group.name', read_only=True)
    duration_days = serializers.SerializerMethodField()
    status_display = serializers.CharField(read_only=True)
    
    class Meta:
        model = Plan
        fields = [
            'id', 'title', 'start_date', 'end_date', 'is_public', 'status',
            'status_display', 'creator', 'group_name', 'duration_days', 'created_at'
        ]
    
    def get_duration_days(self, obj):
        return obj.duration_days
    
    
class ChatMessageSerializer(serializers.ModelSerializer):
    """Serializer cho ChatMessage với Cloudinary attachment support - OPTIMIZED"""
    sender = UserSerializer(read_only=True)
    reply_to = serializers.SerializerMethodField()
    
    # ✅ Use properties directly
    attachment_size_display = serializers.CharField( read_only=True)
    attachment_url = serializers.CharField(read_only=True)
    location_url = serializers.CharField(read_only=True)
    
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
    # OPTIMIZED: Use UserSummarySerializer instead of full UserSerializer
    user = UserSummarySerializer(read_only=True)
    friend = UserSummarySerializer(read_only=True)
    
    class Meta:
        model = Friendship
        fields = [
            'id', 'user', 'friend', 'status',
            'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'user', 'friend', 'created_at', 'updated_at']
    
    def to_representation(self, instance):
        """OPTIMIZED: Add friend_info without SerializerMethodField"""
        data = super().to_representation(instance)
        
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            current_user = request.user
            # Determine friend user efficiently
            friend_user = instance.friend if instance.user == current_user else instance.user
            data['friend_info'] = {
                'id': friend_user.id,
                'username': friend_user.username,
                'display_name': friend_user.display_name,
                'avatar_url': friend_user.avatar_url,
                'is_online': friend_user.is_online,
                'last_seen': friend_user.last_seen
            }
        
        return data


class FriendRequestSerializer(serializers.Serializer):
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






