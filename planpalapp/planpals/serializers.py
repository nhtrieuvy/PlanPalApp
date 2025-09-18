from rest_framework import serializers
from django.contrib.auth import get_user_model
from .models import (
    Plan, Group, GroupMembership, ChatMessage, Conversation,
    Friendship, PlanActivity, MessageReadStatus
)



User = get_user_model()


class UserSerializer(serializers.ModelSerializer):    
    # Use model properties directly for computed fields
    online_status = serializers.CharField(read_only=True)
    avatar_url = serializers.CharField(read_only=True)
    has_avatar = serializers.BooleanField(read_only=True)
    is_recently_online = serializers.BooleanField(read_only=True)
    
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
        data = super().to_representation(instance)
        data['full_name'] = instance.get_full_name() or instance.username
        data['initials'] = self._get_initials(instance)
        return data
    
    def _get_initials(self, instance):
        if instance.first_name and instance.last_name:
            return f"{instance.first_name[0]}{instance.last_name[0]}".upper()
        elif instance.first_name:
            return instance.first_name[0].upper()
        return instance.username[0].upper() if instance.username else "U"


class UserCreateSerializer(serializers.ModelSerializer):
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
    avatar_url = serializers.CharField(read_only=True)
    has_avatar = serializers.BooleanField(read_only=True)
    online_status = serializers.CharField(read_only=True)
    
    class Meta:
        model = User
        fields = [
            'id', 'username', 'first_name', 'last_name', 'email',
            'is_online', 'online_status', 'avatar_url', 'has_avatar',
            'date_joined', 'last_seen'
        ]
    
    def to_representation(self, instance):
        data = super().to_representation(instance)
        data['full_name'] = instance.get_full_name() or instance.username
        data['initials'] = self._get_initials(instance)
        return data
    
    def _get_initials(self, instance):
        if instance.first_name and instance.last_name:
            return f"{instance.first_name[0]}{instance.last_name[0]}".upper()
        elif instance.first_name:
            return instance.first_name[0].upper()
        return instance.username[0].upper() if instance.username else "U"


class GroupMembershipSerializer(serializers.ModelSerializer):
    user = UserSummarySerializer(read_only=True)
    
    class Meta:
        model = GroupMembership
        fields = [
            'id', 'user', 'role', 'created_at'
        ]
        read_only_fields = ['id', 'created_at']


class GroupSerializer(serializers.ModelSerializer):
    admin = UserSummarySerializer(read_only=True)
    memberships = GroupMembershipSerializer(many=True, read_only=True)
    
    # Use model properties directly
    member_count = serializers.IntegerField(read_only=True)
    plans_count = serializers.IntegerField(read_only=True)
    active_plans_count = serializers.IntegerField(read_only=True)
    
    # Avatar and cover properties from model
    avatar_url = serializers.CharField(read_only=True)
    has_avatar = serializers.BooleanField(read_only=True)
    cover_image_url = serializers.CharField(read_only=True)
    has_cover_image = serializers.BooleanField(read_only=True)
    
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
        data = super().to_representation(instance)
        data['initials'] = self._get_group_initials(instance)
        return data
    
    def _get_group_initials(self, instance):
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
            return obj.get_user_role(request.user)
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
        return super().create(validated_data)


