"""
Serializers for PlanPal app

Handle data serialization/deserialization for API endpoints.
Includes validation, nested relationships, and computed fields.
"""

from rest_framework import serializers
from django.contrib.auth import get_user_model
from django.db import models
from .models import (
    Plan, Group, GroupMembership, ChatMessage, 
    Friendship, PlanActivity, MessageReadStatus
)

User = get_user_model()


class UserSerializer(serializers.ModelSerializer):
    """Serializer cho User model"""
    full_name = serializers.SerializerMethodField()
    is_recently_online = serializers.SerializerMethodField()
    
    class Meta:
        model = User
        fields = [
            'id', 'username', 'email', 'first_name', 'last_name', 'full_name',
            'phone_number', 'avatar', 'date_of_birth', 'bio', 
            'is_online', 'last_seen', 'is_recently_online',
            'date_joined', 'is_active'
        ]
        read_only_fields = ['id', 'date_joined', 'last_seen', 'is_online']
    
    def get_full_name(self, obj):
        return obj.get_full_name()
    
    def get_is_recently_online(self, obj):
        return obj.is_recently_online


class UserCreateSerializer(serializers.ModelSerializer):
    """Serializer cho user registration"""
    password = serializers.CharField(write_only=True, min_length=8)
    password_confirm = serializers.CharField(write_only=True)
    
    class Meta:
        model = User
        fields = [
            'username', 'email', 'password', 'password_confirm',
            'first_name', 'last_name', 'phone_number'
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
        if value and value.size > 5 * 1024 * 1024:  # 5MB limit
            raise serializers.ValidationError("Avatar không được vượt quá 5MB")
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
    """Serializer cho Group model"""
    admin = UserSerializer(read_only=True)
    memberships = GroupMembershipSerializer(many=True, read_only=True)
    
    # Computed fields
    member_count = serializers.SerializerMethodField()
    is_member = serializers.SerializerMethodField()
    user_role = serializers.SerializerMethodField()
    can_edit = serializers.SerializerMethodField()
    can_delete = serializers.SerializerMethodField()
    
    class Meta:
        model = Group
        fields = [
            'id', 'name', 'description', 'cover_image', 'admin', 
            'memberships', 'member_count', 'is_active',
            'is_member', 'user_role', 'can_edit', 'can_delete',
            'created_at', 'updated_at'
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
    """Serializer cho PlanActivity"""
    
    class Meta:
        model = PlanActivity
        fields = [
            'id', 'plan', 'title', 'description', 'activity_type',
            'start_time', 'end_time', 'location_name', 'location_address',
            'latitude', 'longitude', 'google_place_id', 'estimated_cost',
            'notes', 'order', 'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'created_at', 'updated_at']
    
    def validate(self, attrs):
        if attrs.get('start_time') and attrs.get('end_time'):
            if attrs['end_time'] <= attrs['start_time']:
                raise serializers.ValidationError(
                    "Thời gian kết thúc phải sau thời gian bắt đầu"
                )
        return attrs


class PlanSerializer(serializers.ModelSerializer):
    """Serializer cho Plan model"""
    creator = UserSerializer(read_only=True)
    group = GroupSerializer(read_only=True)
    activities = PlanActivitySerializer(many=True, read_only=True)
    
    # Write fields
    group_id = serializers.UUIDField(write_only=True, required=False, allow_null=True)
    
    # Computed fields
    duration_days = serializers.SerializerMethodField()
    activities_count = serializers.SerializerMethodField()
    total_estimated_cost = serializers.SerializerMethodField()
    can_view = serializers.SerializerMethodField()
    can_edit = serializers.SerializerMethodField()
    collaborators = serializers.SerializerMethodField()
    
    class Meta:
        model = Plan
        fields = [
            'id', 'title', 'description', 'start_date', 'end_date', 'budget',
            'is_public', 'status', 'plan_type', 'creator', 'group', 'group_id',
            'activities', 'duration_days', 'activities_count', 'total_estimated_cost',
            'can_view', 'can_edit', 'collaborators',
            'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'creator', 'plan_type', 'created_at', 'updated_at']
    
    def get_duration_days(self, obj):
        return obj.duration_days
    
    def get_activities_count(self, obj):
        return obj.activities_count
    
    def get_total_estimated_cost(self, obj):
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
        collaborators = obj.get_collaborators()
        return UserSerializer(collaborators, many=True).data
    
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
    """Serializer cho ChatMessage"""
    sender = UserSerializer(read_only=True)
    reply_to = serializers.SerializerMethodField()
    
    # Computed fields
    can_edit = serializers.SerializerMethodField()
    can_delete = serializers.SerializerMethodField()
    attachment_size_display = serializers.SerializerMethodField()
    location_url = serializers.SerializerMethodField()
    
    class Meta:
        model = ChatMessage
        fields = [
            'id', 'group', 'sender', 'message_type', 'content',
            'attachment', 'attachment_name', 'attachment_size', 'attachment_size_display',
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
            from django.utils import timezone
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
    """Serializer cho Friendship"""
    sender = UserSerializer(read_only=True)
    receiver = UserSerializer(read_only=True)
    
    # Write fields
    receiver_id = serializers.UUIDField(write_only=True)
    
    class Meta:
        model = Friendship
        fields = [
            'id', 'sender', 'receiver', 'receiver_id', 'status',
            'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'sender', 'status', 'created_at', 'updated_at']
    
    def validate_receiver_id(self, value):
        try:
            receiver = User.objects.get(id=value)
            request = self.context.get('request')
            if request and request.user == receiver:
                raise serializers.ValidationError(
                    "Không thể gửi lời mời kết bạn cho chính mình"
                )
            
            # Check if friendship already exists
            if Friendship.objects.filter(
                models.Q(sender=request.user, receiver=receiver) |
                models.Q(sender=receiver, receiver=request.user)
            ).exists():
                raise serializers.ValidationError(
                    "Lời mời kết bạn đã tồn tại"
                )
            
            return value
        except User.DoesNotExist:
            raise serializers.ValidationError("User không tồn tại")
    
    def create(self, validated_data):
        request = self.context.get('request')
        validated_data['sender'] = request.user
        receiver_id = validated_data.pop('receiver_id')
        validated_data['receiver'] = User.objects.get(id=receiver_id)
        return super().create(validated_data)


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
