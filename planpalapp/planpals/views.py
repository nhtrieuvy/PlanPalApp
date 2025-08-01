# ============================================================================
# PLANPAL API VIEWS - OAuth2 Authentication
# ============================================================================

from django.shortcuts import get_object_or_404
from rest_framework import viewsets, status, generics, mixins
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework.views import APIView
from django.contrib.auth import authenticate, get_user_model
from django.utils import timezone
from django.db import models
from django.core.exceptions import ValidationError
from datetime import datetime

from .models import User, Group, Plan, Friendship, ChatMessage, PlanActivity
from .serializers import (
    UserSerializer, UserCreateSerializer, GroupSerializer, 
    PlanSerializer, FriendshipSerializer, FriendRequestSerializer, ChatMessageSerializer,
    PlanActivitySerializer
)
from .permissions import (
    IsAuthenticatedAndActive, PlanPermission, GroupPermission,
    ChatMessagePermission, FriendshipPermission, UserProfilePermission,
    IsGroupMember, IsGroupAdmin, PlanActivityPermission
)
from .services import notification_service
from .services.goong_service import goong_service

User = get_user_model()

# ============================================================================
# OAuth2 Authentication Views (Simplified for now)
# ============================================================================

class OAuth2LoginView(APIView):
    """OAuth2 Login endpoint với JSON response"""
    permission_classes = [AllowAny]
    
    def post(self, request, *args, **kwargs):
       
        username = request.data.get('username')
        password = request.data.get('password')
        
        
        if not username or not password:
            return Response(
                {'error': 'Username and password required'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        user = authenticate(username=username, password=password)
        if not user:
            return Response(
                {'error': 'Invalid credentials'}, 
                status=status.HTTP_401_UNAUTHORIZED
            )
        
        # Check if user is active
        if not user.is_active:
            return Response(
                {'error': 'Account is deactivated'}, 
                status=status.HTTP_403_FORBIDDEN
            )
        
        # Update user online status using model method
        user.set_online_status(True)
        
        # Return comprehensive user data using serializer
        user_serializer = UserSerializer(user)
        return Response({
            'message': 'Login successful',
            'user': user_serializer.data,
            'note': 'OAuth2 token implementation pending'
        }, status=status.HTTP_200_OK)

class OAuth2LogoutView(APIView):
    """OAuth2 Logout endpoint"""
    permission_classes = [IsAuthenticated]
    
    def post(self, request):
        try:
            # Update user offline status using model method
            request.user.set_online_status(False)
            
            # Note: OAuth2 token revocation will be implemented
            # when oauth2_provider is properly configured
            
            return Response({
                'message': 'Logged out successfully',
                'timestamp': timezone.now().isoformat(),
                'note': 'OAuth2 token revocation pending'
            }, status=status.HTTP_200_OK)
            
        except Exception as e:
            return Response(
                {'error': f'Logout failed: {str(e)}'}, 
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )

# ============================================================================
# Core API ViewSets
# ============================================================================

class UserViewSet(viewsets.GenericViewSet,
                  mixins.CreateModelMixin,
                  mixins.RetrieveModelMixin,
                  mixins.UpdateModelMixin):
    """SECURE User operations - Fixed dangerous ModelViewSet"""
    serializer_class = UserSerializer
    
    def get_permissions(self):
        if self.action == 'create':
            permission_classes = [AllowAny]
        elif self.action in ['update', 'destroy']:
            permission_classes = [IsAuthenticated, UserProfilePermission]
        else:
            permission_classes = [IsAuthenticatedAndActive]
        return [permission() for permission in permission_classes]
    
    def get_queryset(self):
        """SECURE - Only current user for profile operations"""
        return User.objects.filter(id=self.request.user.id)
    
    def get_serializer_class(self):
        if self.action == 'create':
            return UserCreateSerializer
        return UserSerializer
    
    def list(self, request):
        """Custom list - only return current user profile"""
        user_serializer = self.get_serializer(request.user)
        return Response({
            'user': user_serializer.data,
            'message': 'Use specific endpoints for user search'
        })
    
    # ✅ SECURE USER SEARCH
    @action(detail=False, methods=['get'])
    def search(self, request):
        """Search users for friend requests (limited results)"""
        query = request.query_params.get('q')
        if not query:
            return Response(
                {'error': 'Search query (q) parameter required'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        # Limited search - only basic info, max 20 results
        users = User.objects.filter(
            models.Q(username__icontains=query) |
            models.Q(email__icontains=query) |
            models.Q(first_name__icontains=query) |
            models.Q(last_name__icontains=query)
        ).exclude(
            id=request.user.id  # Exclude self
        ).only(
            'id', 'username', 'first_name', 'last_name', 'avatar'
        )[:20]  # Limit to 20 results
        
        # Use basic serializer for search results
        users_data = []
        for user in users:
            users_data.append({
                'id': user.id,
                'username': user.username,
                'full_name': f"{user.first_name} {user.last_name}".strip(),
                'avatar': user.avatar.url if user.avatar else None
            })
        
        return Response({
            'users': users_data,
            'count': len(users_data),
            'query': query
        })
    
    #API trả về thông tin người dùng hiện tại
    @action(detail=False, methods=['get'])
    def profile(self, request):
        """Get current user profile"""
        serializer = self.get_serializer(request.user) 
        return Response(serializer.data)
    
    #API cập nhật thông tin người dùng hiện tại
    @action(detail=False, methods=['put', 'patch'])
    def update_profile(self, request):
        """Update current user profile"""
        serializer = self.get_serializer(
            request.user, 
            data=request.data, 
            partial=True
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)
    
    #API lấy danh sách kế hoạch của người dùng hiện tại
    @action(detail=False, methods=['get'])
    def my_plans(self, request):
        """Get all plans for current user using model method"""
        plans = request.user.get_all_plans()
        serializer = PlanSerializer(plans, many=True)
        return Response(serializer.data)
    
    #API lấy danh sách chat gần đây hình như trong 5ph
    @action(detail=False, methods=['get'])
    def recent_conversations(self, request):
        """Get recent conversations using model method"""
        conversations = request.user.get_recent_conversations()
        serializer = GroupSerializer(conversations, many=True)
        return Response(serializer.data)
    
    #API lấy tin nhắn chưa đọc
    @action(detail=False, methods=['get'])
    def unread_count(self, request):
        """Get unread messages count using model method"""
        count = request.user.get_unread_messages_count()
        return Response({'unread_count': count})

class GroupViewSet(viewsets.GenericViewSet,
                   mixins.CreateModelMixin,
                   mixins.RetrieveModelMixin,
                   mixins.UpdateModelMixin,
                   mixins.DestroyModelMixin):
    """SECURE Group operations - Fixed dangerous ModelViewSet"""
    serializer_class = GroupSerializer
    permission_classes = [IsAuthenticated, GroupPermission]
    
    def get_queryset(self):
        """SECURE - Only groups user is member of with correct field references"""
        return Group.objects.filter(
            members=self.request.user
        ).select_related('admin').prefetch_related(
            'members',
            'memberships__user'
        )
    
    def list(self, request):
        """Custom secure list implementation - user's groups only"""
        queryset = self.get_queryset().order_by('-created_at')
        serializer = self.get_serializer(queryset, many=True)
        
        return Response({
            'groups': serializer.data,
            'count': len(serializer.data),
            'timestamp': timezone.now().isoformat()
        })
    
    def perform_create(self, serializer):
        """Auto-add creator as admin and member"""
        group = serializer.save(admin=self.request.user)
        group.members.add(self.request.user)
        return group
    
    # ✅ SECURE JOIN GROUP
    @action(detail=False, methods=['post'])
    def join(self, request):
        """Join group by invite code or ID"""
        group_id = request.data.get('group_id')
        invite_code = request.data.get('invite_code')
        
        if not group_id and not invite_code:
            return Response(
                {'error': 'group_id or invite_code required'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        try:
            if invite_code:
                group = Group.objects.get(invite_code=invite_code)
            else:
                # Only allow joining public groups
                group = Group.objects.get(
                    id=group_id, 
                    is_public=True  # Assuming you have this field
                )
            
            if request.user in group.members.all():
                return Response({'message': 'Already a member'})
            
            group.members.add(request.user)
            
            return Response({
                'message': 'Joined group successfully',
                'group': self.get_serializer(group).data
            })
            
        except Group.DoesNotExist:
            return Response(
                {'error': 'Group not found or not accessible'}, 
                status=status.HTTP_404_NOT_FOUND
            )
    
    @action(detail=False, methods=['get'])
    def my_groups(self, request):
        """Get user's joined groups"""
        groups = self.get_queryset()
        serializer = self.get_serializer(groups, many=True)
        return Response({
            'groups': serializer.data,
            'count': len(serializer.data)
        })
    
    @action(detail=False, methods=['get'])
    def created_by_me(self, request):
        """Get groups created by user"""
        groups = self.get_queryset().filter(created_by=request.user)
        serializer = self.get_serializer(groups, many=True)
        return Response({
            'groups': serializer.data,
            'count': len(serializer.data)
        })
    
    @action(detail=False, methods=['get'])
    def search(self, request):
        """Search in user's groups"""
        query = request.query_params.get('q')
        if not query:
            return Response(
                {'error': 'q parameter required'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        groups = self.get_queryset().filter(
            models.Q(name__icontains=query) |
            models.Q(description__icontains=query)
        )
        
        serializer = self.get_serializer(groups, many=True)
        return Response({
            'groups': serializer.data,
            'query': query,
            'count': len(serializer.data)
        })
    
    #API gửi tin nhắn đến nhóm
    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, IsGroupMember])
    def send_message(self, request, pk=None):
        """Send message to group using model method"""
        group = self.get_object()
        content = request.data.get('content')
        message_type = request.data.get('message_type', 'text')
        
        try:
            message = group.send_message(
                sender=request.user,
                content=content,
                message_type=message_type
            )
            serializer = ChatMessageSerializer(message)
            return Response(serializer.data, status=status.HTTP_201_CREATED)
        except PermissionError as e:
            return Response(
                {'error': str(e)}, 
                status=status.HTTP_403_FORBIDDEN
            )
    
    #API lấy danh sách tin nhắn gần đây
    @action(detail=True, methods=['get'], permission_classes=[IsAuthenticated, IsGroupMember])
    def recent_messages(self, request, pk=None):
        """Get recent messages using model method"""
        group = self.get_object()
        limit = int(request.query_params.get('limit', 50))
        messages = group.get_recent_messages(limit=limit)
        serializer = ChatMessageSerializer(messages, many=True)
        return Response(serializer.data)
    
    #API lấy số lượng tin nhắn chưa đọc
    @action(detail=True, methods=['get'], permission_classes=[IsAuthenticated, IsGroupMember])
    def unread_count(self, request, pk=None):
        """Get unread messages count using model method"""
        group = self.get_object()
        count = group.get_unread_messages_count(request.user)
        return Response({'unread_count': count})
    
    #API lấy danh sách quản trị viên của nhóm
    @action(detail=True, methods=['get'], permission_classes=[IsAuthenticated, IsGroupMember])
    def admins(self, request, pk=None):
        """Get group admins using model method"""
        group = self.get_object()
        admins = group.get_admins()
        serializer = UserSerializer(admins, many=True)
        return Response(serializer.data)

class PlanViewSet(viewsets.ModelViewSet):
    """Plan CRUD operations - SECURITY FIXED"""
    serializer_class = PlanSerializer
    permission_classes = [IsAuthenticated, PlanPermission]
    
    def get_queryset(self):
        """SECURE - Only user's accessible plans with full optimizations"""
        return Plan.objects.filter(
            models.Q(group__members=self.request.user) |
            models.Q(created_by=self.request.user)
        ).select_related('created_by', 'group').prefetch_related(
            'group__members',
            'activities'
        ).distinct().order_by('-created_at')
    
    def perform_create(self, serializer):
        """Auto-set creator and handle notifications"""
        plan = serializer.save(created_by=self.request.user)
        
        # Optional: Send notification if service available
        try:
            if hasattr(notification_service, 'notify_plan_created'):
                notification_service.notify_plan_created(
                    plan_id=str(plan.id),
                    creator_name=self.request.user.username,
                    group_id=str(plan.group.id) if plan.group else None
                )
        except Exception:
            pass  # Don't fail plan creation if notification fails
        
        return plan
    
    def list(self, request):
        """Enhanced list with metadata"""
        queryset = self.get_queryset()
        serializer = self.get_serializer(queryset, many=True)
        
        return Response({
            'plans': serializer.data,
            'count': len(serializer.data),
            'user_id': request.user.id,
            'timestamp': timezone.now().isoformat()
        })
    
    #API lấy kế hoạch theo ngày
    @action(detail=True, methods=['get'])
    def activities_by_date(self, request, pk=None):
        """Get activities for specific date using model method"""
        plan = self.get_object()
        date_str = request.query_params.get('date')
        
        if not date_str:
            return Response(
                {'error': 'Date parameter required (YYYY-MM-DD format)'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        try:
            date = datetime.strptime(date_str, '%Y-%m-%d').date()
            activities = plan.get_activities_by_date(date)
            serializer = PlanActivitySerializer(activities, many=True)
            return Response(serializer.data)
        except ValueError:
            return Response(
                {'error': 'Invalid date format. Use YYYY-MM-DD'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
    
    #API lấy người tham gia kế hoạch
    @action(detail=True, methods=['get'])
    def collaborators(self, request, pk=None):
        """Get plan collaborators using model method"""
        plan = self.get_object()
        collaborators = plan.get_collaborators()
        serializer = UserSerializer(collaborators, many=True)
        return Response(serializer.data)
    
    #API thêm hoạt động vào kế hoạch - OPTIMIZED
    @action(detail=True, methods=['post'])
    def add_activity(self, request, pk=None):
        """Add activity to plan using serializer - THIN VIEW"""
        plan = self.get_object()
        
        # ✅ THIN VIEW - delegate to serializer
        serializer = PlanActivitySerializer(data=request.data)
        if serializer.is_valid():
            # Set plan from URL parameter
            serializer.validated_data['plan'] = plan
            activity = serializer.save()
            
            return Response(
                PlanActivitySerializer(activity).data, 
                status=status.HTTP_201_CREATED
            )
        
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
    
    #API lấy tóm tắt kế hoạch
    @action(detail=True, methods=['get'])
    def summary(self, request, pk=None):
        """Get plan summary using model properties"""
        plan = self.get_object()
        
        summary = {
            'duration_days': plan.duration_days,
            'activities_count': plan.activities_count,
            'total_estimated_cost': plan.total_estimated_cost,
            'collaborators_count': len(plan.get_collaborators()),
        }
        
        return Response(summary)


# 1. Send friend request - OPTIMIZED
class FriendRequestView(generics.CreateAPIView):
    serializer_class = FriendRequestSerializer
    permission_classes = [IsAuthenticated]
    
    def create(self, request):
        serializer = self.get_serializer(data=request.data)
        if serializer.is_valid():
            friend_id = serializer.validated_data['friend_id']
            
            try:
                friend = User.objects.get(id=friend_id)
            except User.DoesNotExist:
                return Response(
                    {'error': 'User not found'}, 
                    status=status.HTTP_404_NOT_FOUND
                )
            
            # ✅ OPTIMIZED - Use model method with get_or_create
            try:
                friendship, created = Friendship.create_friend_request(request.user, friend)
                
                if created:
                    return Response({
                        'message': 'Friend request sent successfully',
                        'friendship': FriendshipSerializer(friendship).data
                    }, status=status.HTTP_201_CREATED)
                else:
                    return Response({
                        'message': 'Friend request already exists or updated',
                        'friendship': FriendshipSerializer(friendship).data
                    })
                    
            except ValidationError as e:
                return Response({'error': str(e)}, status=status.HTTP_400_BAD_REQUEST)
                
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

# 2. List pending requests - OPTIMIZED  
class FriendRequestListView(generics.ListAPIView):
    serializer_class = FriendshipSerializer
    permission_classes = [IsAuthenticated]
    
    def get_queryset(self):
        # ✅ OPTIMIZED - Single query with select_related
        return Friendship.objects.filter(
            friend=self.request.user,
            status=Friendship.PENDING
        ).select_related('user', 'friend').order_by('-created_at')

# 3. Accept/Reject requests - OPTIMIZED
class FriendRequestActionView(APIView):
    permission_classes = [IsAuthenticated, FriendshipPermission]
    
    def post(self, request, request_id):
        action = request.data.get('action')
        
        if action not in ['accept', 'reject']:
            return Response(
                {'error': 'Invalid action. Use "accept" or "reject"'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
            
        # ✅ OPTIMIZED - Single query with select_related
        friendship = get_object_or_404(
            Friendship.objects.select_related('user', 'friend'),
            id=request_id,
            friend=request.user,
            status=Friendship.PENDING
        )
        
        # ✅ FriendshipPermission sẽ check quyền ở đây
        self.check_object_permissions(request, friendship)
        
        success = False
        if action == 'accept':
            success = friendship.accept()
        elif action == 'reject':
            success = friendship.reject()
            
        if success:
            return Response({
                'message': f'Request {action}ed successfully',
                'friendship': FriendshipSerializer(friendship).data
            })
        else:
            return Response(
                {'error': f'Could not {action} request'}, 
                status=status.HTTP_400_BAD_REQUEST
            )

# 4. List friends - OPTIMIZED with single query
class FriendsListView(generics.ListAPIView):
    serializer_class = UserSerializer
    permission_classes = [IsAuthenticated]
    
    def get_queryset(self):
        # ✅ OPTIMIZED - Use model method for single query
        return Friendship.get_friends_queryset(self.request.user)

class ChatMessageViewSet(viewsets.GenericViewSet,
                         mixins.CreateModelMixin,
                         mixins.RetrieveModelMixin,
                         mixins.UpdateModelMixin,
                         mixins.DestroyModelMixin):
    """Optimized Chat Message operations - NO dangerous list endpoint"""
    serializer_class = ChatMessageSerializer
    permission_classes = [IsAuthenticated, ChatMessagePermission]
    
    def get_queryset(self):
        # ✅ OPTIMIZED - Only messages from user's groups
        return ChatMessage.objects.filter(
            group__members=self.request.user
        ).select_related('sender', 'group')
    
    
    
    def create(self, request, *args, **kwargs):
        """Override create to add business logic"""
        # Validate group membership before sending message
        group_id = request.data.get('group')
        if group_id:
            try:
                group = Group.objects.get(id=group_id, members=request.user)
            except Group.DoesNotExist:
                return Response(
                    {'error': 'Cannot send message to this group'}, 
                    status=status.HTTP_403_FORBIDDEN
                )
        
        return super().create(request, *args, **kwargs)
    
    def perform_create(self, serializer):
        """Set sender automatically"""
        serializer.save(sender=self.request.user)
    
    def update(self, request, *args, **kwargs):
        """Override update to check message ownership and time limit"""
        message = self.get_object()
        
        # Only sender can edit message
        if message.sender != request.user:
            return Response(
                {'error': 'Can only edit your own messages'}, 
                status=status.HTTP_403_FORBIDDEN
            )
        
        # Check edit time limit (15 minutes)
        edit_deadline = message.created_at + timezone.timedelta(minutes=15)
        if timezone.now() > edit_deadline:
            return Response(
                {'error': 'Message edit time expired (15 minutes limit)'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        # Don't allow editing system messages
        if message.message_type == 'system':
            return Response(
                {'error': 'Cannot edit system messages'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        return super().update(request, *args, **kwargs)
    
    def destroy(self, request, *args, **kwargs):
        """Override destroy to check permissions"""
        message = self.get_object()
        
        # Sender or group admin can delete
        can_delete = (
            message.sender == request.user or 
            message.group.is_admin(request.user)
        )
        
        if not can_delete:
            return Response(
                {'error': 'Permission denied. Only sender or group admin can delete messages'}, 
                status=status.HTTP_403_FORBIDDEN
            )
        
        return super().destroy(request, *args, **kwargs)
    
    #API lấy tin nhắn theo nhóm với pagination
    @action(detail=False, methods=['get'])
    def by_group(self, request):
        """Get paginated messages for specific group"""
        group_id = request.query_params.get('group_id')
        
        if not group_id:
            return Response(
                {'error': 'group_id parameter required'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        # Validate user access to group
        try:
            group = Group.objects.get(id=group_id, members=request.user)
        except Group.DoesNotExist:
            return Response(
                {'error': 'Group not found or access denied'}, 
                status=status.HTTP_404_NOT_FOUND
            )
        
        # Pagination parameters
        limit = min(int(request.query_params.get('limit', 50)), 100)  # Max 100
        before_id = request.query_params.get('before_id')  # Cursor pagination
        
        # Build query with cursor pagination
        queryset = ChatMessage.objects.filter(
            group=group
        ).select_related('sender').order_by('-created_at')
        
        if before_id:
            try:
                before_message = ChatMessage.objects.get(id=before_id)
                queryset = queryset.filter(created_at__lt=before_message.created_at)
            except ChatMessage.DoesNotExist:
                return Response(
                    {'error': 'Invalid before_id'}, 
                    status=status.HTTP_400_BAD_REQUEST
                )
        
        # Get limit + 1 to check if more exist
        messages = list(queryset[:limit + 1])
        
        has_more = len(messages) > limit
        if has_more:
            messages = messages[:-1]  # Remove extra message
        
        serializer = self.get_serializer(messages, many=True)
        
        return Response({
            'messages': serializer.data,
            'has_more': has_more,
            'next_cursor': messages[-1].id if messages and has_more else None,
            'count': len(messages)
        })
    
    #API tìm kiếm tin nhắn
    @action(detail=False, methods=['get'])
    def search(self, request):
        """Search messages within user's groups"""
        query = request.query_params.get('q')
        group_id = request.query_params.get('group_id')
        
        if not query:
            return Response(
                {'error': 'Search query (q) parameter required'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        # Base queryset - only user's groups
        queryset = ChatMessage.objects.filter(
            group__members=request.user,
            content__icontains=query
        ).select_related('sender', 'group').order_by('-created_at')
        
        # Filter by specific group if provided
        if group_id:
            try:
                Group.objects.get(id=group_id, members=request.user)  # Validate access
                queryset = queryset.filter(group_id=group_id)
            except Group.DoesNotExist:
                return Response(
                    {'error': 'Group not found or access denied'}, 
                    status=status.HTTP_404_NOT_FOUND
                )
        
        # Limit search results for performance
        messages = queryset[:50]
        serializer = self.get_serializer(messages, many=True)
        
        return Response({
            'messages': serializer.data,
            'count': len(messages),
            'query': query
        })
    
    #API lấy tin nhắn gần đây từ tất cả nhóm
    @action(detail=False, methods=['get'])
    def recent(self, request):
        """Get recent messages across all user's groups"""
        limit = min(int(request.query_params.get('limit', 20)), 50)  # Max 50
        
        messages = ChatMessage.objects.filter(
            group__members=request.user
        ).select_related('sender', 'group').order_by('-created_at')[:limit]
        
        serializer = self.get_serializer(messages, many=True)
        
        return Response({
            'messages': serializer.data,
            'count': len(messages)
        })

class PlanActivityViewSet(viewsets.GenericViewSet,
                          mixins.CreateModelMixin,
                          mixins.RetrieveModelMixin,
                          mixins.UpdateModelMixin,
                          mixins.DestroyModelMixin):
    """Optimized Plan Activity operations - SECURE permissions"""
    serializer_class = PlanActivitySerializer
    permission_classes = [IsAuthenticated, PlanActivityPermission]
    
    def get_queryset(self):
        # ✅ SECURE - Only activities from user's plans
        return PlanActivity.objects.filter(
            plan__group__members=self.request.user
        ).select_related('plan', 'plan__group')
    
    
    def create(self, request, *args, **kwargs):
        """Override create to validate plan access"""
        plan_id = request.data.get('plan')
        
        if not plan_id:
            return Response(
                {'error': 'plan field is required'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        # Validate user can add activities to this plan
        try:
            plan = Plan.objects.filter(
                models.Q(id=plan_id) & (
                    models.Q(group__members=request.user) | 
                    models.Q(created_by=request.user)
                )
            ).first()
            
            if not plan:
                raise Plan.DoesNotExist()
                
        except Plan.DoesNotExist:
            return Response(
                {'error': 'Plan not found or access denied'}, 
                status=status.HTTP_403_FORBIDDEN
            )
        
        return super().create(request, *args, **kwargs)
    
    def update(self, request, *args, **kwargs):
        """Override update to check ownership"""
        activity = self.get_object()
        
        # Check if user can modify this activity
        if not (activity.plan.created_by == request.user or 
                activity.plan.group.is_admin(request.user)):
            return Response(
                {'error': 'Permission denied. Only plan creator or group admin can modify activities'}, 
                status=status.HTTP_403_FORBIDDEN
            )
        
        return super().update(request, *args, **kwargs)
    
    def destroy(self, request, *args, **kwargs):
        """Override destroy to check ownership"""
        activity = self.get_object()
        
        # Check if user can delete this activity
        if not (activity.plan.created_by == request.user or 
                activity.plan.group.is_admin(request.user)):
            return Response(
                {'error': 'Permission denied. Only plan creator or group admin can delete activities'}, 
                status=status.HTTP_403_FORBIDDEN
            )
        
        return super().destroy(request, *args, **kwargs)
    
    #API lấy hoạt động theo kế hoạch - OPTIMIZED
    @action(detail=False, methods=['get'])
    def by_plan(self, request):
        """Get activities for specific plan - SECURE & OPTIMIZED"""
        plan_id = request.query_params.get('plan_id')
        
        if not plan_id:
            return Response(
                {'error': 'plan_id parameter required'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        # Validate user access to plan
        try:
            plan = Plan.objects.filter(
                models.Q(id=plan_id) & (
                    models.Q(group__members=request.user) | 
                    models.Q(created_by=request.user)
                )
            ).first()
            
            if not plan:
                raise Plan.DoesNotExist()
            
            # Get activities with optimized query
            activities = self.get_queryset().filter(
                plan=plan
            ).order_by('start_time')
            
            serializer = self.get_serializer(activities, many=True)
            return Response({
                'activities': serializer.data,
                'plan_id': plan_id,
                'plan_title': plan.title,
                'count': len(activities)
            })
            
        except Plan.DoesNotExist:
            return Response(
                {'error': 'Plan not found or access denied'}, 
                status=status.HTTP_404_NOT_FOUND
            )
    
    #API lấy hoạt động theo khoảng thời gian - NEW
    @action(detail=False, methods=['get'])
    def by_date_range(self, request):
        """Get user's activities within date range"""
        start_date = request.query_params.get('start_date')
        end_date = request.query_params.get('end_date')
        
        if not start_date or not end_date:
            return Response(
                {'error': 'start_date and end_date parameters required (YYYY-MM-DD)'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        try:
            start_date = datetime.strptime(start_date, '%Y-%m-%d').date()
            end_date = datetime.strptime(end_date, '%Y-%m-%d').date()
            
            activities = self.get_queryset().filter(
                start_time__date__range=[start_date, end_date]
            ).select_related('plan').order_by('start_time')
            
            serializer = self.get_serializer(activities, many=True)
            return Response({
                'activities': serializer.data,
                'date_range': {
                    'start': start_date.isoformat(),
                    'end': end_date.isoformat()
                },
                'count': len(activities)
            })
            
        except ValueError:
            return Response(
                {'error': 'Invalid date format. Use YYYY-MM-DD'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
    
    #API lấy hoạt động sắp tới - NEW
    @action(detail=False, methods=['get'])
    def upcoming(self, request):
        """Get user's upcoming activities"""
        limit = min(int(request.query_params.get('limit', 20)), 50)  # Max 50
        
        now = timezone.now()
        activities = self.get_queryset().filter(
            start_time__gt=now
        ).select_related('plan').order_by('start_time')[:limit]
        
        serializer = self.get_serializer(activities, many=True)
        return Response({
            'activities': serializer.data,
            'count': len(activities),
            'timestamp': now.isoformat()
        })
    
    #API tìm kiếm hoạt động - NEW
    @action(detail=False, methods=['get'])
    def search(self, request):
        """Search activities within user's plans"""
        query = request.query_params.get('q')
        plan_id = request.query_params.get('plan_id')
        
        if not query:
            return Response(
                {'error': 'Search query (q) parameter required'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        # Base queryset - only user's activities
        queryset = self.get_queryset().filter(
            models.Q(title__icontains=query) |
            models.Q(description__icontains=query) |
            models.Q(location_name__icontains=query)
        ).select_related('plan')
        
        # Filter by specific plan if provided
        if plan_id:
            try:
                Plan.objects.filter(
                    models.Q(id=plan_id) & (
                        models.Q(group__members=request.user) | 
                        models.Q(created_by=request.user)
                    )
                ).first()
                queryset = queryset.filter(plan_id=plan_id)
            except Plan.DoesNotExist:
                return Response(
                    {'error': 'Plan not found or access denied'}, 
                    status=status.HTTP_404_NOT_FOUND
                )
        
        # Limit search results for performance
        activities = queryset.order_by('start_time')[:30]
        serializer = self.get_serializer(activities, many=True)
        
        return Response({
            'activities': serializer.data,
            'count': len(activities),
            'query': query
        })





class PlacesSearchView(APIView):
    """Search for places using Goong Map API"""
    permission_classes = [IsAuthenticated]
    
    def get(self, request):
        query = request.query_params.get('query')
        lat = request.query_params.get('lat')
        lng = request.query_params.get('lng')
        radius = int(request.query_params.get('radius', 5000))
        place_type = request.query_params.get('type')
        
        if not query:
            return Response(
                {'error': 'query parameter required'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        # Convert lat/lng to tuple if provided
        location = None
        if lat and lng:
            try:
                location = (float(lat), float(lng))
            except ValueError:
                return Response(
                    {'error': 'Invalid lat/lng format'}, 
                    status=status.HTTP_400_BAD_REQUEST
                )
        
        places = goong_service.search_places(
            query=query,
            location=location,
            radius=radius
        )
        
        return Response({'places': places})

class PlaceDetailsView(APIView):
    """Get detailed information about a place"""
    permission_classes = [IsAuthenticated]
    
    def get(self, request, place_id):
        place_details = goong_service.get_place_details(place_id)
        
        if place_details:
            return Response({'place': place_details})
        else:
            return Response(
                {'error': 'Place not found'}, 
                status=status.HTTP_404_NOT_FOUND
            )

class NearbyPlacesView(APIView):
    """Get nearby places for a location"""
    permission_classes = [IsAuthenticated]
    
    def get(self, request):
        lat = request.query_params.get('lat')
        lng = request.query_params.get('lng')
        radius = int(request.query_params.get('radius', 1000))
        place_type = request.query_params.get('type')
        
        if not lat or not lng:
            return Response(
                {'error': 'lat and lng parameters required'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        try:
            lat = float(lat)
            lng = float(lng)
        except ValueError:
            return Response(
                {'error': 'Invalid lat/lng format'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        places = goong_service.nearby_search(
            latitude=lat,
            longitude=lng,
            radius=radius,
            type_filter=place_type
        )
        
        return Response({'places': places})

class PlaceAutocompleteView(APIView):
    """Get place suggestions for autocomplete"""
    permission_classes = [IsAuthenticated]
    
    def get(self, request):
        input_text = request.query_params.get('input')
        lat = request.query_params.get('lat')
        lng = request.query_params.get('lng')
        radius = int(request.query_params.get('radius', 5000))
        
        if not input_text:
            return Response(
                {'error': 'input parameter required'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        # Convert lat/lng to tuple if provided for location bias
        location = None
        if lat and lng:
            try:
                location = (float(lat), float(lng))
            except ValueError:
                return Response(
                    {'error': 'Invalid lat/lng format'}, 
                    status=status.HTTP_400_BAD_REQUEST
                )
        
        suggestions = goong_service.autocomplete(
            input_text=input_text,
            location=location,
            radius=radius
        )
        
        return Response({'suggestions': suggestions})

class GeocodeView(APIView):
    """Convert address to coordinates and vice versa"""
    permission_classes = [IsAuthenticated]
    
    def get(self, request):
        address = request.query_params.get('address')
        lat = request.query_params.get('lat')
        lng = request.query_params.get('lng')
        
        if address:
            # Forward geocoding: address to coordinates
            result = goong_service.geocode(address)
            if result:
                return Response({'result': result})
            else:
                return Response(
                    {'error': 'Address not found'}, 
                    status=status.HTTP_404_NOT_FOUND
                )
        
        elif lat and lng:
            # Reverse geocoding: coordinates to address
            try:
                lat = float(lat)
                lng = float(lng)
                result = goong_service.reverse_geocode(lat, lng)
                if result:
                    return Response({'result': result})
                else:
                    return Response(
                        {'error': 'Location not found'}, 
                        status=status.HTTP_404_NOT_FOUND
                    )
            except ValueError:
                return Response(
                    {'error': 'Invalid lat/lng format'}, 
                    status=status.HTTP_400_BAD_REQUEST
                )
        
        else:
            return Response(
                {'error': 'Either address or lat/lng parameters required'}, 
                status=status.HTTP_400_BAD_REQUEST
            )

class SendNotificationView(APIView):
    """Send push notification manually (for testing)"""
    permission_classes = [IsAuthenticated]
    
    def post(self, request):
        recipient_id = request.data.get('recipient_id')
        title = request.data.get('title')
        body = request.data.get('body')
        data = request.data.get('data', {})
        
        if not all([recipient_id, title, body]):
            return Response(
                {'error': 'recipient_id, title, and body are required'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        try:
            recipient = User.objects.get(id=recipient_id)
            if hasattr(recipient, 'fcm_token') and recipient.fcm_token:
                success = notification_service.send_push_notification(
                    fcm_tokens=[recipient.fcm_token],
                    title=title,
                    body=body,
                    data=data
                )
                
                if success:
                    return Response({'message': 'Notification sent successfully'})
                else:
                    return Response(
                        {'error': 'Failed to send notification'}, 
                        status=status.HTTP_500_INTERNAL_SERVER_ERROR
                    )
            else:
                return Response(
                    {'error': 'Recipient has no FCM token'}, 
                    status=status.HTTP_400_BAD_REQUEST
                )
                
        except User.DoesNotExist:
            return Response(
                {'error': 'Recipient not found'}, 
                status=status.HTTP_404_NOT_FOUND
            )

# ============================================================================
# ENHANCED VIEWS WITH SERVICE INTEGRATION
# ============================================================================

#Viết riêng ra để tránh xung đột với các view gốc, nó thuộc về services, dễ test, dễ bảo trì, nếu viết chung thì 1 services không work toàn bộ viewset broken
class EnhancedGroupViewSet(GroupViewSet):
    """Enhanced Group ViewSet with notification services"""
    
    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, IsGroupMember])
    def send_message_with_notification(self, request, pk=None):
        """Send message to group with push notification"""
        group = self.get_object()
        content = request.data.get('content')
        message_type = request.data.get('message_type', 'text')
        
        try:
            message = group.send_message(
                sender=request.user,
                content=content,
                message_type=message_type
            )
            
            # Send push notification to group members
            notification_service.notify_new_message(
                group_id=str(group.id),
                sender_name=request.user.username,
                message_preview=content[:100],
                sender_id=str(request.user.id)
            )
            
            serializer = ChatMessageSerializer(message)
            return Response(serializer.data, status=status.HTTP_201_CREATED)
            
        except PermissionError as e:
            return Response(
                {'error': str(e)}, 
                status=status.HTTP_403_FORBIDDEN
            )

class EnhancedPlanViewSet(PlanViewSet):
    """Enhanced Plan ViewSet with places and notification services"""
    
    @action(detail=True, methods=['post'])
    def add_activity_with_place(self, request, pk=None):
        """Add activity to plan with place lookup - THIN VIEW"""
        plan = self.get_object()
        
        # ✅ THIN VIEW - basic validation then delegate to model
        title = request.data.get('title')
        start_time = request.data.get('start_time')
        end_time = request.data.get('end_time')
        place_id = request.data.get('place_id')
        
        if not all([title, start_time, end_time]):
            return Response(
                {'error': 'title, start_time, and end_time are required'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        try:
            # Parse datetime
            start_time = datetime.fromisoformat(start_time.replace('Z', '+00:00'))
            end_time = datetime.fromisoformat(end_time.replace('Z', '+00:00'))
            
            # Extract extra fields
            extra_fields = {k: v for k, v in request.data.items() 
                           if k not in ['title', 'start_time', 'end_time', 'place_id']}
            
            # ✅ DELEGATE to FAT MODEL
            activity = plan.add_activity_with_place(
                title=title,
                start_time=start_time,
                end_time=end_time,
                place_id=place_id,
                **extra_fields
            )
            
            # ✅ DELEGATE notifications to model
            plan.notify_activity_added(request.user)
            
            return Response(
                PlanActivitySerializer(activity).data, 
                status=status.HTTP_201_CREATED
            )
            
        except ValueError as e:
            return Response(
                {'error': str(e)}, 
                status=status.HTTP_400_BAD_REQUEST
            )
    


