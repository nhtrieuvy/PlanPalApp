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
    """Full User serializer - dùng to_representation cho computed fields."""
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
            'phone_number',
            'avatar_url', 'has_avatar',
            'date_of_birth', 'bio', 'is_online', 'last_seen', 'is_recently_online', 'online_status',
            'plans_count', 'personal_plans_count', 'group_plans_count', 'groups_count',
            'friends_count', 'unread_messages_count', 'date_joined', 'is_active'
        ]
        read_only_fields = ['id', 'date_joined', 'last_seen', 'is_online']
    
    def to_representation(self, instance):
        data = super().to_representation(instance)
        data['full_name'] = instance.get_full_name() or instance.username
        data['initials'] = self._get_initials(instance)
        return data
    
    def _get_initials(self, instance):
        """Helper method để tính initials"""
        if instance.first_name and instance.last_name:
            return f"{instance.first_name[0]}{instance.last_name[0]}".upper()
        elif instance.first_name:
            return instance.first_name[0].upper()
        return instance.username[0].upper() if instance.username else "U"


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
    avatar_thumb = serializers.CharField(read_only=True)
    avatar_url = serializers.CharField(read_only=True)
    
    class Meta:
        model = User
        fields = [
            'id', 'username', 'is_online',
            'avatar_thumb', 'avatar_url', 'first_name', 
            'last_name', 'email', 'date_joined', 'last_seen'
        ]
    
    def to_representation(self, instance):
        data = super().to_representation(instance)
        # Computed fields using to_representation for better performance
        data['full_name'] = instance.get_full_name() or instance.username
        data['initials'] = self._get_initials(instance)
        return data
    
    def _get_initials(self, instance):
        """Helper method để tính initials"""
        if instance.first_name and instance.last_name:
            return f"{instance.first_name[0]}{instance.last_name[0]}".upper()
        elif instance.first_name:
            return instance.first_name[0].upper()
        return instance.username[0].upper() if instance.username else "U"


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
            'admin', 'memberships', 'member_count', 'plans_count', 'active_plans_count',
            'is_active', 'is_member', 'user_role', 'can_edit', 'can_delete', 'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'admin', 'created_at', 'updated_at']
    
    def to_representation(self, instance):
        data = super().to_representation(instance)
        # Computed field using to_representation for better performance
        data['initials'] = self._get_group_initials(instance)
        return data
    
    def _get_group_initials(self, instance):
        """Helper method để tính initials cho group"""
        if not instance.name:
            return 'G'
        
        parts = [p for p in instance.name.split() if p]
        if len(parts) >= 2:
            return (parts[0][0] + parts[1][0]).upper()
        
        return instance.name[:2].upper()
    
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
    
    member_count = serializers.IntegerField(read_only=True)
    admin = UserSummarySerializer(read_only=True)
    
    # Field for initial members (friends to add)
    initial_members = serializers.ListField(
        child=serializers.UUIDField(),
        write_only=True,
        required=True,
        help_text="List of friend IDs to add to group (minimum 2 required)"
    )
    
    class Meta:
        model = Group
        fields = [
            'id', 'name', 'description', 'initial_members',
            'avatar', 'avatar_thumb', 'avatar_url', 'has_avatar', 'cover_image_url', 'has_cover_image',
            'member_count', 'admin', 'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'admin', 'created_at', 'updated_at']

    def to_representation(self, instance):
        data = super().to_representation(instance)
        # Computed field using to_representation for better performance
        data['initials'] = self._get_group_initials(instance)
        return data
    
    def _get_group_initials(self, instance):
        """Helper method để tính initials cho group"""
        if not instance.name:
            return 'G'
        
        parts = [p for p in instance.name.split() if p]
        if len(parts) >= 2:
            return (parts[0][0] + parts[1][0]).upper()
        
        return instance.name[:2].upper()

    def validate_name(self, value):
        if len(value.strip()) < 3:
            raise serializers.ValidationError("Tên nhóm phải có ít nhất 3 ký tự")
        return value.strip()
    
    def validate_initial_members(self, value):
        """Validate initial members list"""
        if len(value) < 2:
            raise serializers.ValidationError("Cần ít nhất 2 bạn bè để tạo nhóm")
        
        # Check for duplicates
        if len(value) != len(set(value)):
            raise serializers.ValidationError("Không thể thêm cùng một người nhiều lần")
        
        request = self.context.get('request')
        if not request:
            raise serializers.ValidationError("Invalid context")
        
        current_user = request.user
        
        # Check if current user is in the list (shouldn't be)
        if str(current_user.id) in [str(uid) for uid in value]:
            raise serializers.ValidationError("Không thể thêm chính mình vào nhóm")
        
        # Validate all users exist and are friends
        from .models import Friendship
        for user_id in value:
            try:
                target_user = User.objects.get(id=user_id)
            except User.DoesNotExist:
                raise serializers.ValidationError(f"User với ID {user_id} không tồn tại")
            
            if not Friendship.are_friends(current_user, target_user):
                raise serializers.ValidationError(f"Chỉ có thể thêm bạn bè vào nhóm. {target_user.username} chưa phải là bạn bè")
        return value
    
    def create(self, validated_data):
        """Create group và auto-add creator thành admin member"""
        request = self.context.get('request')
        initial_members = validated_data.pop('initial_members')
        validated_data['admin'] = request.user
        
        group = super().create(validated_data)
        
        # Add initial members
        from .models import GroupMembership
        for user_id in initial_members:
            user = User.objects.get(id=user_id)
            GroupMembership.objects.create(
                group=group,
                user=user,
                role=GroupMembership.MEMBER
            )
        
        return group


class GroupSummarySerializer(serializers.ModelSerializer):
    """Lightweight group summary (list views)."""
    member_count = serializers.IntegerField(read_only=True)
    avatar_thumb = serializers.CharField(read_only=True)
    
    class Meta:
        model = Group
        fields = ['id', 'name', 'description', 'member_count', 'avatar_thumb']
    
    def to_representation(self, instance):
        data = super().to_representation(instance)
        # Computed field using to_representation for better performance
        data['initials'] = self._get_group_initials(instance)
        return data
    
    def _get_group_initials(self, instance):
        """Helper method để tính initials cho group"""
        if not instance.name:
            return 'G'
        
        parts = [p for p in instance.name.split() if p]
        if len(parts) >= 2:
            return (parts[0][0] + parts[1][0]).upper()
        
        return instance.name[:2].upper()


class PlanActivitySerializer(serializers.ModelSerializer):
    """Serializer cho PlanActivity - OPTIMIZED"""

    class Meta:
        model = PlanActivity
        fields = [
            'id', 'plan', 'title', 'description', 'activity_type',
            'start_time', 'end_time', 'location_name', 'location_address', 
            'latitude', 'longitude', 'goong_place_id', 'estimated_cost', 
            'notes', 'order', 'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'created_at', 'updated_at']
    
    def to_representation(self, instance):
        data = super().to_representation(instance)
        # Computed fields using to_representation for better performance
        data['duration_hours'] = self._get_duration_hours(instance)
        data['duration_display'] = self._get_duration_display(instance)
        data['activity_type_display'] = self._get_activity_type_display(instance)
        data['has_location'] = self._get_has_location(instance)
        data['maps_url'] = self._get_maps_url(instance)
        return data
    
    def _get_duration_hours(self, instance):
        """Helper method để tính duration hours"""
        if instance.start_time and instance.end_time:
            duration = instance.end_time - instance.start_time
            return duration.total_seconds() / 3600
        return 0
    
    def _get_duration_display(self, instance):
        """Helper method để hiển thị duration"""
        hours = self._get_duration_hours(instance)
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
    
    def _get_activity_type_display(self, instance):
        """Helper method để hiển thị activity type với icon"""
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
        return type_icons.get(instance.activity_type, instance.activity_type)
    
    def _get_has_location(self, instance):
        """Helper method để check has location"""
        return bool(instance.latitude and instance.longitude)
    
    def _get_maps_url(self, instance):
        """Helper method để tạo Google Maps URL"""
        if self._get_has_location(instance):
            return f"https://www.google.com/maps?q={instance.latitude},{instance.longitude}"
        elif instance.location_name:
            return f"https://www.google.com/maps/search/{instance.location_name}"
        return None
    
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
    activities_count = serializers.IntegerField( read_only=True)
    total_estimated_cost = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True)

    # Computed fields that need context
    can_view = serializers.SerializerMethodField()
    can_edit = serializers.SerializerMethodField()
    collaborators = UserSummarySerializer(many=True, read_only=True)

    class Meta:
        model = Plan
        fields = [
            'id', 'title', 'description', 'start_date', 'end_date',
            'is_public', 'status', 'plan_type', 'creator', 'group', 'group_id', 'group_name',
            'activities', 'duration_days', 'activities_count', 
            'total_estimated_cost', 'can_view', 'can_edit', 'collaborators',
            'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'creator', 'plan_type', 'created_at', 'updated_at']
    
    def to_representation(self, instance):
        data = super().to_representation(instance)
        # Computed fields using to_representation for better performance
        data['duration_display'] = self._get_duration_display(instance)
        data['status_display'] = self._get_status_display(instance)
        return data
    
    def _get_duration_display(self, instance):
        """Helper method để tính duration display"""
        days = instance.duration_days
        if days == 0:
            return "Chưa xác định"
        elif days == 1:
            return "1 ngày"
        else:
            return f"{days} ngày"
    
    def _get_status_display(self, instance):
        """Helper method để hiển thị status với icon"""
        status_map = {
            'upcoming': '⏳ Sắp bắt đầu',
            'ongoing': '🏃 Đang diễn ra',
            'completed': '✅ Đã hoàn thành',
            'cancelled': '❌ Đã hủy',
        }
        return status_map.get(instance.status, instance.status)
    
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
    
    class Meta:
        model = Plan
        fields = [
            'id', 'title', 'start_date', 'end_date', 'is_public', 'status',
            'plan_type', 'creator', 'group_name', 'created_at'
        ]
    
    def to_representation(self, instance):
        data = super().to_representation(instance)
        # Computed fields using to_representation for better performance
        data['duration_days'] = instance.duration_days
        data['activities_count'] = instance.activities_count
        data['status_display'] = self._get_status_display(instance)
        data['duration_display'] = self._get_duration_display(instance)
        return data
    
    def _get_duration_display(self, instance):
        """Helper method để tính duration display"""
        days = instance.duration_days
        if days == 0:
            return "Chưa xác định"
        elif days == 1:
            return "1 ngày"
        else:
            return f"{days} ngày"
    
    def _get_status_display(self, instance):
        """Helper method để hiển thị status với icon"""
        status_map = {
            'upcoming': '⏳ Sắp bắt đầu',
            'ongoing': '🏃 Đang diễn ra',
            'completed': '✅ Đã hoàn thành',
            'cancelled': '❌ Đã hủy',
        }
        return status_map.get(instance.status, instance.status)
    
    
class ChatMessageSerializer(serializers.ModelSerializer):
    """Serializer cho ChatMessage với Cloudinary attachment support - OPTIMIZED"""
    sender = UserSerializer(read_only=True)
    reply_to = serializers.SerializerMethodField()
    
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
    
    def to_representation(self, instance):
        data = super().to_representation(instance)
        # Computed fields using to_representation for better performance
        data['attachment_size_display'] = self._get_attachment_size_display(instance)
        data['attachment_url'] = self._get_attachment_url(instance)
        data['location_url'] = self._get_location_url(instance)
        return data
    
    def _get_attachment_size_display(self, instance):
        """Helper method để format attachment size"""
        if not instance.attachment_size:
            return None
        
        # Convert bytes to human readable format
        size = instance.attachment_size
        for unit in ['B', 'KB', 'MB', 'GB']:
            if size < 1024:
                return f"{size:.1f} {unit}"
            size /= 1024
        return f"{size:.1f} TB"
    
    def _get_attachment_url(self, instance):
        """Helper method để get Cloudinary attachment URL"""
        if instance.attachment:
            if hasattr(instance.attachment, 'build_url'):
                return instance.attachment.build_url()
            return instance.attachment.url
        return None
    
    def _get_location_url(self, instance):
        """Helper method để tạo Google Maps URL cho location"""
        if instance.message_type == 'location' and instance.latitude and instance.longitude:
            return f"https://www.google.com/maps?q={instance.latitude},{instance.longitude}"
        return None
    
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
    
    def get_attachment_thumbnail(self, obj):
        """Get attachment thumbnail for images"""
        if obj.attachment and obj.message_type == 'image':
            if hasattr(obj.attachment, 'build_url'):
                return obj.attachment.build_url(
                    width=300, height=300, crop='fill', gravity='center'
                )
            return obj.attachment.url
        return None
    
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
                'display_name': friend_user.get_full_name() or friend_user.username,
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






