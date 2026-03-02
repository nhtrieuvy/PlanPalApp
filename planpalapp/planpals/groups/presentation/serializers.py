from rest_framework import serializers
from django.contrib.auth import get_user_model

from planpals.groups.infrastructure.models import Group, GroupMembership
from planpals.auth.presentation.serializers import UserSummarySerializer
from planpals.models import User, Friendship

User = get_user_model()


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
    
    member_count = serializers.IntegerField(read_only=True)
    plans_count = serializers.IntegerField(read_only=True)
    active_plans_count = serializers.IntegerField(read_only=True)
    
    avatar_url = serializers.CharField(read_only=True)
    has_avatar = serializers.BooleanField(read_only=True)
    cover_image_url = serializers.CharField(read_only=True)
    has_cover_image = serializers.BooleanField(read_only=True)
    
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
    
    def _get_user_membership(self, obj, user):
        """Look up membership from prefetched data instead of hitting the DB."""
        memberships = getattr(obj, '_prefetched_objects_cache', {}).get('memberships')
        if memberships is not None:
            # Use prefetched queryset — no DB hit
            for m in memberships:
                if m.user_id == user.id:
                    return m
            return None
        # Fallback to DB query when not prefetched
        return obj.get_user_membership(user)

    def get_is_member(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            return self._get_user_membership(obj, request.user) is not None
        return False
    
    def get_user_role(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            membership = self._get_user_membership(obj, request.user)
            return membership.role if membership else None
        return None
    
    def get_can_edit(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            membership = self._get_user_membership(obj, request.user)
            return membership is not None and membership.role == GroupMembership.ADMIN
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
    avatar_url = serializers.CharField(read_only=True)
    has_avatar = serializers.BooleanField(read_only=True)
    cover_image_url = serializers.CharField(read_only=True)
    has_cover_image = serializers.BooleanField(read_only=True)
    member_count = serializers.IntegerField(read_only=True)
    
    admin = UserSummarySerializer(read_only=True)
    
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
        
        from planpals.groups.application.services import GroupService

        
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
