from typing import Dict, List, Optional, Any, Union, TYPE_CHECKING
from django.shortcuts import get_object_or_404
from django.contrib.auth import authenticate, get_user_model
from django.utils import timezone
from django.db import models, transaction
from django.core.exceptions import ValidationError, PermissionDenied
from django.db.models import Prefetch
from datetime import datetime

from rest_framework import viewsets, status, generics, mixins
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework.views import APIView
from rest_framework.request import Request

if TYPE_CHECKING:
    from django.db.models import QuerySet

from .models import (
    User, Group, Plan, Friendship, ChatMessage, PlanActivity, 
    GroupMembership, Conversation
)
from .serializers import (
    GroupCreateSerializer, GroupSummarySerializer, PlanSummarySerializer, 
    UserSerializer, UserCreateSerializer, UserSummarySerializer, GroupSerializer, 
    PlanSerializer, PlanCreateSerializer, FriendshipSerializer, FriendRequestSerializer, 
    ChatMessageSerializer, PlanActivitySerializer, ConversationSerializer
)
from .permissions import (
    IsAuthenticatedAndActive, PlanPermission, GroupPermission,
    ChatMessagePermission, FriendshipPermission, UserProfilePermission,
    IsGroupMember, IsGroupAdmin, PlanActivityPermission, ConversationPermission
)

from .services import UserService, GroupService, PlanService, ChatService
from .integrations import GoongMapService, NotificationService
from .oauth2_utils import OAuth2ResponseFormatter

# Import services at the end to avoid circular imports
# These will be imported lazily when needed

from oauth2_provider.models import AccessToken, RefreshToken

User = get_user_model()


# ============================================================================
# OAuth2 Authentication Views (Optimized)
# ============================================================================

class OAuth2LogoutView(APIView):
    """
    Optimized OAuth2 logout with proper token cleanup
    Sets user offline status and revokes tokens
    """
    permission_classes = [IsAuthenticated]

    def post(self, request: Request) -> Response:
        """Handle logout with token revocation and status update"""
        user = request.user
        token_string = getattr(request.auth, 'token', None) if hasattr(request.auth, 'token') else request.auth
        revoked = False
        
        try:
            if token_string:
                at_qs = AccessToken.objects.select_for_update().filter(
                    token=token_string, user=user
                )
                if at_qs.exists():
                    at = at_qs.first()
                    # Delete linked refresh tokens first
                    RefreshToken.objects.filter(access_token=at).delete()
                    at.delete()
                    revoked = True
            
            # Use model method for status update
            user.set_online_status(False)
            
            return Response({
                'message': 'Logged out successfully',
                'timestamp': timezone.now().isoformat(),
                'token_revoked': revoked
            })
        except Exception as e:
            data, code = OAuth2ResponseFormatter.error_response(
                'server_error', f'Logout failed: {e}', 500
            )
            return Response(data, status=code)


# ============================================================================
# Core API ViewSets (Optimized)
# ============================================================================

