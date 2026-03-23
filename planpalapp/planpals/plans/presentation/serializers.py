from rest_framework import serializers
from django.contrib.auth import get_user_model

from planpals.plans.infrastructure.models import Plan, PlanActivity
from planpals.plans.domain.entities import (
    validate_activity_times, validate_coordinates, validate_estimated_cost,
    validate_plan_dates,
)
from planpals.models import Group, GroupMembership
from planpals.auth.presentation.serializers import UserSummarySerializer
from planpals.groups.presentation.serializers import GroupSummarySerializer

User = get_user_model()


class PlanActivitySummarySerializer(serializers.ModelSerializer):
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
        
        if not start_time:
            raise serializers.ValidationError({'start_time': 'Start time is required'})
        if not end_time:
            raise serializers.ValidationError({'end_time': 'End time is required'})
        
        # Delegate to domain validation — single source of truth
        time_error = validate_activity_times(start_time, end_time)
        if time_error:
            raise serializers.ValidationError({'end_time': time_error})
        
        coord_error = validate_coordinates(
            attrs.get('latitude'), attrs.get('longitude')
        )
        if coord_error:
            raise serializers.ValidationError(coord_error)
        
        cost_error = validate_estimated_cost(attrs.get('estimated_cost'))
        if cost_error:
            raise serializers.ValidationError({'estimated_cost': cost_error})
        
        return attrs


class PlanActivityCreateSerializer(serializers.ModelSerializer):
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


class PlanDetailSerializer(serializers.ModelSerializer):
    creator = UserSummarySerializer(read_only=True)
    group = GroupSummarySerializer(read_only=True)
    activities = PlanActivitySerializer(many=True, read_only=True)
    
    group_id = serializers.UUIDField(write_only=True, required=False, allow_null=True)
    group_name = serializers.CharField(source='group.name', read_only=True)
    
    duration_days = serializers.IntegerField(read_only=True)
    activities_count = serializers.IntegerField(read_only=True)
    total_estimated_cost = serializers.DecimalField(
        max_digits=12, 
        decimal_places=2, 
        read_only=True
    )

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
    
    def _user_is_group_member(self, group, user):
        """Check membership from prefetched data when available."""
        if group is None:
            return False
        members = getattr(group, '_prefetched_objects_cache', {}).get('members')
        if members is not None:
            return any(m.id == user.id for m in members)
        # Fallback (no prefetch — e.g. detail retrieved via get_object)
        return group.is_member(user)

    def _user_is_group_admin(self, group, user):
        """Check admin via prefetched memberships when available."""
        if group is None:
            return False
        memberships = getattr(group, '_prefetched_objects_cache', {}).get('memberships')
        if memberships is not None:
            return any(m.user_id == user.id and m.role == 'admin' for m in memberships)
        return group.is_admin(user)

    def get_can_view(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            user = request.user
            
            if obj.creator_id == user.id:
                return True
            
            if obj.is_public:
                return True
            
            if obj.is_group_plan() and obj.group:
                return self._user_is_group_member(obj.group, user)
            
            return False
        return obj.is_public
    
    
    def get_can_edit(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            user = request.user
            
            if obj.creator_id == user.id:
                return True
            
            if obj.is_group_plan() and obj.group:
                return self._user_is_group_admin(obj.group, user)
            
            return False
        return False
    
    def get_collaborators(self, obj):
        collaborators = obj.collaborators
        return UserSummarySerializer(collaborators, many=True, context=self.context).data
    
    def validate(self, attrs):
        if attrs.get('start_date') and attrs.get('end_date'):
            date_error = validate_plan_dates(attrs['start_date'], attrs['end_date'])
            if date_error:
                raise serializers.ValidationError(date_error)
        
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
            date_error = validate_plan_dates(attrs['start_date'], attrs['end_date'])
            if date_error:
                raise serializers.ValidationError(date_error)
        
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
