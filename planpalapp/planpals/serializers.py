from rest_framework import serializers
from django.contrib.auth import get_user_model
from django.db import models
from django.utils import timezone
from django.core.cache import cache
from .models import (
    Plan, Group, GroupMembership, ChatMessage, Conversation,
    Friendship, PlanActivity, MessageReadStatus
)

User = get_user_model()


class UserSerializer(serializers.ModelSerializer):
    """
    Full User serializer - optimized with property-based fields
    Business logic in model, presentation logic here
    """
    
    # Use model properties directly for computed fields
    online_status = serializers.CharField(source='online_status', read_only=True)
    avatar_url = serializers.CharField(source='avatar_url', read_only=True)
    has_avatar = serializers.BooleanField(source='has_avatar', read_only=True)
    is_recently_online = serializers.BooleanField(source='is_recently_online', read_only=True)
    
    # Count fields - use with_cached_counts() for optimization
    plans_count = serializers.IntegerField(read_only=True)
    personal_plans_count = serializers.IntegerField(read_only=True)
    group_plans_count = serializers.IntegerField(read_only=True)
    groups_count = serializers.IntegerField(read_only=True)
    friends_count = serializers.IntegerField(read_only=True)
    unread_messages_count = serializers.IntegerField(read_only=True)

    class Meta:
        model = User
        fields = [
            'id', 'username', 'email', 'first_name', 'last_name',
            'phone_number', 'avatar', 'avatar_url', 'has_avatar',
            'date_of_birth', 'bio', 'is_online', 'last_seen', 
            'is_recently_online', 'online_status',
            'plans_count', 'personal_plans_count', 'group_plans_count', 
            'groups_count', 'friends_count', 'unread_messages_count', 
            'date_joined', 'is_active'
        ]
        read_only_fields = ['id', 'date_joined', 'last_seen', 'is_online']
    
    def to_representation(self, instance):
        """Add presentation-only computed fields"""
        data = super().to_representation(instance)
        data['full_name'] = instance.get_full_name() or instance.username
        data['initials'] = self._get_initials(instance)
        return data
    
    def _get_initials(self, instance):
        """Helper method for UI initials display"""
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
    """Lightweight User serializer for nested representations"""
    avatar_url = serializers.CharField(source='avatar_url', read_only=True)
    has_avatar = serializers.BooleanField(source='has_avatar', read_only=True)
    online_status = serializers.CharField(source='online_status', read_only=True)
    
    class Meta:
        model = User
        fields = [
            'id', 'username', 'first_name', 'last_name', 'email',
            'is_online', 'online_status', 'avatar_url', 'has_avatar',
            'date_joined', 'last_seen'
        ]
    
    def to_representation(self, instance):
        """Add presentation-only computed fields"""
        data = super().to_representation(instance)
        data['full_name'] = instance.get_full_name() or instance.username
        data['initials'] = self._get_initials(instance)
        return data
    
    def _get_initials(self, instance):
        """Helper method for UI initials display"""
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
    """
    Full group detail serializer - optimized with model properties
    Business logic in model, presentation logic here
    """
    admin = UserSummarySerializer(read_only=True)
    memberships = GroupMembershipSerializer(many=True, read_only=True)
    
    # Use model properties directly
    member_count = serializers.IntegerField(source='member_count', read_only=True)
    plans_count = serializers.IntegerField(read_only=True)
    active_plans_count = serializers.IntegerField(read_only=True)
    
    # Avatar and cover properties from model
    avatar_url = serializers.CharField(source='avatar_url', read_only=True)
    has_avatar = serializers.BooleanField(source='has_avatar', read_only=True)
    cover_image_url = serializers.CharField(source='cover_image_url', read_only=True)
    has_cover_image = serializers.BooleanField(source='has_cover_image', read_only=True)
    
    # Context-dependent fields
    is_member = serializers.SerializerMethodField()
    user_role = serializers.SerializerMethodField()
    can_edit = serializers.SerializerMethodField()
    can_delete = serializers.SerializerMethodField()

    class Meta:
        model = Group
        fields = [
            'id', 'name', 'description', 'avatar', 'cover_image',
            'avatar_url', 'has_avatar', 'cover_image_url', 'has_cover_image',
            'admin', 'memberships', 'member_count', 'plans_count', 'active_plans_count',
            'is_active', 'is_member', 'user_role', 'can_edit', 'can_delete', 
            'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'admin', 'created_at', 'updated_at']
    
    def to_representation(self, instance):
        """Add presentation-only computed fields"""
        data = super().to_representation(instance)
        data['initials'] = self._get_group_initials(instance)
        return data
    
    def _get_group_initials(self, instance):
        """Helper method for UI initials display"""
        if not instance.name:
            return 'G'
        
        parts = [p for p in instance.name.split() if p]
        if len(parts) >= 2:
            return (parts[0][0] + parts[1][0]).upper()
        
        return instance.name[:2].upper()
    
    def get_is_member(self, obj):
        """Check if current user is member - use model method"""
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            return obj.is_member(request.user)
        return False
    
    def get_user_role(self, obj):
        """Get current user's role in group"""
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            try:
                membership = obj.memberships.get(user=request.user)
                return membership.role
            except GroupMembership.DoesNotExist:
                return None
        return None
    
    def get_can_edit(self, obj):
        """Check if current user can edit group - use model method"""
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            return obj.is_admin(request.user)
        return False
    
    def get_can_delete(self, obj):
        """Check if current user can delete group"""
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            return obj.admin == request.user
        return False
    
    def create(self, validated_data):
        """Create group with auto-setup - business logic in model"""
        request = self.context.get('request')
        validated_data['admin'] = request.user
        return super().create(validated_data)


class GroupCreateSerializer(serializers.ModelSerializer):
    """
    Optimized serializer for group creation with initial members
    Business logic moved to model methods
    """
    # Use model properties directly
    avatar_url = serializers.CharField(source='avatar_url', read_only=True)
    has_avatar = serializers.BooleanField(source='has_avatar', read_only=True)
    cover_image_url = serializers.CharField(source='cover_image_url', read_only=True)
    has_cover_image = serializers.BooleanField(source='has_cover_image', read_only=True)
    member_count = serializers.IntegerField(source='member_count', read_only=True)
    
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
            'id', 'name', 'description', 'avatar', 'cover_image', 'initial_members',
            'avatar_url', 'has_avatar', 'cover_image_url', 'has_cover_image',
            'member_count', 'admin', 'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'admin', 'created_at', 'updated_at']

    def to_representation(self, instance):
        """Add presentation-only computed fields"""
        data = super().to_representation(instance)
        data['initials'] = self._get_group_initials(instance)
        return data
    
    def _get_group_initials(self, instance):
        """Helper method for UI initials display"""
        if not instance.name:
            return 'G'
        
        parts = [p for p in instance.name.split() if p]
        if len(parts) >= 2:
            return (parts[0][0] + parts[1][0]).upper()
        
        return instance.name[:2].upper()

    def validate_name(self, value):
        """Validate group name"""
        if len(value.strip()) < 3:
            raise serializers.ValidationError("Tên nhóm phải có ít nhất 3 ký tự")
        return value.strip()
    
    def validate_initial_members(self, value):
        """Validate initial members list - use model methods"""
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
        
        # Use model method for validation
        for user_id in value:
            try:
                target_user = User.objects.get(id=user_id)
            except User.DoesNotExist:
                raise serializers.ValidationError(f"User với ID {user_id} không tồn tại")
            
            if not Friendship.are_friends(current_user, target_user):
                raise serializers.ValidationError(
                    f"Chỉ có thể thêm bạn bè vào nhóm. {target_user.username} chưa phải là bạn bè"
                )
        return value
    
    def create(self, validated_data):
        """Create group with initial members - delegate to model"""
        request = self.context.get('request')
        initial_members = validated_data.pop('initial_members')
        validated_data['admin'] = request.user
        
        group = super().create(validated_data)
        
        # Add initial members using model method
        for user_id in initial_members:
            user = User.objects.get(id=user_id)
            group.add_member(user, role='member')
        
        return group


class GroupSummarySerializer(serializers.ModelSerializer):
    """
    Lightweight group summary for list views
    Uses model properties for optimization
    """
    member_count = serializers.IntegerField(source='member_count', read_only=True)
    avatar_url = serializers.CharField(source='avatar_url', read_only=True)
    
    class Meta:
        model = Group
        fields = [
            'id', 'name', 'description', 'member_count', 
            'avatar_url', 'created_at'
        ]
    
    def to_representation(self, instance):
        """Add presentation-only computed fields"""
        data = super().to_representation(instance)
        data['initials'] = self._get_group_initials(instance)
        return data
    
    def _get_group_initials(self, instance):
        """Helper method for UI initials display"""
        if not instance.name:
            return 'G'
        
        parts = [p for p in instance.name.split() if p]
        if len(parts) >= 2:
            return (parts[0][0] + parts[1][0]).upper()
        
        return instance.name[:2].upper()


class PlanActivitySerializer(serializers.ModelSerializer):
    """
    Optimized PlanActivity serializer
    Uses model properties where possible, presentation logic here
    """
    # Use model properties directly
    duration_hours = serializers.FloatField(source='duration_hours', read_only=True)
    has_location = serializers.BooleanField(source='has_location', read_only=True)

    class Meta:
        model = PlanActivity
        fields = [
            'id', 'plan', 'title', 'description', 'activity_type',
            'start_time', 'end_time', 'location_name', 'location_address', 
            'latitude', 'longitude', 'goong_place_id', 'estimated_cost', 
            'notes', 'order', 'is_completed', 'duration_hours', 'has_location',
            'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'created_at', 'updated_at']
    
    def to_representation(self, instance):
        """Add presentation-only computed fields"""
        data = super().to_representation(instance)
        data['duration_display'] = self._get_duration_display(instance)
        data['activity_type_display'] = self._get_activity_type_display(instance)
        data['maps_url'] = self._get_maps_url(instance)
        return data
    
    def _get_duration_display(self, instance):
        """Helper method for duration display formatting"""
        hours = instance.duration_hours
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
        """Helper method for activity type with icons"""
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
    
    def _get_maps_url(self, instance):
        """Helper method for Google Maps URL generation"""
        if instance.has_location:
            return f"https://www.google.com/maps?q={instance.latitude},{instance.longitude}"
        elif instance.location_name:
            return f"https://www.google.com/maps/search/{instance.location_name}"
        return None
    
    def validate(self, attrs):
        """Basic validation - complex logic delegated to model"""
        start_time = attrs.get('start_time')
        end_time = attrs.get('end_time')
        
        # Basic time validation
        if start_time and end_time and end_time <= start_time:
            raise serializers.ValidationError(
                "Thời gian kết thúc phải sau thời gian bắt đầu"
            )
        
        # Delegate complex validation to model
        plan = attrs.get('plan') or (self.instance and self.instance.plan)
        if plan and start_time and end_time:
            # Use model method for overlap checking
            if hasattr(plan, 'check_activity_overlap'):
                exclude_id = self.instance.id if self.instance else None
                if plan.check_activity_overlap(start_time, end_time, exclude_id):
                    raise serializers.ValidationError(
                        "Hoạt động bị trùng thời gian với hoạt động khác"
                    )
        
        return attrs


class PlanSerializer(serializers.ModelSerializer):
    """
    Optimized Plan serializer
    Uses model properties and methods, presentation logic here
    """
    creator = UserSummarySerializer(read_only=True)
    group = GroupSummarySerializer(read_only=True)
    activities = PlanActivitySerializer(many=True, read_only=True)
    
    # Write fields
    group_id = serializers.UUIDField(write_only=True, required=False, allow_null=True)
    # Convenience read field for frontend badges
    group_name = serializers.CharField(source='group.name', read_only=True)
    
    # Use model properties directly
    duration_days = serializers.IntegerField(source='duration_days', read_only=True)
    activities_count = serializers.IntegerField(source='activities_count', read_only=True)
    total_estimated_cost = serializers.DecimalField(
        source='total_estimated_cost', 
        max_digits=12, 
        decimal_places=2, 
        read_only=True
    )

    # Context-dependent fields
    can_view = serializers.SerializerMethodField()
    can_edit = serializers.SerializerMethodField()
    collaborators = serializers.SerializerMethodField()

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
        """Add presentation-only computed fields"""
        data = super().to_representation(instance)
        data['duration_display'] = self._get_duration_display(instance)
        data['status_display'] = self._get_status_display(instance)
        return data
    
    def _get_duration_display(self, instance):
        """Helper method for duration display formatting"""
        days = instance.duration_days
        if days == 0:
            return "Chưa xác định"
        elif days == 1:
            return "1 ngày"
        else:
            return f"{days} ngày"
    
    def _get_status_display(self, instance):
        """Helper method for status display with icons"""
        status_map = {
            'upcoming': '⏳ Sắp bắt đầu',
            'ongoing': '🏃 Đang diễn ra',
            'completed': '✅ Đã hoàn thành',
            'cancelled': '❌ Đã hủy',
        }
        return status_map.get(instance.status, instance.status)
    
    def get_can_view(self, obj):
        """Check if current user can view plan - use model methods"""
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            user = request.user
            
            # Creator can always view
            if obj.creator == user:
                return True
            
            # Public plans are viewable by everyone
            if obj.is_public:
                return True
            
            # Group plans: members can view
            if obj.is_group_plan() and obj.group:
                return obj.group.is_member(user)
            
            return False
        return obj.is_public
    
    
    def get_can_edit(self, obj):
        """Check if current user can edit plan - use model methods"""
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            user = request.user
            
            # Creator can always edit
            if obj.creator == user:
                return True
            
            # Group plans: admins can edit
            if obj.is_group_plan() and obj.group:
                return obj.group.is_admin(user)
            
            return False
        return False
    
    def get_collaborators(self, obj):
        """Get plan collaborators - use model property"""
        collaborators = obj.collaborators
        return UserSummarySerializer(collaborators, many=True, context=self.context).data
    
    def validate(self, attrs):
        """Basic validation - delegate complex logic to model"""
        if attrs.get('start_date') and attrs.get('end_date'):
            if attrs['end_date'] <= attrs['start_date']:
                raise serializers.ValidationError(
                    "Ngày kết thúc phải sau ngày bắt đầu"
                )
        
        # Validate group access using model methods
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
        """Create plan with proper setup"""
        request = self.context.get('request')
        validated_data['creator'] = request.user
        return super().create(validated_data)

    def update(self, instance, validated_data):
        """Update plan respecting business rules"""
        if 'group_id' in validated_data:
            group_id = validated_data.pop('group_id')
            if instance.plan_type == 'personal':
                validated_data['group'] = None
            elif group_id is not None:
                try:
                    group = Group.objects.get(id=group_id)
                    validated_data['group'] = group
                except Group.DoesNotExist:
                    raise serializers.ValidationError("Nhóm không tồn tại")
        
        return super().update(instance, validated_data)


class PlanCreateSerializer(serializers.ModelSerializer):
    """
    Simplified serializer for plan creation
    Business logic delegated to model methods
    """
    plan_type = serializers.ChoiceField(
        choices=[('personal', 'Cá nhân'), ('group', 'Nhóm')], 
        required=True
    )
    group_id = serializers.UUIDField(required=False, allow_null=True)
    
    class Meta:
        model = Plan
        fields = [
            'title', 'description', 'start_date', 'end_date', 
            'is_public', 'plan_type', 'group_id'
        ]

    def validate_title(self, value):
        """Validate plan title"""
        if len(value.strip()) < 3:
            raise serializers.ValidationError("Tiêu đề phải có ít nhất 3 ký tự")
        return value.strip()

    def validate(self, attrs):
        """Validate plan creation data"""
        if attrs.get('start_date') and attrs.get('end_date'):
            if attrs['end_date'] <= attrs['start_date']:
                raise serializers.ValidationError(
                    "Ngày kết thúc phải sau ngày bắt đầu"
                )
        
        plan_type = attrs.get('plan_type')
        group_id = attrs.get('group_id')
        
        if plan_type == 'group':
            if not group_id:
                raise serializers.ValidationError("Kế hoạch nhóm phải chọn nhóm")
            
            # Validate group access using model methods
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
            if group_id:
                raise serializers.ValidationError("Kế hoạch cá nhân không thể thuộc nhóm")
        else:
            raise serializers.ValidationError("Loại kế hoạch không hợp lệ")
        
        return attrs

    def create(self, validated_data):
        """Create plan with proper setup"""
        # Set default status
        validated_data['status'] = 'upcoming'
        
        # Handle group assignment
        plan_type = validated_data.get('plan_type')
        group_id = validated_data.pop('group_id', None)
        
        if plan_type == 'group' and group_id:
            validated_data['group'] = Group.objects.get(id=group_id)
        else:
            validated_data['group'] = None
        
        # Set creator
        request = self.context.get('request')
        validated_data['creator'] = request.user
        
        return super().create(validated_data)


class PlanSummarySerializer(serializers.ModelSerializer):
    """
    Lightweight Plan summary for list views
    Uses model properties for optimization
    """
    creator = UserSummarySerializer(read_only=True)
    group_name = serializers.CharField(source='group.name', read_only=True)
    
    # Use model properties directly
    duration_days = serializers.IntegerField(source='duration_days', read_only=True)
    activities_count = serializers.IntegerField(source='activities_count', read_only=True)
    
    class Meta:
        model = Plan
        fields = [
            'id', 'title', 'start_date', 'end_date', 'is_public', 'status',
            'plan_type', 'creator', 'group_name', 'duration_days', 'activities_count',
            'created_at'
        ]
    
    def to_representation(self, instance):
        """Add presentation-only computed fields"""
        data = super().to_representation(instance)
        data['status_display'] = self._get_status_display(instance)
        data['duration_display'] = self._get_duration_display(instance)
        return data
    
    def _get_duration_display(self, instance):
        """Helper method for duration display formatting"""
        days = instance.duration_days
        if days == 0:
            return "Chưa xác định"
        elif days == 1:
            return "1 ngày"
        else:
            return f"{days} ngày"
    
    def _get_status_display(self, instance):
        """Helper method for status display with icons"""
        status_map = {
            'upcoming': '⏳ Sắp bắt đầu',
            'ongoing': '🏃 Đang diễn ra',
            'completed': '✅ Đã hoàn thành',
            'cancelled': '❌ Đã hủy',
        }
        return status_map.get(instance.status, instance.status)
    
class ChatMessageSerializer(serializers.ModelSerializer):
    """
    Optimized ChatMessage serializer with Cloudinary support
    Uses model properties where possible, presentation logic here
    """
    sender = UserSummarySerializer(read_only=True)
    reply_to = serializers.SerializerMethodField()
    
    # Use model properties directly where available
    attachment_url = serializers.CharField(source='attachment_url', read_only=True)
    attachment_size_display = serializers.CharField(source='attachment_size_display', read_only=True)
    location_url = serializers.CharField(source='location_url', read_only=True)
    
    # Context-dependent fields
    can_edit = serializers.SerializerMethodField()
    can_delete = serializers.SerializerMethodField()
    attachment_thumbnail = serializers.SerializerMethodField()
    
    class Meta:
        model = ChatMessage
        fields = [
            'id', 'conversation', 'group', 'sender', 'message_type', 'content',
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
        """Get reply to message info"""
        if obj.reply_to:
            return {
                'id': obj.reply_to.id,
                'content': obj.reply_to.content[:100] + ('...' if len(obj.reply_to.content) > 100 else ''),
                'sender': obj.reply_to.sender.username if obj.reply_to.sender else 'System',
                'message_type': obj.reply_to.message_type
            }
        return None
    
    def get_can_edit(self, obj):
        """Check if current user can edit message"""
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            # Only sender can edit their own text messages
            return (obj.sender == request.user and 
                    obj.message_type == 'text' and 
                    not obj.is_deleted)
        return False
    
    def get_can_delete(self, obj):
        """Check if current user can delete message"""
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            user = request.user
            # Sender can delete their own messages
            if obj.sender == user:
                return True
            # Group admin can delete messages in group
            if obj.conversation and obj.conversation.group:
                return obj.conversation.group.is_admin(user)
        return False
    
    def get_attachment_thumbnail(self, obj):
        """Get attachment thumbnail for images"""
        if obj.attachment and obj.message_type == 'image':
            # Use Cloudinary transformation for thumbnail
            try:
                return obj.attachment.build_url(
                    width=150, height=150, crop='fill', quality='auto:good'
                )
            except:
                return obj.attachment_url
        return None
    
    def validate(self, attrs):
        """Basic validation - delegate complex logic to model"""
        # Location messages need coordinates
        if attrs.get('message_type') == 'location':
            if not (attrs.get('latitude') and attrs.get('longitude')):
                raise serializers.ValidationError(
                    "Location messages phải có coordinates"
                )
        return attrs
    
    def create(self, validated_data):
        """Create message with proper setup"""
        request = self.context.get('request')
        validated_data['sender'] = request.user
        return super().create(validated_data)


class FriendshipSerializer(serializers.ModelSerializer):
    """
    Optimized Friendship serializer 
    Uses canonical friendship model and efficient representation
    """
    # Note: user_a and user_b are internal canonical fields
    # We expose logical user/friend based on context
    user = serializers.SerializerMethodField()
    friend = serializers.SerializerMethodField()
    initiator = UserSummarySerializer(read_only=True)
    
    class Meta:
        model = Friendship
        fields = [
            'id', 'user', 'friend', 'initiator', 'status',
            'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'user', 'friend', 'initiator', 'created_at', 'updated_at']
    
    def get_user(self, instance):
        """Get the current user in the friendship"""
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            current_user = request.user
            # Always return current user as 'user'
            if current_user in [instance.user_a, instance.user_b]:
                return UserSummarySerializer(current_user, context=self.context).data
        # Fallback to initiator
        return UserSummarySerializer(instance.initiator, context=self.context).data
    
    def get_friend(self, instance):
        """Get the other user (friend) in the friendship"""
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            current_user = request.user
            other_user = instance.get_other_user(current_user)
            if other_user:
                return UserSummarySerializer(other_user, context=self.context).data
        # Fallback
        non_initiator = instance.user_b if instance.initiator == instance.user_a else instance.user_a
        return UserSummarySerializer(non_initiator, context=self.context).data


class FriendRequestSerializer(serializers.Serializer):
    """
    Optimized friend request serializer
    Uses model methods for validation and creation
    """
    friend_id = serializers.UUIDField()
    message = serializers.CharField(max_length=200, required=False, allow_blank=True)
    
    def validate_friend_id(self, value):
        """Validate friend request using model methods"""
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
        
        # Use model method for existing friendship check
        existing = Friendship.between_users(user, friend_user)
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
        """Create friendship using model method"""
        request = self.context['request']
        # Use model class method for creation
        friendship = Friendship.create_request(
            initiator=request.user,
            receiver=self.validated_friend
        )
        return friendship


class FriendsListSerializer(serializers.ModelSerializer):
    """
    Optimized serializer for friends list
    Uses context for efficient data loading
    """
    friendship_since = serializers.SerializerMethodField()
    mutual_friends_count = serializers.SerializerMethodField()
    
    # Use model properties directly
    avatar_url = serializers.CharField(source='avatar_url', read_only=True)
    online_status = serializers.CharField(source='online_status', read_only=True)
    
    class Meta:
        model = User
        fields = [
            'id', 'username', 'first_name', 'last_name', 
            'avatar_url', 'is_online', 'online_status', 'last_seen', 
            'friendship_since', 'mutual_friends_count'
        ]
    
    def to_representation(self, instance):
        """Add presentation-only computed fields"""
        data = super().to_representation(instance)
        data['full_name'] = instance.get_full_name() or instance.username
        data['initials'] = self._get_initials(instance)
        return data
    
    def _get_initials(self, instance):
        """Helper method for UI initials display"""
        if instance.first_name and instance.last_name:
            return f"{instance.first_name[0]}{instance.last_name[0]}".upper()
        elif instance.first_name:
            return instance.first_name[0].upper()
        return instance.username[0].upper() if instance.username else "U"
    
    def get_friendship_since(self, obj):
        """Get friendship date - optimized with context"""
        friendships_map = self.context.get('friendships_map', {})
        friendship = friendships_map.get(obj.id)
        return friendship.created_at if friendship else None
    
    def get_mutual_friends_count(self, obj):
        """Get mutual friends count - optimized with context"""
        # This can be pre-calculated and passed in context for better performance
        mutual_count = self.context.get('mutual_friends_count', {})
        return mutual_count.get(obj.id, 0)


class MessageReadStatusSerializer(serializers.ModelSerializer):
    """
    Optimized MessageReadStatus serializer
    Uses lightweight user representation
    """
    user = UserSummarySerializer(read_only=True)
    
    class Meta:
        model = MessageReadStatus
        fields = ['id', 'message', 'user', 'read_at']
        read_only_fields = ['id', 'user', 'read_at']


# === Conversation Serializers ===

class ConversationSerializer(serializers.ModelSerializer):
    """
    Optimized Conversation serializer
    Uses model properties and methods for efficiency
    """
    participants = UserSummarySerializer(many=True, read_only=True)
    group = GroupSummarySerializer(read_only=True)
    
    # Use model properties directly
    display_name = serializers.CharField(source='display_name', read_only=True)
    unread_count = serializers.SerializerMethodField()
    last_message = serializers.SerializerMethodField()
    
    class Meta:
        model = Conversation
        fields = [
            'id', 'conversation_type', 'name', 'display_name', 'avatar',
            'group', 'participants', 'last_message_at', 'is_active',
            'unread_count', 'last_message', 'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'created_at', 'updated_at', 'last_message_at']
    
    def get_unread_count(self, obj):
        """Get unread messages count for current user"""
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            return obj.get_unread_count_for_user(request.user)
        return 0
    
    def get_last_message(self, obj):
        """Get last message info"""
        # Use prefetch_related or select_related for optimization
        last_message = getattr(obj, 'prefetched_last_message', None)
        if not last_message:
            # Fallback query
            last_message = obj.messages.filter(is_deleted=False).order_by('-created_at').first()
        
        if last_message:
            return {
                'id': last_message.id,
                'content': last_message.content[:100] + ('...' if len(last_message.content) > 100 else ''),
                'message_type': last_message.message_type,
                'sender': last_message.sender.username if last_message.sender else 'System',
                'created_at': last_message.created_at
            }
        return None






