from rest_framework import serializers
from django.conf import settings
from django.contrib.auth import get_user_model
from django.utils import timezone

from planpals.groups.infrastructure.models import (
    Group,
    GroupInvite,
    GroupJoinRequest,
    GroupMembership,
)
from planpals.auth.presentation.serializers import UserSummarySerializer
from planpals.models import User, Friendship

User = get_user_model()


class GroupMembershipSerializer(serializers.ModelSerializer):
    user = UserSummarySerializer(read_only=True)
    role_display = serializers.CharField(source='get_role_display', read_only=True)
    
    class Meta:
        model = GroupMembership
        fields = [
            'id', 'user', 'role', 'role_display', 'created_at'
        ]
        read_only_fields = ['id', 'created_at']


class GroupDetailSerializer(serializers.ModelSerializer):
    admin = UserSummarySerializer(read_only=True)
    memberships = GroupMembershipSerializer(many=True, read_only=True)

    avatar_url = serializers.CharField(read_only=True)
    has_avatar = serializers.BooleanField(read_only=True)
    cover_image_url = serializers.CharField(read_only=True)
    has_cover_image = serializers.BooleanField(read_only=True)
    
    member_count = serializers.IntegerField(read_only=True)
    plans_count = serializers.IntegerField(read_only=True)
    active_plans_count = serializers.IntegerField(read_only=True)
    
    is_member = serializers.SerializerMethodField()
    user_role = serializers.SerializerMethodField()
    can_edit = serializers.SerializerMethodField()
    can_delete = serializers.SerializerMethodField()
    can_create_plan = serializers.SerializerMethodField()

    class Meta:
        model = Group
        fields = [
            'id', 'name', 'description', 'visibility',
            'avatar', 'avatar_url', 'has_avatar',
            'cover_image', 'cover_image_url', 'has_cover_image',
            'admin', 'memberships', 'member_count', 'plans_count', 'active_plans_count',
            'is_active', 'is_member', 'user_role', 'can_edit',
            'can_delete', 'can_create_plan',
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

    def get_can_create_plan(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            return obj.can_create_plans(request.user)
        return False
    
    def create(self, validated_data):
        request = self.context.get('request')
        validated_data['admin'] = request.user
        return super().create(validated_data)


class GroupCreateSerializer(serializers.ModelSerializer):
    member_count = serializers.IntegerField(read_only=True)

    avatar_url = serializers.CharField(read_only=True)
    has_avatar = serializers.BooleanField(read_only=True)
    cover_image_url = serializers.CharField(read_only=True)
    has_cover_image = serializers.BooleanField(read_only=True)
    
    admin = UserSummarySerializer(read_only=True)
    
    initial_members = serializers.ListField(
        child=serializers.UUIDField(),
        write_only=True,
        required=False,
        default=list,
        help_text="Deprecated. Invite codes should be used for scalable onboarding."
    )
    
    class Meta:
        model = Group
        fields = [
            'id', 'name', 'description', 'visibility',
            'avatar', 'avatar_url', 'has_avatar',
            'cover_image', 'cover_image_url', 'has_cover_image',
            'initial_members',
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

    def validate_visibility(self, value):
        normalized = (value or Group.PRIVATE).strip().lower()
        if normalized not in {Group.PUBLIC, Group.PRIVATE}:
            raise serializers.ValidationError("Visibility must be public or private")
        return normalized
    
    def validate_initial_members(self, value):
        value = value or []
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
        initial_members = validated_data.pop('initial_members', [])
        validated_data['admin'] = request.user
        
        group = super().create(validated_data)
        
        from planpals.groups.application.services import GroupService

        
        for user_id in initial_members:
            user = User.objects.get(id=user_id)
            GroupService.add_member(group, user, role='member')
        
        return group


class GroupSummarySerializer(serializers.ModelSerializer):
    member_count = serializers.SerializerMethodField()
    avatar_url = serializers.CharField(read_only=True)
    has_avatar = serializers.BooleanField(read_only=True)
    
    class Meta:
        model = Group
        fields = [
            'id', 'name', 'description', 'visibility',
            'member_count', 'avatar_url', 'has_avatar', 'created_at'
        ]
    
    def to_representation(self, instance):
        data = super().to_representation(instance)
        data['initials'] = self._get_group_initials(instance)
        return data

    def get_member_count(self, instance):
        memberships = getattr(instance, '_prefetched_objects_cache', {}).get('memberships')
        if memberships is not None:
            return len(memberships)
        return instance.member_count
    
    def _get_group_initials(self, instance):
        if not instance.name:
            return 'G'
        
        parts = [p for p in instance.name.split() if p]
        if len(parts) >= 2:
            return (parts[0][0] + parts[1][0]).upper()
        
        return instance.name[:2].upper()


class GroupInviteCreateSerializer(serializers.Serializer):
    expires_at = serializers.DateTimeField(required=False, allow_null=True)
    max_uses = serializers.IntegerField(required=False, allow_null=True, min_value=1)


class GroupInviteSerializer(serializers.ModelSerializer):
    created_by = UserSummarySerializer(read_only=True)
    group_visibility = serializers.CharField(source='group.visibility', read_only=True)
    invite_code = serializers.CharField(source='token', read_only=True)
    remaining_uses = serializers.SerializerMethodField()
    is_expired = serializers.SerializerMethodField()
    deep_link = serializers.SerializerMethodField()
    web_link = serializers.SerializerMethodField()

    class Meta:
        model = GroupInvite
        fields = [
            'id',
            'group',
            'group_visibility',
            'token',
            'invite_code',
            'created_by',
            'expires_at',
            'max_uses',
            'current_uses',
            'remaining_uses',
            'is_active',
            'is_expired',
            'deep_link',
            'web_link',
            'created_at',
            'updated_at',
        ]
        read_only_fields = fields

    def get_remaining_uses(self, obj):
        if obj.max_uses is None:
            return None
        return max(obj.max_uses - obj.current_uses, 0)

    def get_is_expired(self, obj):
        return bool(obj.expires_at and obj.expires_at <= timezone.now())

    def get_deep_link(self, obj):
        scheme = getattr(settings, 'PLANPAL_DEEP_LINK_SCHEME', 'planpal')
        return f'{scheme}://groups/join/{obj.token}'

    def get_web_link(self, obj):
        base_url = getattr(settings, 'PLANPAL_WEB_BASE_URL', 'https://planpal.app').rstrip('/')
        return f'{base_url}/groups/join/{obj.token}'


class GroupInviteCodeJoinSerializer(serializers.Serializer):
    code = serializers.RegexField(
        regex=r'^\d{6}$',
        max_length=6,
        min_length=6,
        trim_whitespace=True,
        error_messages={
            'invalid': 'Invite code must contain exactly 6 digits.',
            'blank': 'Invite code is required.',
        },
    )


class GroupJoinRequestSerializer(serializers.ModelSerializer):
    user = UserSummarySerializer(read_only=True)
    reviewed_by = UserSummarySerializer(read_only=True)
    invite_token = serializers.CharField(source='invite.token', read_only=True)

    class Meta:
        model = GroupJoinRequest
        fields = [
            'id',
            'group',
            'invite',
            'invite_token',
            'user',
            'status',
            'reviewed_by',
            'reviewed_at',
            'created_at',
            'updated_at',
        ]
        read_only_fields = fields
