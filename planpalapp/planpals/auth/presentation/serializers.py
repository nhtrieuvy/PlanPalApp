from rest_framework import serializers
from django.contrib.auth import get_user_model
from planpals.auth.infrastructure.models import User, Friendship, FriendshipRejection
from django.core.files.uploadedfile import UploadedFile


User = get_user_model()


class UserSerializer(serializers.ModelSerializer):    
    online_status = serializers.CharField(read_only=True)
    avatar_url = serializers.CharField(read_only=True)
    has_avatar = serializers.BooleanField(read_only=True)
    is_recently_online = serializers.BooleanField(read_only=True)
    
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
            'date_joined', 'is_active', 'is_staff'
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
    id = serializers.CharField(read_only=True)
    
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


class FCMTokenSerializer(serializers.Serializer):
    fcm_token = serializers.CharField(max_length=255, allow_blank=False)
    platform = serializers.ChoiceField(
        choices=[('android', 'android'), ('ios', 'ios'), ('web', 'web')],
        required=False,
        default='android',
    )

    def validate_fcm_token(self, value):
        if len(value) < 10:
            raise serializers.ValidationError("FCM token seems too short")
        return value


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
            
            list_requests = self.context.get('list_friend_requests', False)
            
            if list_requests and instance.status == 'pending':
                receiver = instance.get_other_user(instance.initiator)
                if receiver:
                    return UserSummarySerializer(receiver, context=self.context).data
            
            if current_user in [instance.user_a, instance.user_b]:
                return UserSummarySerializer(current_user, context=self.context).data
        
        return UserSummarySerializer(instance.user_a, context=self.context).data
    
    def get_friend(self, instance):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            current_user = request.user
            
            list_requests = self.context.get('list_friend_requests', False)
            
            if list_requests and instance.status == 'pending':
                return UserSummarySerializer(instance.initiator, context=self.context).data
            
            other_user = instance.get_other_user(current_user)
            if other_user:
                return UserSummarySerializer(other_user, context=self.context).data
        
        return UserSummarySerializer(instance.user_b, context=self.context).data


class FriendRequestSerializer(serializers.Serializer):
    friend_id = serializers.UUIDField()
    message = serializers.CharField(max_length=200, required=False, allow_blank=True)
    
    def validate_friend_id(self, value):
        request = self.context['request']
        user = request.user
        
        try:
            friend_user = User.objects.get(id=value)
        except User.DoesNotExist:
            raise serializers.ValidationError("User not found")
        
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
        from planpals.auth.application.services import UserService
        success, message = UserService.send_friend_request(request.user, self.validated_friend)
        if not success:
            raise serializers.ValidationError(message)
        
        friendship = Friendship.get_friendship(request.user, self.validated_friend)
        return friendship


class FriendsListSerializer(serializers.ModelSerializer):

    friendship_since = serializers.SerializerMethodField()
    mutual_friends_count = serializers.SerializerMethodField()
    
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
        mutual_count = self.context.get('mutual_friends_count', {})
        return mutual_count.get(obj.id, 0)