class UserViewSet(viewsets.GenericViewSet,
                  mixins.CreateModelMixin,
                  mixins.RetrieveModelMixin,
                  mixins.UpdateModelMixin):
    """
    Optimized UserViewSet with proper queryset optimization
    Uses model methods and cached counts for performance
    """
    serializer_class = UserSerializer
    
    def get_permissions(self):
        """Dynamic permission assignment based on action"""
        if self.action == 'create':
            permission_classes = [AllowAny]
        elif self.action in ['update', 'partial_update', 'destroy']:
            permission_classes = [IsAuthenticated, UserProfilePermission]
        else:
            permission_classes = [IsAuthenticatedAndActive]
        return [permission() for permission in permission_classes]
    
    def get_queryset(self):
        """
        Optimized queryset with cached counts
        Only returns current user for security
        """
        if not self.request.user.is_authenticated:
            return User.objects.none()
        
        # Use optimized queryset with cached counts
        return User.objects.filter(
            id=self.request.user.id
        ).with_cached_counts()
    
    def get_serializer_class(self) -> type:
        """Dynamic serializer selection"""
        if self.action == 'create':
            return UserCreateSerializer
        if self.action == "list":
            return UserSummarySerializer
        return UserSerializer
    
    def list(self, request: Request) -> Response:
        """
        Optimized user profile endpoint
        Returns current user with all computed fields
        """
        # Get user with all counts annotated for better performance
        user = User.objects.with_cached_counts().get(id=request.user.id)
        user_serializer = self.get_serializer(user)
        return Response({
            'user': user_serializer.data,
            'message': 'User profile retrieved successfully'
        })
    
    @action(detail=False, methods=['get'])
    def search(self, request):
        """
        Optimized user search for friend requests
        Uses efficient queries and pagination
        """
        query = request.query_params.get('q')
        if not query or len(query) < 2:
            return Response(
                {'error': 'Search query (q) parameter required (min 2 characters)'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        # Optimized query with select_related and only necessary fields
        users = User.objects.filter(
            models.Q(username__icontains=query) |
            models.Q(email__icontains=query) |
            models.Q(first_name__icontains=query) |
            models.Q(last_name__icontains=query)
        ).exclude(
            id=request.user.id
        ).only(
            'id', 'username', 'first_name', 'last_name', 
            'avatar', 'is_online', 'last_seen'
        )[:20]  # Limit results for performance
        
        # Use optimized serializer
        serializer = UserSummarySerializer(users, many=True, context={'request': request})
        
        return Response({
            'users': serializer.data,
            'count': len(serializer.data),
            'query': query
        })
    
    @action(detail=False, methods=['get'])
    def profile(self, request: Request) -> Response:
        """
        Get current user profile with optimized counts
        Uses cached counts for better performance
        """
        # Get user with cached counts for performance
        user = User.objects.with_cached_counts().get(id=request.user.id)
        serializer = self.get_serializer(user) 
        return Response(serializer.data)
    
    @action(detail=False, methods=['put', 'patch'])
    def update_profile(self, request: Request) -> Response:
        """
        Update current user profile
        Uses atomic transaction for data consistency
        """
        with transaction.atomic():
            serializer = self.get_serializer(
                request.user, 
                data=request.data, 
                partial=True
            )
            serializer.is_valid(raise_exception=True)
            user = serializer.save()
            
            # Update last seen on profile updates
            user.update_last_seen()
            
        return Response(serializer.data)
    
    @action(detail=False, methods=['get'])
    def my_plans(self, request):
        """
        Get user's plans with optimized queries
        Uses model methods and efficient filtering
        """
        user = request.user
        plan_type = request.query_params.get('type', 'all')
        
        # Use optimized queryset from model
        queryset = Plan.objects.for_user(user).with_stats()
        
        if plan_type == 'personal':
            queryset = queryset.filter(plan_type='personal')
        elif plan_type == 'group':
            queryset = queryset.filter(plan_type='group')
        
        page = self.paginate_queryset(queryset)
        if page is not None:
            serializer = PlanSummarySerializer(page, many=True, context={'request': request})
            return self.get_paginated_response(serializer.data)
        
        serializer = PlanSummarySerializer(queryset, many=True, context={'request': request})
        return Response(serializer.data)
    
    @action(detail=False, methods=['get'])
    def my_groups(self, request):
        """
        Get user's groups with optimized queries
        Uses model properties for efficient filtering
        """
        user = request.user
        
        # Use model property for optimized query
        groups = user.joined_groups.with_full_stats()
        
        page = self.paginate_queryset(groups)
        if page is not None:
            serializer = GroupSummarySerializer(page, many=True, context={'request': request})
            return self.get_paginated_response(serializer.data)
        
        serializer = GroupSummarySerializer(groups, many=True, context={'request': request})
        return Response(serializer.data)
    
    @action(detail=False, methods=['get'])
    def my_activities(self, request):
        """
        Get user's plan activities with optimized filtering
        Uses model methods for efficient queries
        """
        user = request.user
        activity_type = request.query_params.get('type', 'all')
        
        # Use optimized queryset from model
        queryset = PlanActivity.objects.filter(
            plan__created_by=user
        ).select_related('plan', 'location').prefetch_related('plan__group')
        
        if activity_type == 'personal':
            queryset = queryset.filter(plan__group__isnull=True)
        elif activity_type == 'group':
            queryset = queryset.filter(plan__group__isnull=False)
        
        page = self.paginate_queryset(queryset)
        if page is not None:
            serializer = PlanActivitySerializer(page, many=True, context={'request': request})
            return self.get_paginated_response(serializer.data)
        
        serializer = PlanActivitySerializer(queryset, many=True, context={'request': request})
        return Response(serializer.data)
    
    @action(detail=False, methods=['post'])
    def set_online_status(self, request):
        """
        Update user online status efficiently
        Uses atomic transaction for consistency
        """
        is_online = request.data.get('is_online', True)
        
        with transaction.atomic():
            request.user.set_online_status(is_online)
        
        return Response({
            'is_online': request.user.is_online,
            'last_seen': request.user.last_seen
        })
    
    @action(detail=False, methods=['get'])
    def friendship_stats(self, request):
        """
        Get user's friendship statistics
        Uses cached counts for performance
        """
        # Get user with all counts annotated to avoid N+1 queries
        user = User.objects.with_cached_counts().get(id=request.user.id)
        
        return Response({
            'friends_count': user.friends_count,
            'pending_sent_count': user.pending_sent_count,
            'pending_received_count': user.pending_received_count,
            'blocked_count': user.blocked_count
        })
    
    @action(detail=False, methods=['get'])
    def recent_conversations(self, request):
        """
        Get recent conversations with optimized queries
        Uses model property for efficient filtering
        """
        conversations = request.user.recent_conversations[:10]
        serializer = GroupSerializer(conversations, many=True, context={'request': request})
        
        return Response({
            'conversations': serializer.data,
            'timestamp': timezone.now().isoformat()
        })
    
    @action(detail=False, methods=['get'])
    def unread_count(self, request):
        """
        Get unread messages count efficiently
        Uses cached property for performance
        """
        return Response({
            'unread_count': request.user.unread_messages_count,
            'timestamp': timezone.now().isoformat()
        })
    
    def retrieve(self, request, pk=None):
        """
        Get user profile by ID with optimized queries
        Uses Django built-in functions for cleaner code
        """
        user = get_object_or_404(User, id=pk)
        
        # Check permission using built-in permission system
        self.check_object_permissions(request, user)
        
        # Use optimized serializer with only needed fields
        serializer = UserSummarySerializer(user, context={'request': request})
        return Response(serializer.data)
    
    @action(detail=True, methods=['get'])
    def friendship_status(self, request, pk=None):
        """
        Get friendship status with a user using canonical model
        Uses optimized queries with model methods
        """
        target_user = get_object_or_404(User, id=pk)
        current_user = request.user
        
        if current_user == target_user:
            return Response({'status': 'self'})
        
        # Use canonical friendship model method
        status_info = current_user.get_friendship_status(target_user)
        
        return Response(status_info)
    
    @action(detail=True, methods=['delete'])
    def unfriend(self, request, pk=None):
        """
        Unfriend/Remove friendship - uses service layer
        """
        from . import integrations as main_services
        
        target_user = get_object_or_404(User, id=pk)
        current_user = request.user
        
        if current_user == target_user:
            return Response({'error': 'Cannot unfriend yourself'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        success, message = UserService.unfriend_user(current_user, target_user)
        
        if not success:
            return Response({'error': message}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        return Response({'message': message})
    
    # OPTIMIZED API block user
    @action(detail=True, methods=['post'])
    def block(self, request, pk=None):
        """Block user - uses service layer"""
        target_user = get_object_or_404(User, id=pk)
        current_user = request.user
        
        if current_user == target_user:
            return Response({'error': 'Cannot block yourself'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        success, message = UserService.block_user(current_user, target_user)
        
        if not success:
            return Response({'error': message}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        return Response({'message': message})
    
    # OPTIMIZED API unblock user
    @action(detail=True, methods=['delete'])
    def unblock(self, request, pk=None):
        """Unblock user - SECURE"""
        target_user = get_object_or_404(User, id=pk)
        current_user = request.user
        
        if current_user == target_user:
            return Response({'error': 'Cannot unblock yourself'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        friendship = Friendship.objects.filter(
            user=current_user,
            friend=target_user,
            status=Friendship.BLOCKED
        ).first()
        
        if not friendship:
            return Response({'error': 'User is not blocked'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Remove the block by deleting the friendship
        friendship.delete()
        return Response({'message': 'User unblocked successfully'})
    
    def _can_view_profile(self, current_user, target_user):
        """Check if current user can view target user profile"""
        if current_user == target_user:
            return True
        
        # Check if profile is public (default True)
        if getattr(target_user, 'is_profile_public', True):
            return True
        
        # Check if they are friends
        from .models import Friendship
        return Friendship.are_friends(current_user, target_user)
        

class GroupViewSet(viewsets.GenericViewSet,
                   mixins.CreateModelMixin,
                   mixins.RetrieveModelMixin,
                   mixins.UpdateModelMixin,
                   mixins.DestroyModelMixin):
    """
    Optimized Group operations with enhanced security
    Uses Django best practices and efficient queries
    """
    serializer_class = GroupSerializer
    permission_classes = [IsAuthenticated, GroupPermission]
    
    def get_serializer_class(self):
        """
        Use optimized serializer for different operations
        Reduces payload size and improves performance
        """
        if self.action == 'create':
            return GroupCreateSerializer
        elif self.action == 'list':
            return GroupSummarySerializer
        return self.serializer_class

    def get_queryset(self):
        """
        Secure queryset with optimized database queries
        Only groups user is member of with proper prefetching
        """
        return Group.objects.filter(
            members=self.request.user
        ).select_related(
            'admin'
        ).prefetch_related(
            'members__profile',
            'memberships__user'
        ).with_full_stats()
    
    def list(self, request):
        """
        Custom secure list with optimized queries
        Uses cached counts for better performance
        """
        queryset = self.get_queryset().order_by('-created_at')
        
        page = self.paginate_queryset(queryset)
        if page is not None:
            serializer = self.get_serializer(page, many=True)
            return self.get_paginated_response(serializer.data)
        
        serializer = self.get_serializer(queryset, many=True)
        return Response(serializer.data)
    
    def perform_create(self, serializer):
        """
        Auto-add creator as admin with atomic transaction
        Ensures data consistency and proper membership
        """
        with transaction.atomic():
            group = serializer.save(admin=self.request.user)
            # Membership is handled in model's save method
        return group
    
    @action(detail=False, methods=['post'])
    def join(self, request):
        """
        Join group by invite code or ID with enhanced security
        Uses atomic transactions and proper validation
        """
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
                group = Group.objects.get(
                    id=group_id, 
                    is_public=True
                )
            
            # Use service layer for joining
            success, message = GroupService.join_group_by_invite(group, request.user)
            
            if not success:
                return Response({'error': message}, status=status.HTTP_400_BAD_REQUEST)
            
            return Response({
                'message': message,
                'group': GroupSummarySerializer(group, context={'request': request}).data
            })
            
        except Group.DoesNotExist:
            return Response(
                {'error': 'Group not found or not accessible'}, 
                status=status.HTTP_404_NOT_FOUND
            )
    
    @action(detail=False, methods=['get'])
    def my_groups(self, request):
        """
        Get user's joined groups with efficient pagination
        Uses optimized queryset and serializer
        """
        queryset = self.get_queryset()
        
        page = self.paginate_queryset(queryset)
        if page is not None:
            serializer = self.get_serializer(page, many=True)
            return self.get_paginated_response(serializer.data)
        
        serializer = self.get_serializer(queryset, many=True)
        return Response(serializer.data)
    
    @action(detail=False, methods=['get'])
    def created_by_me(self, request):
        """
        Get groups created by user with optimized queries
        Uses admin field for filtering
        """
        queryset = self.get_queryset().filter(admin=request.user)
        
        page = self.paginate_queryset(queryset)
        if page is not None:
            serializer = self.get_serializer(page, many=True)
            return self.get_paginated_response(serializer.data)
        
        serializer = self.get_serializer(queryset, many=True)
        return Response(serializer.data)
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
    
    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, IsGroupAdmin])
    def add_member(self, request, pk=None):
        """Admin adds friend to group - uses service layer"""
        group = self.get_object()
        user_id = request.data.get('user_id')
        
        if not user_id:
            return Response({'error': 'user_id required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        try:
            target_user = User.objects.get(id=user_id)
        except User.DoesNotExist:
            return Response({'error': 'User not found'}, 
                          status=status.HTTP_404_NOT_FOUND)
        
        # Use service layer for adding member
        success, message = GroupService.add_member_to_group(group, target_user)
        
        if not success:
            return Response({'error': message}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        return Response({
            'message': f'Added {target_user.username} to group successfully'
        })
    
    #API gửi tin nhắn đến nhóm
    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, IsGroupMember])
    def send_message(self, request, pk=None):
        """Send message to group using service layer"""
        group = self.get_object()
        content = request.data.get('content')
        message_type = request.data.get('message_type', 'text')
        
        try:
            message = ChatService.send_message(
                sender=request.user,
                group=group,
                content=content,
                message_type=message_type
            )
            serializer = ChatMessageSerializer(message)
            return Response(serializer.data, status=status.HTTP_201_CREATED)
        except ValidationError as e:
            return Response(
                {'error': str(e)}, 
                status=status.HTTP_403_FORBIDDEN
            )
    
    #API lấy danh sách tin nhắn gần đây
    @action(detail=True, methods=['get'], permission_classes=[IsAuthenticated, IsGroupMember])
    def recent_messages(self, request, pk=None):
        """Get recent messages - OPTIMIZED using property"""
        group = self.get_object()
        limit = int(request.query_params.get('limit', 50))
           
        serializer = ChatMessageSerializer(group.get_recent_messages(limit), many=True, context={'request': request})
        
        return Response({
            'messages': serializer.data,
            'group_id': str(group.id),
            'count': len(serializer.data)
        })
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

    #API lấy danh sách kế hoạch của nhóm
    @action(detail=True, methods=['get'], permission_classes=[IsAuthenticated, IsGroupMember])
    def plans(self, request, pk=None):
        """Get group plans - OPTIMIZED"""
        group = self.get_object()
        
        # Get all plans for this group with optimizations
        plans = Plan.objects.filter(group=group).select_related(
            'creator', 'group'
        ).prefetch_related('activities').order_by('-created_at')
        
        serializer = PlanSummarySerializer(plans, many=True, context={'request': request})
        
        return Response({
            'plans': serializer.data,
            'group_id': str(group.id),
            'group_name': group.name,
            'count': len(serializer.data),
            'can_create_plan': group.is_admin(request.user)  # Only admins can create
        })

class PlanViewSet(viewsets.ModelViewSet):
    """
    Optimized Plan CRUD operations with enhanced security
    Uses Django best practices and efficient queries
    """
    serializer_class = PlanSerializer
    permission_classes = [IsAuthenticated, PlanPermission]
    
    def get_serializer_class(self):
        """
        Use optimized serializer for different operations
        Reduces payload size and improves performance
        """
        if self.action == 'create':
            return PlanCreateSerializer
        elif self.action == 'list':
            return PlanSummarySerializer
        return self.serializer_class
    
    def get_queryset(self):
        """
        Secure queryset with comprehensive optimizations
        Only user's accessible plans with proper prefetching
        """
        return Plan.objects.filter(
            models.Q(group__members=self.request.user) |
            models.Q(creator=self.request.user)
        ).select_related(
            'creator', 'group'
        ).prefetch_related(
            'group__members',
            'activities__location'
        ).with_stats().distinct().order_by('-created_at')
    
    def perform_create(self, serializer):
        """
        Auto-set creator with atomic transaction
        Handles notifications and ensures data consistency
        """
        with transaction.atomic():
            plan = serializer.save(creator=self.request.user)
            
            # Send notification asynchronously if service available
            try:
                if hasattr(NotificationService, 'notify_plan_created'):
                    NotificationService.notify_plan_created(
                        plan_id=str(plan.id),
                        creator_name=self.request.user.username,
                        group_id=str(plan.group.id) if plan.group else None
                    )
            except Exception:
                pass  # Don't fail plan creation if notification fails
        
        return plan

    # def create(self, request, *args, **kwargs):
    #     """Override create to return consistent data format"""
    #     serializer = self.get_serializer(data=request.data)
    #     serializer.is_valid(raise_exception=True)
    #     plan = self.perform_create(serializer)
        
    #     # Return data using PlanSummarySerializer for consistency
    #     response_serializer = PlanSummarySerializer(plan, context={'request': request})
    #     headers = self.get_success_headers(response_serializer.data)
    #     return Response(response_serializer.data, status=status.HTTP_201_CREATED, headers=headers)
    
    def list(self, request):
        """
        Enhanced list with optimized metadata
        Uses proper pagination and efficient queries
        """
        queryset = self.get_queryset()
        
        page = self.paginate_queryset(queryset)
        if page is not None:
            serializer = self.get_serializer(page, many=True)
            return self.get_paginated_response(serializer.data)
        
        serializer = self.get_serializer(queryset, many=True)
        return Response(serializer.data)
    
    @action(detail=False, methods=['get'])
    def my_plans(self, request):
        """
        Get user's plans with optimized filtering
        Uses efficient queries and proper pagination
        """
        queryset = self.get_queryset()
        plan_type = request.query_params.get('type', 'all')
        
        if plan_type == 'personal':
            queryset = queryset.filter(group__isnull=True)
        elif plan_type == 'group':
            queryset = queryset.filter(group__isnull=False)
        
        page = self.paginate_queryset(queryset)
        if page is not None:
            serializer = self.get_serializer(page, many=True)
            return self.get_paginated_response(serializer.data)
        
        serializer = self.get_serializer(queryset, many=True)
        return Response(serializer.data)
    
    #API lấy kế hoạch theo ngày
    @action(detail=True, methods=['get'])
    def activities_by_date(self, request, pk=None):
        """Get activities grouped by date - OPTIMIZED using property"""
        plan = self.get_object()
        
        # Using property for grouped activities
        activities_by_date = plan.activities_by_date  # Using property
        
        # Convert to serializable format
        result = {}
        for date, activities in activities_by_date.items():
            result[date.isoformat()] = PlanActivitySerializer(
                activities, many=True, context={'request': request}
            ).data
        
        return Response({
            'activities_by_date': result,
            'plan_id': str(plan.id),
            'total_activities': plan.activities_count  # Using property
        })
        
    
    #API lấy người tham gia kế hoạch
    @action(detail=True, methods=['get'])
    def collaborators(self, request, pk=None):
        """Get plan collaborators - OPTIMIZED using property"""
        plan = self.get_object()
        collaborators = plan.collaborators  # Using property
        
        serializer = UserSerializer(collaborators, many=True, context={'request': request})
        
        return Response({
            'collaborators': serializer.data,
            'count': len(collaborators),
            'plan_type': plan.plan_type
        })
        
    
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
        plan = self.get_object()
        
        return Response({
            'id': str(plan.id),
            'title': plan.title,
            'duration': {
                'days': plan.duration_days,          # Using property
                'display': plan.duration_display      # Using property
            },
            'activities': {
                'count': plan.activities_count,       # Using property
                'by_date': len(plan.activities_by_date)  # Using property
            },
            'budget': {
                'planned': plan.budget,
                'estimated': plan.total_estimated_cost,  # Using property
                'comparison': plan.budget_vs_estimated,  # Using property
                'over_budget': plan.is_over_budget       # Using property
            },
            'status': {
                'code': plan.status,
                'display': plan.status_display          # Using property
            },
            'collaboration': {
                'type': plan.plan_type,
                'collaborators_count': len(plan.collaborators)  # Using property
            },
            'timestamps': {
                'created': plan.created_at,
                'updated': plan.updated_at
            }
        })
    
    @action(detail=True, methods=['get'])
    def schedule(self, request, pk=None):
        """Get plan activities schedule/timeline - OPTIMIZED"""
        plan = self.get_object()
        
        # Get activities with optimized query
        activities = plan.activities.order_by('start_time')
        
        # Group activities by date
        schedule_by_date = {}
        for activity in activities:
            if activity.start_time:
                date_key = activity.start_time.date().isoformat()
                if date_key not in schedule_by_date:
                    schedule_by_date[date_key] = []
                
                # Calculate duration in minutes
                duration_minutes = 0
                if activity.start_time and activity.end_time:
                    duration_delta = activity.end_time - activity.start_time
                    duration_minutes = int(duration_delta.total_seconds() / 60)
                
                schedule_by_date[date_key].append({
                    'id': str(activity.id),
                    'title': activity.title,
                    'description': activity.description,
                    'activity_type': activity.activity_type,
                    'start_time': activity.start_time,
                    'end_time': activity.end_time,
                    'duration_minutes': duration_minutes,
                    'estimated_cost': float(activity.estimated_cost) if activity.estimated_cost else 0,
                    'location_name': activity.location_name,
                    'location_address': activity.location_address,
                    'notes': activity.notes,
                    'is_completed': activity.is_completed
                })
        
        # Calculate timeline statistics
        total_activities = activities.count()
        completed_activities = activities.filter(is_completed=True).count()
        
        # Calculate total duration in minutes
        total_duration = 0
        for activity in activities:
            if activity.start_time and activity.end_time:
                duration_delta = activity.end_time - activity.start_time
                total_duration += int(duration_delta.total_seconds() / 60)
        
        return Response({
            'plan_id': str(plan.id),
            'plan_title': plan.title,
            'schedule_by_date': schedule_by_date,
            'statistics': {
                'total_activities': total_activities,
                'completed_activities': completed_activities,
                'completion_rate': (completed_activities / total_activities * 100) if total_activities > 0 else 0,
                'total_duration_minutes': total_duration,
                'total_duration_display': f"{total_duration // 60}h {total_duration % 60}m" if total_duration > 0 else "0m",
                'date_range': {
                    'start_date': plan.start_date,
                    'end_date': plan.end_date,
                    'duration_days': plan.duration_days
                }
            },
            'permissions': {
                'can_edit': self._can_user_edit_plan(plan, request.user),
                'can_add_activity': self._can_user_edit_plan(plan, request.user)
            }
        })
    
    @action(detail=True, methods=['post'])
    def create_activity(self, request, pk=None):
        """Create new activity in plan - ADMIN ONLY for group plans"""
        plan = self.get_object()
        
        # Check if user can add activities to this plan
        if plan.plan_type == 'group' and plan.group and not plan.group.is_admin(request.user):
            return Response(
                {'error': 'Only group admins can add activities to group plans'}, 
                status=status.HTTP_403_FORBIDDEN
            )
        elif plan.plan_type == 'personal' and plan.user != request.user:
            return Response(
                {'error': 'You can only add activities to your own plans'}, 
                status=status.HTTP_403_FORBIDDEN
            )
        
        # Create activity in plan
        activity_data = request.data.copy()
        activity_data['plan'] = plan.id
        
        activity_serializer = PlanActivitySerializer(data=activity_data)
        
        if activity_serializer.is_valid():
            activity = activity_serializer.save()
            
            return Response({
                'message': 'Activity created successfully',
                'activity': PlanActivitySerializer(activity).data
            }, status=status.HTTP_201_CREATED)
        
        return Response(activity_serializer.errors, status=status.HTTP_400_BAD_REQUEST)
    
    def _can_user_edit_plan(self, plan, user):
        """Check if user can edit plan - delegates to service layer"""
        from .integrations import plan_service
        return plan_service.can_edit_plan(plan, user)
    
    @action(detail=True, methods=['put', 'patch'], url_path='activities/(?P<activity_id>[^/.]+)')
    def update_activity(self, request, pk=None, activity_id=None):
        """Update activity in plan - uses service layer for permission checking"""
        plan = self.get_object()
        
        # Check permissions using service layer
        if not self._can_user_edit_plan(plan, request.user):
            return Response(
                {'error': 'You do not have permission to modify this plan'}, 
                status=status.HTTP_403_FORBIDDEN
            )
        
        try:
            plan_activity = plan.activities.get(id=activity_id)
        except PlanActivity.DoesNotExist:
            return Response(
                {'error': 'Activity not found in this plan'}, 
                status=status.HTTP_404_NOT_FOUND
            )
        
        # Update activity
        activity_serializer = PlanActivitySerializer(
            plan_activity, 
            data=request.data, 
            partial=True
        )
        
        if activity_serializer.is_valid():
            activity_serializer.save()
            return Response({
                'message': 'Activity updated successfully',
                'activity': activity_serializer.data
            })
        
        return Response(activity_serializer.errors, status=status.HTTP_400_BAD_REQUEST)
    
    @action(detail=True, methods=['delete'], url_path='activities/(?P<activity_id>[^/.]+)')
    def remove_activity(self, request, pk=None, activity_id=None):
        """Remove activity from plan - uses service layer for permission checking"""
        plan = self.get_object()
        
        # Check permissions using service layer
        if not self._can_user_edit_plan(plan, request.user):
            return Response(
                {'error': 'You do not have permission to modify this plan'}, 
                status=status.HTTP_403_FORBIDDEN
            )
        
        try:
            plan_activity = plan.activities.get(id=activity_id)
        except PlanActivity.DoesNotExist:
            return Response(
                {'error': 'Activity not found in this plan'}, 
                status=status.HTTP_404_NOT_FOUND
            )
        
        # Delete the activity
        activity_title = plan_activity.title
        plan_activity.delete()
        
        return Response({
            'message': f'Activity "{activity_title}" removed from plan'
        })
    
    @action(detail=True, methods=['post'], url_path='activities/(?P<activity_id>[^/.]+)/complete')
    def toggle_activity_completion(self, request, pk=None, activity_id=None):
        """Toggle activity completion status"""
        plan = self.get_object()
        
        # Check if user can modify this plan
        if not self._can_user_edit_plan(plan, request.user):
            return Response(
                {'error': 'You do not have permission to modify this plan'}, 
                status=status.HTTP_403_FORBIDDEN
            )
        
        try:
            plan_activity = plan.activities.get(id=activity_id)
        except PlanActivity.DoesNotExist:
            return Response(
                {'error': 'Activity not found in this plan'}, 
                status=status.HTTP_404_NOT_FOUND
            )
        
        # Toggle completion status
        plan_activity.is_completed = not plan_activity.is_completed
        plan_activity.completed_at = timezone.now() if plan_activity.is_completed else None
        plan_activity.save()
        
        return Response({
            'message': f'Activity marked as {"completed" if plan_activity.is_completed else "incomplete"}',
            'activity': PlanActivitySerializer(plan_activity).data
        })

    @action(detail=False, methods=['get'])
    def joined(self, request):
        """Get plans that the user has joined (excluding their own plans)"""
        user = request.user
        
        # Get group plans where user is a member but not the creator
        group_plans = Plan.objects.filter(
            plan_type='group',
            group__members=user
        ).exclude(creator=user).distinct()
        
        # Apply search filter if provided
        search = request.query_params.get('search', None)
        if search:
            group_plans = group_plans.filter(
                models.Q(title__icontains=search) |
                models.Q(description__icontains=search)
            )
        
        # Serialize and return
        serializer = PlanSummarySerializer(group_plans, many=True, context={'request': request})
        return Response({
            'results': serializer.data,
            'count': group_plans.count()
        })
    
    @action(detail=False, methods=['get'])
    def public(self, request):
        """Get public plans that user can discover and join"""
        user = request.user
        
        # Get public plans excluding user's own plans
        public_plans = Plan.objects.filter(
            is_public=True,
            status__in=['planning', 'active']
        ).exclude(creator=user)
        
        # Exclude plans where user is already a member
        public_plans = public_plans.exclude(
            plan_type='group',
            group__members=user
        )
        
        # Apply search filter if provided
        search = request.query_params.get('search', None)
        if search:
            public_plans = public_plans.filter(
                models.Q(title__icontains=search) |
                models.Q(description__icontains=search)
            )
        
        # Order by created date (newest first)
        public_plans = public_plans.order_by('-created_at')
        
        # Serialize and return
        serializer = PlanSummarySerializer(public_plans, many=True, context={'request': request})
        return Response({
            'results': serializer.data,
            'count': public_plans.count()
        })

    @action(detail=True, methods=['post'])
    def join(self, request, pk=None):
        """Join a public plan"""
        plan = self.get_object()
        user = request.user
        
        # Check if plan is public
        if not plan.is_public:
            return Response(
                {'error': 'This plan is not public'}, 
                status=status.HTTP_403_FORBIDDEN
            )
        
        # Check if user is the creator
        if plan.creator == user:
            return Response(
                {'error': 'You cannot join your own plan'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        # For group plans, add user to the group
        if plan.plan_type == 'group' and plan.group:
            # Check if user is already a member
            if plan.group.members.filter(id=user.id).exists():
                return Response(
                    {'error': 'You are already a member of this plan'}, 
                    status=status.HTTP_400_BAD_REQUEST
                )
            
            # Add user to group
            GroupMembership.objects.create(
                group=plan.group,
                user=user,
                role='member'
            )
            
            return Response({
                'message': f'Successfully joined plan "{plan.title}"',
                'plan': PlanSerializer(plan, context={'request': request}).data
            })
        else:
            return Response(
                {'error': 'Can only join group plans'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        


class FriendRequestView(generics.CreateAPIView):
    """
    Optimized Friend Request creation with enhanced validation
    Uses atomic transactions and proper error handling
    """
    serializer_class = FriendRequestSerializer
    permission_classes = [IsAuthenticated]
    
    def create(self, request):
        """Create friend request with comprehensive validation"""
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        
        friend_id = serializer.validated_data['friend_id']
        
        try:
            friend = User.objects.get(id=friend_id)
        except User.DoesNotExist:
            return Response(
                {'error': 'User not found'}, 
                status=status.HTTP_404_NOT_FOUND
            )
        
        try:
            with transaction.atomic():
                success, message = UserService.send_friend_request(request.user, friend)
                
                if not success:
                    return Response({'error': message}, status=status.HTTP_400_BAD_REQUEST)

                # Send notification asynchronously
                try:
                    NotificationService.notify_friend_request(
                        friend_id, 
                        request.user.get_full_name()
                    )
                except Exception:
                    pass  # Don't fail request if notification fails
                
                friendship = Friendship.objects.between_users(request.user, friend).first()
                return Response({
                    'message': message,
                    'friendship': FriendshipSerializer(friendship, context={'request': request}).data
                }, status=status.HTTP_201_CREATED)
                    
        except ValidationError as e:
            return Response({'error': str(e)}, status=status.HTTP_400_BAD_REQUEST)


class FriendRequestListView(generics.ListAPIView):
    """
    Optimized Friend Request listing with efficient queries
    Uses select_related for performance optimization
    """
    serializer_class = FriendshipSerializer
    permission_classes = [IsAuthenticated]
    
    def get_queryset(self):
        """
        Get pending friend requests with optimized queries
        Uses canonical friendship model methods
        """
        return Friendship.objects.filter(
            friend=self.request.user,
            status=Friendship.PENDING
        ).select_related('user', 'friend').order_by('-created_at')


class FriendRequestActionView(APIView):
    """
    Optimized Friend Request action handling
    Uses atomic transactions and proper validation
    """
    permission_classes = [IsAuthenticated]
    
    def post(self, request, request_id):
        """Handle friend request actions (accept/reject)"""
        action = request.data.get('action')
        allowed_actions = ['accept', 'reject']
        
        if action not in allowed_actions:
            return Response(
                {'error': f'Invalid action. Use one of: {", ".join(allowed_actions)}'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        # Get friendship with optimized query
        friendship = get_object_or_404(
            Friendship.objects.select_related('user', 'friend'),
            id=request_id,
            friend=request.user,
            status=Friendship.PENDING
        )
        
        try:
            with transaction.atomic():
                if action == 'accept':
                    success, message = UserService.accept_friend_request(request.user, friendship.user)
                else:  # action == 'reject'
                    success, message = UserService.reject_friend_request(request.user, friendship.user)

                if not success:
                    return Response({'error': message}, status=status.HTTP_400_BAD_REQUEST)

                if action == 'accept':
                    # Send notification for acceptance
                    try:
                        NotificationService.notify_friend_request_accepted(
                            friendship.user.id, 
                            request.user.get_full_name()
                        )
                    except Exception:
                        pass  # Don't fail action if notification fails
                
                # Refresh friendship state from DB
                friendship.refresh_from_db()
                
                return Response({
                    'message': message,
                    'friendship': FriendshipSerializer(friendship, context={'request': request}).data
                })
                    
        except (ValidationError, PermissionDenied) as e:
            return Response({'error': str(e)}, status=status.HTTP_400_BAD_REQUEST)
                    
        except Exception as e:
            return Response(
                {'error': f'Action failed: {str(e)}'}, 
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


class FriendsListView(generics.ListAPIView):
    serializer_class = UserSummarySerializer
    permission_classes = [IsAuthenticated]
    
    def get_queryset(self):
        return User.objects.friends_of(self.request.user).with_counts()


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
        """Override update to check message ownership and time limit - uses service layer"""
        message = self.get_object()
        
        # Use service layer for edit validation
        success, error_message = chat_service.edit_message(message, request.user, request.data.get('content', ''))
        
        if not success:
            return Response(
                {'error': error_message}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        return super().update(request, *args, **kwargs)
    
    def destroy(self, request, *args, **kwargs):
        """Override destroy to check permissions - uses service layer"""
        message = self.get_object()
        
        # Use service layer for delete validation
        success, error_message = chat_service.delete_message(message, request.user)
        
        if not success:
            return Response(
                {'error': error_message}, 
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
                    models.Q(creator=request.user)
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
        if not (activity.plan.creator == request.user or 
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
        if not (activity.plan.creator == request.user or 
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
                    models.Q(creator=request.user)
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
                        models.Q(creator=request.user)
                    )
                ).get()  # Validate access
                queryset = queryset.filter(plan_id=plan_id)
            except Plan.DoesNotExist:
                return Response(
                    {'error': 'Plan not found or access denied'}, 
                    status=status.HTTP_404_NOT_FOUND
                )
        
        # Limit search results for performance
        activities = queryset.order_by('-created_at')[:50]
        serializer = self.get_serializer(activities, many=True)
        
        return Response({
            'activities': serializer.data,
            'count': len(activities),
            'query': query
        })


# ============================================================================
# Places/Location API Views (Goong Map Integration)
# ============================================================================

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
        
        places = GoongMapService.search_places(
            query=query,
            location=location,
            radius=radius
        )
        
        return Response({'places': places})

class PlaceDetailsView(APIView):
    """Get detailed information about a place"""
    permission_classes = [IsAuthenticated]
    
    def get(self, request, place_id):
        place_details = GoongMapService.get_place_details(place_id)
        
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
        
        places = GoongMapService.nearby_search(
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

        suggestions = GoongMapService.autocomplete(
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
            result = GoongMapService.geocode(address)
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
                result = GoongMapService.reverse_geocode(lat, lng)
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
                success = NotificationService.send_push_notification(
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
            message = ChatService.send_message(
                sender=request.user,
                group=group,
                content=content,
                message_type=message_type
            )
            
            # Send push notification to group members
            NotificationService.notify_new_message(
                group_id=str(group.id),
                sender_name=request.user.username,
                message_preview=content[:100],
                sender_id=str(request.user.id)
            )
            
            serializer = ChatMessageSerializer(message)
            return Response(serializer.data, status=status.HTTP_201_CREATED)
            
        except ValidationError as e:
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
            
            # Use service layer for activity creation
            activity = PlanService.add_activity_with_place(
                plan=plan,
                title=title,
                start_time=start_time,
                end_time=end_time,
                place_id=place_id,
                **extra_fields
            )
            return Response(
                PlanActivitySerializer(activity).data, 
                status=status.HTTP_201_CREATED
            )
            
        except ValueError as e:
            return Response(
                {'error': str(e)}, 
                status=status.HTTP_400_BAD_REQUEST
            )