class GroupCreateSerializer(serializers.ModelSerializer):
    # Use model properties directly
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
            'id', 'name', 'description', 'avatar', 'cover_image', 'initial_members',
            'avatar_url', 'has_avatar', 'cover_image_url', 'has_cover_image',
            'member_count', 'admin', 'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'admin', 'created_at', 'updated_at']

    def to_representation(self, instance):
        data = super().to_representation(instance)
        data['initials'] = self._get_group_initials(instance)
        return data
    
    def _get_group_initials(self, instance):
        if not instance.name:
            return 'G'
        
        parts = [p for p in instance.name.split() if p]
        if len(parts) >= 2:
            return (parts[0][0] + parts[1][0]).upper()
        
        return instance.name[:2].upper()

    def validate_name(self, value):
        if len(value.strip()) < 3:
            raise serializers.ValidationError("Group name must be at least 3 characters")
        return value.strip()
    
    def validate_initial_members(self, value):
        if len(value) < 2:
            raise serializers.ValidationError("At least 2 friends are required to create a group")
        
        if len(value) != len(set(value)):
            raise serializers.ValidationError("Cannot add the same person multiple times")
        
        request = self.context.get('request')
        if not request:
            raise serializers.ValidationError("Invalid context")
        
        current_user = request.user
        
        if str(current_user.id) in [str(uid) for uid in value]:
            raise serializers.ValidationError("Cannot add yourself to the group")
        
        for user_id in value:
            try:
                target_user = User.objects.get(id=user_id)
            except User.DoesNotExist:
                raise serializers.ValidationError(f"User with ID {user_id} does not exist")
            
            if not Friendship.are_friends(current_user, target_user):
                raise serializers.ValidationError(
                    f"Only friends can be added to the group. {target_user.username} is not a friend"
                )
        return value
    
    def create(self, validated_data):
        request = self.context.get('request')
        initial_members = validated_data.pop('initial_members')
        validated_data['admin'] = request.user
        
        group = super().create(validated_data)
        
        from .services import GroupService
        
        for user_id in initial_members:
            user = User.objects.get(id=user_id)
            GroupService.add_member(group, user, role='member')
        
        return group


class GroupSummarySerializer(serializers.ModelSerializer):
    member_count = serializers.IntegerField(read_only=True)
    avatar_url = serializers.CharField(read_only=True)
    
    class Meta:
        model = Group
        fields = [
            'id', 'name', 'description', 'member_count', 
            'avatar_url', 'created_at'
        ]
    
    def to_representation(self, instance):
        data = super().to_representation(instance)
        data['initials'] = self._get_group_initials(instance)
        return data
    
    def _get_group_initials(self, instance):
        if not instance.name:
            return 'G'
        
        parts = [p for p in instance.name.split() if p]
        if len(parts) >= 2:
            return (parts[0][0] + parts[1][0]).upper()
        
        return instance.name[:2].upper()


class PlanActivitySummarySerializer(serializers.ModelSerializer):
    """
    Lightweight serializer for schedule overview - only essential fields for performance
    """
    # Essential display fields
    duration_display = serializers.SerializerMethodField()
    activity_type_display = serializers.SerializerMethodField()
    has_location = serializers.BooleanField(read_only=True)
    
    class Meta:
        model = PlanActivity
        fields = [
            'id', 'title', 'activity_type', 'activity_type_display',
            'start_time', 'end_time', 'duration_display',
            'estimated_cost', 'is_completed', 'has_location', 'order'
        ]
    
    def get_duration_display(self, instance):
        """Get formatted duration display"""
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
    
    def get_activity_type_display(self, instance):
        """Get activity type display name"""
        type_names = {
            'eating': 'Ăn uống',
            'resting': 'Nghỉ ngơi', 
            'moving': 'Di chuyển',
            'sightseeing': 'Tham quan',
            'shopping': 'Mua sắm',
            'entertainment': 'Giải trí',
            'event': 'Sự kiện',
            'sport': 'Thể thao',
            'study': 'Học tập',
            'work': 'Công việc',
            'other': 'Khác',
        }
        return type_names.get(instance.activity_type, instance.activity_type)


class PlanActivitySerializer(serializers.ModelSerializer):
    # Use model properties directly
    duration_hours = serializers.FloatField(read_only=True)
    has_location = serializers.BooleanField(read_only=True)

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
        data = super().to_representation(instance)
        data['duration_display'] = self._get_duration_display(instance)
        data['activity_type_display'] = self._get_activity_type_display(instance)
        data['maps_url'] = self._get_maps_url(instance)
        return data
    
    def _get_duration_display(self, instance):
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
        if instance.has_location:
            return f"https://www.google.com/maps?q={instance.latitude},{instance.longitude}"
        elif instance.location_name:
            return f"https://www.google.com/maps/search/{instance.location_name}"
        return None
    
    def validate(self, attrs):
        start_time = attrs.get('start_time')
        end_time = attrs.get('end_time')
        
        # Validate required fields
        if not start_time:
            raise serializers.ValidationError({'start_time': 'Start time is required'})
        if not end_time:
            raise serializers.ValidationError({'end_time': 'End time is required'})
        
        # Basic time validation - end time must be after start time
        if end_time <= start_time:
            raise serializers.ValidationError({
                'end_time': 'End time must be after start time'
            })
        
        # Duration validation (max 24 hours)
        duration = end_time - start_time
        if duration.total_seconds() > 24 * 3600:
            raise serializers.ValidationError({
                'end_time': 'Activity duration cannot exceed 24 hours'
            })
        
        # Simple coordinate validation if provided
        latitude = attrs.get('latitude')
        longitude = attrs.get('longitude')
        if latitude is not None and not (-90 <= latitude <= 90):
            raise serializers.ValidationError({
                'latitude': 'Latitude must be between -90 and 90'
            })
        if longitude is not None and not (-180 <= longitude <= 180):
            raise serializers.ValidationError({
                'longitude': 'Longitude must be between -180 and 180'
            })
        
        # Validate estimated cost
        estimated_cost = attrs.get('estimated_cost')
        if estimated_cost is not None and estimated_cost < 0:
            raise serializers.ValidationError({
                'estimated_cost': 'Estimated cost must be non-negative'
            })
        
        return attrs


class PlanActivityCreateSerializer(serializers.ModelSerializer):
    """
    Serializer for creating PlanActivity - simple approach like PlanCreateSerializer
    """
    plan_id = serializers.UUIDField(write_only=True, required=True)
    
    class Meta:
        model = PlanActivity
        fields = [
            'plan_id', 'title', 'description', 'activity_type',
            'start_time', 'end_time', 'location_name', 'location_address',
            'latitude', 'longitude', 'goong_place_id', 'estimated_cost', 'notes'
        ]
    
    def validate(self, attrs):
        plan_id = attrs.get('plan_id')
        if plan_id:
            try:
                plan = Plan.objects.get(id=plan_id)
                attrs['plan'] = plan
            except Plan.DoesNotExist:
                raise serializers.ValidationError({'plan_id': 'Plan does not exist'})
        return attrs
    
    def create(self, validated_data):
        validated_data.pop('plan_id', None)
        return super().create(validated_data)


class PlanSerializer(serializers.ModelSerializer):
    creator = UserSummarySerializer(read_only=True)
    group = GroupSummarySerializer(read_only=True)
    activities = PlanActivitySerializer(many=True, read_only=True)
    
    # Write fields
    group_id = serializers.UUIDField(write_only=True, required=False, allow_null=True)
    # Convenience read field for frontend badges
    group_name = serializers.CharField(source='group.name', read_only=True)
    
    # Use model properties directly
    duration_days = serializers.IntegerField(read_only=True)
    activities_count = serializers.IntegerField(read_only=True)
    total_estimated_cost = serializers.DecimalField(
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
        data = super().to_representation(instance)
        data['duration_display'] = self._get_duration_display(instance)
        data['status_display'] = self._get_status_display(instance)
        return data
    
    def _get_duration_display(self, instance):
        days = instance.duration_days
        if days == 0:
            return "Chưa xác định"
        elif days == 1:
            return "1 ngày"
        else:
            return f"{days} ngày"
    
    def _get_status_display(self, instance):
        status_map = {
            'upcoming': '⏳ Sắp bắt đầu',
            'ongoing': '🏃 Đang diễn ra',
            'completed': '✅ Đã hoàn thành',
            'cancelled': '❌ Đã hủy',
        }
        return status_map.get(instance.status, instance.status)
    
    def get_can_view(self, obj):
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
        collaborators = obj.collaborators
        return UserSummarySerializer(collaborators, many=True, context=self.context).data
    
    def validate(self, attrs):
        if attrs.get('start_date') and attrs.get('end_date'):
            if attrs['end_date'] <= attrs['start_date']:
                raise serializers.ValidationError(
                    "End time must be after start time"
                )
        
        group_id = attrs.get('group_id')
        instance = getattr(self, 'instance', None)
        if instance:
            if instance.plan_type == 'personal' and group_id:
                raise serializers.ValidationError("Personal plans cannot be assigned to a group")
            if instance.plan_type == 'group' and ('group_id' in attrs) and group_id is None:
                raise serializers.ValidationError("Group plans must belong to a group")

        if group_id:
            try:
                group = Group.objects.get(id=group_id)
                request = self.context.get('request')
                if request and request.user.is_authenticated:
                    if not group.is_member(request.user):
                        raise serializers.ValidationError(
                            "You are not a member of this group"
                        )
            except Group.DoesNotExist:
                raise serializers.ValidationError("Group does not exist")

        return attrs
    
    def create(self, validated_data):
        request = self.context.get('request')
        validated_data['creator'] = request.user
        return super().create(validated_data)

    def update(self, instance, validated_data):
        if 'group_id' in validated_data:
            group_id = validated_data.pop('group_id')
            if instance.plan_type == 'personal':
                validated_data['group'] = None
            elif group_id is not None:
                try:
                    group = Group.objects.get(id=group_id)
                    validated_data['group'] = group
                except Group.DoesNotExist:
                    raise serializers.ValidationError("Group does not exist")
        
        return super().update(instance, validated_data)


class PlanCreateSerializer(serializers.ModelSerializer):
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
        if len(value.strip()) < 3:
            raise serializers.ValidationError("Title must be at least 3 characters")
        return value.strip()

    def validate(self, attrs):
        if attrs.get('start_date') and attrs.get('end_date'):
            if attrs['end_date'] <= attrs['start_date']:
                raise serializers.ValidationError(
                    "End time must be after start time"
                )
        
        plan_type = attrs.get('plan_type')
        group_id = attrs.get('group_id')
        
        if plan_type == 'group':
            if not group_id:
                raise serializers.ValidationError("Group plans must belong to a group")
            
            try:
                group = Group.objects.get(id=group_id)
                request = self.context.get('request')
                if request and request.user.is_authenticated:
                    if not GroupMembership.objects.filter(group=group, user=request.user).exists():
                        raise serializers.ValidationError(
                            "You are not a member of this group"
                        )
                # Store resolved group for the view to use
                attrs['group'] = group
            except Group.DoesNotExist:
                raise serializers.ValidationError("Group does not exist")
        elif plan_type == 'personal':
            if group_id:
                raise serializers.ValidationError("Personal plans cannot belong to a group")
            attrs['group'] = None
        else:
            raise serializers.ValidationError("Invalid plan type")
        
        return attrs

    def create(self, validated_data):
        request = self.context.get('request')
        if request and request.user and not request.user.is_anonymous:
            validated_data['creator'] = request.user
        
        validated_data.pop('group_id', None)
        return super().create(validated_data)


class PlanSummarySerializer(serializers.ModelSerializer):
    creator = UserSummarySerializer(read_only=True)
    group_name = serializers.CharField(source='group.name', read_only=True)
    
    # Use model properties directly
    duration_days = serializers.IntegerField(read_only=True)
    activities_count = serializers.IntegerField(read_only=True)
    
    class Meta:
        model = Plan
        fields = [
            'id', 'title', 'start_date', 'end_date', 'is_public', 'status',
            'plan_type', 'creator', 'group_name', 'duration_days', 'activities_count',
            'created_at'
        ]
    
    def to_representation(self, instance):
        data = super().to_representation(instance)
        data['status_display'] = self._get_status_display(instance)
        data['duration_display'] = self._get_duration_display(instance)
        return data
    
    def _get_duration_display(self, instance):
        days = instance.duration_days
        if days == 0:
            return "Chưa xác định"
        elif days == 1:
            return "1 ngày"
        else:
            return f"{days} ngày"
    
    def _get_status_display(self, instance):
        status_map = {
            'upcoming': '⏳ Sắp bắt đầu',
            'ongoing': '🏃 Đang diễn ra',
            'completed': '✅ Đã hoàn thành',
            'cancelled': '❌ Đã hủy',
        }
        return status_map.get(instance.status, instance.status)
    
class ChatMessageSerializer(serializers.ModelSerializer):
    sender = UserSummarySerializer(read_only=True)
    reply_to = serializers.SerializerMethodField()
    
    # Use model properties directly where available
    attachment_url = serializers.CharField(read_only=True)
    attachment_size_display = serializers.CharField(read_only=True)
    location_url = serializers.CharField(read_only=True)
    
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
        if obj.reply_to:
            return {
                'id': obj.reply_to.id,
                'content': obj.reply_to.content[:100] + ('...' if len(obj.reply_to.content) > 100 else ''),
                'sender': obj.reply_to.sender.username if obj.reply_to.sender else 'System',
                'message_type': obj.reply_to.message_type
            }
        return None
    
    def get_can_edit(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            # Only sender can edit their own text messages
            return (obj.sender == request.user and 
                    obj.message_type == 'text' and 
                    not obj.is_deleted)
        return False
    
    def get_can_delete(self, obj):
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
        if obj.attachment and obj.message_type == 'image':
            try:
                return obj.attachment.build_url(
                    width=150, height=150, crop='fill', quality='auto:good'
                )
            except:
                return obj.attachment_url
        return None
    
    def validate(self, attrs):
        if attrs.get('message_type') == 'location':
            if not (attrs.get('latitude') and attrs.get('longitude')):
                raise serializers.ValidationError(
                    "Location messages must have coordinates"
                )
        return attrs
    
    def create(self, validated_data):
        request = self.context.get('request')
        validated_data['sender'] = request.user
        return super().create(validated_data)


class FriendshipSerializer(serializers.ModelSerializer):
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
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            current_user = request.user
            
            # Check if this is for a friend request list (pending status)
            list_requests = self.context.get('list_friend_requests', False)
            
            if list_requests and instance.status == 'pending':
                # For friend request lists, 'user' should be the receiver (non-initiator)
                receiver = instance.get_other_user(instance.initiator)
                if receiver:
                    return UserSummarySerializer(receiver, context=self.context).data
            
            # For established friendships or other cases, return current user as 'user'
            if current_user in [instance.user_a, instance.user_b]:
                return UserSummarySerializer(current_user, context=self.context).data
        
        # Fallback to user_a (canonical first user)
        return UserSummarySerializer(instance.user_a, context=self.context).data
    
    def get_friend(self, instance):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            current_user = request.user
            
            # Check if this is for a friend request list (pending status)
            list_requests = self.context.get('list_friend_requests', False)
            
            if list_requests and instance.status == 'pending':
                # For friend request lists, 'friend' should be the initiator
                return UserSummarySerializer(instance.initiator, context=self.context).data
            
            # For established friendships, return the other user as 'friend'
            other_user = instance.get_other_user(current_user)
            if other_user:
                return UserSummarySerializer(other_user, context=self.context).data
        
        # Fallback to user_b (canonical second user)
        return UserSummarySerializer(instance.user_b, context=self.context).data


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
        
        existing = Friendship.get_friendship(user, friend_user)
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
        # Use UserService to handle friend request creation
        from .services import UserService
        success, message = UserService.send_friend_request(request.user, self.validated_friend)
        if not success:
            raise serializers.ValidationError(message)
        
        # Return the created friendship
        friendship = Friendship.get_friendship(request.user, self.validated_friend)
        return friendship


class FriendsListSerializer(serializers.ModelSerializer):

    friendship_since = serializers.SerializerMethodField()
    mutual_friends_count = serializers.SerializerMethodField()
    
    # Use model properties directly
    avatar_url = serializers.CharField(read_only=True)
    online_status = serializers.CharField(read_only=True)
    
    class Meta:
        model = User
        fields = [
            'id', 'username', 'first_name', 'last_name', 
            'avatar_url', 'is_online', 'online_status', 'last_seen', 
            'friendship_since', 'mutual_friends_count'
        ]
    
    def to_representation(self, instance):
        data = super().to_representation(instance)
        data['full_name'] = instance.get_full_name() or instance.username
        data['initials'] = self._get_initials(instance)
        return data
    
    def _get_initials(self, instance):
        if instance.first_name and instance.last_name:
            return f"{instance.first_name[0]}{instance.last_name[0]}".upper()
        elif instance.first_name:
            return instance.first_name[0].upper()
        return instance.username[0].upper() if instance.username else "U"
    
    def get_friendship_since(self, obj):
        friendships_map = self.context.get('friendships_map', {})
        friendship = friendships_map.get(obj.id)
        return friendship.created_at if friendship else None
    
    def get_mutual_friends_count(self, obj):
        # This can be pre-calculated and passed in context for better performance
        mutual_count = self.context.get('mutual_friends_count', {})
        return mutual_count.get(obj.id, 0)


class MessageReadStatusSerializer(serializers.ModelSerializer):
    user = UserSummarySerializer(read_only=True)
    
    class Meta:
        model = MessageReadStatus
        fields = ['id', 'message', 'user', 'read_at']
        read_only_fields = ['id', 'user', 'read_at']


class ConversationSerializer(serializers.ModelSerializer):
    participants = UserSummarySerializer(many=True, read_only=True)
    group = GroupSummarySerializer(read_only=True)
    
    avatar_url = serializers.CharField(read_only=True)
    unread_count = serializers.SerializerMethodField()
    last_message = serializers.SerializerMethodField()
    
    class Meta:
        model = Conversation
        fields = [
            'id', 'conversation_type', 'name', 'avatar', 'avatar_url',
            'group', 'participants', 'last_message_at', 'is_active',
            'unread_count', 'last_message', 'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'created_at', 'updated_at', 'last_message_at']
    
    def to_representation(self, instance):
        data = super().to_representation(instance)
        
        # Get current user from request context
        request = self.context.get('request')
        current_user = request.user if request and request.user.is_authenticated else None
        
        # Use model's context-aware methods
        data['avatar_url'] = instance.get_avatar_url(current_user)
        
        # Add additional context-dependent info
        if instance.conversation_type == 'direct' and current_user:
            other_user = instance.get_other_participant(current_user)
            if other_user:
                data['other_participant'] = {
                    'id': other_user.id,
                    'username': other_user.username,
                    'full_name': other_user.get_full_name(),
                    'is_online': other_user.is_online,
                    'last_seen': other_user.last_seen
                }
        
        return data
    
    def get_unread_count(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            return obj.get_unread_count_for_user(request.user)
        return 0
    
    def get_last_message(self, obj):
        last_message = getattr(obj, 'prefetched_last_message', None)
        if not last_message:
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


class ConversationSummarySerializer(serializers.ModelSerializer):
    avatar_url = serializers.CharField(read_only=True)
    unread_count = serializers.SerializerMethodField()
    
    last_message_preview = serializers.SerializerMethodField()
    
    class Meta:
        model = Conversation
        fields = [
            'id', 'conversation_type', 'avatar_url',
            'last_message_at', 'unread_count', 'last_message_preview', 'is_active'
        ]
    
    def to_representation(self, instance):
        data = super().to_representation(instance)
        
        request = self.context.get('request')
        current_user = request.user if request and request.user.is_authenticated else None
        
        data['avatar_url'] = instance.get_avatar_url(current_user)
        
        if instance.conversation_type == 'group' and instance.group:
            data['group_id'] = instance.group.id
            data['member_count'] = instance.group.member_count
        elif instance.conversation_type == 'direct' and current_user:
            other_user = instance.get_other_participant(current_user)
            if other_user:
                data['other_user_id'] = other_user.id
                data['other_user_online'] = other_user.is_online
        
        return data
    
    def get_unread_count(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            return obj.get_unread_count_for_user(request.user)
        return 0
    
    def get_last_message_preview(self, obj):
        if hasattr(obj, 'last_message_content') and obj.last_message_content:
            sender_name = "System"
            if hasattr(obj, 'last_message_sender_id') and obj.last_message_sender_id:
                # Try to get sender info from participants
                participants = obj.participants.all()
                for participant in participants:
                    if participant.id == obj.last_message_sender_id:
                        sender_name = participant.username
                        break
            
            return {
                'content': obj.last_message_content[:50] + ('...' if len(obj.last_message_content) > 50 else ''),
                'sender': sender_name,
                'created_at': getattr(obj, 'last_message_time', obj.last_message_at)
            }
        
        last_message = obj.messages.filter(is_deleted=False).order_by('-created_at').first()
        if last_message:
            return {
                'content': last_message.content[:50] + ('...' if len(last_message.content) > 50 else ''),
                'sender': last_message.sender.username if last_message.sender else 'System',
                'created_at': last_message.created_at
            }
        
        return None






