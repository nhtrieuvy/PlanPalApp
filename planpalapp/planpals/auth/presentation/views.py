from django.shortcuts import get_object_or_404
from django.contrib.auth import get_user_model
from django.utils import timezone
from django.utils.dateparse import parse_datetime
from django.db import models, transaction
from django.core.exceptions import ValidationError, PermissionDenied
from datetime import datetime
import logging
from rest_framework.exceptions import ValidationError as DRFValidationError

from rest_framework import viewsets, status, generics, mixins
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework.views import APIView
from rest_framework.request import Request

from planpals.auth.infrastructure.models import User, Friendship
from planpals.auth.presentation.serializers import (
    UserSerializer, UserCreateSerializer, UserSummarySerializer,
    FriendshipSerializer, FriendRequestSerializer
)
from planpals.auth.presentation.permissions import (
    IsAuthenticatedAndActive, FriendshipPermission, UserProfilePermission,
    CanNotTargetSelf, CanViewUserProfile, CanManageFriendship
)
from planpals.auth.application.services import UserService
from planpals.auth.infrastructure.oauth2_utils import OAuth2ResponseFormatter
from planpals.shared.paginators import (
    StandardResultsPagination, SearchResultsPagination,
    ActivityCursorPagination
)

# Cross-context imports for serializers used in mixed views
from planpals.groups.presentation.serializers import GroupSerializer, GroupSummarySerializer
from planpals.plans.presentation.serializers import PlanSummarySerializer, PlanActivitySerializer

User = get_user_model()
logger = logging.getLogger(__name__)


class OAuth2LogoutView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request: Request) -> Response:
        user = request.user
        token_string = getattr(request.auth, 'token', None) if hasattr(request.auth, 'token') else request.auth
        
        try:
            success, message, revoked = UserService.logout_user(user, token_string)
            
            if success:
                return Response({
                    'message': message,
                    'timestamp': timezone.now().isoformat(),
                    'token_revoked': revoked
                })
            else:
                data, code = OAuth2ResponseFormatter.error_response(
                    'server_error', message, 500
                )
                return Response(data, status=code)
                
        except Exception as e:
            data, code = OAuth2ResponseFormatter.error_response(
                'server_error', f'Logout failed: {e}', 500
            )
            return Response(data, status=code)


class UserViewSet(viewsets.GenericViewSet,
                  mixins.CreateModelMixin,
                  mixins.RetrieveModelMixin,
                  mixins.UpdateModelMixin):

    serializer_class = UserSerializer
    pagination_class = StandardResultsPagination
    
    def get_permissions(self):
        if self.action == 'create':
            permission_classes = [AllowAny]
        elif self.action in ['update', 'partial_update', 'destroy']:
            permission_classes = [IsAuthenticated, UserProfilePermission]
        elif self.action == 'retrieve':
            permission_classes = [IsAuthenticated, CanViewUserProfile]
        elif self.action in ['unfriend', 'block', 'unblock']:
            permission_classes = [IsAuthenticated, CanManageFriendship]
        else:
            permission_classes = [IsAuthenticatedAndActive]
        return [permission() for permission in permission_classes]
    
    def get_queryset(self):
        if not self.request.user.is_authenticated:
            return User.objects.none()
        
        return User.objects.filter(
            id=self.request.user.id
        ).with_counts()
    
    def get_serializer_class(self):
        if self.action == 'create':
            return UserCreateSerializer
        if self.action == "list":
            return UserSummarySerializer
        return UserSerializer

    @action(detail=False, methods=['post'], permission_classes=[IsAuthenticated])
    def register_device_token(self, request):
        """Register or update the current user's FCM device token

        Expected payload: { "fcm_token": "<token>", "platform": "android" }
        """
        from planpals.auth.presentation.serializers import FCMTokenSerializer
        from planpals.auth.application.commands import UpdateFCMTokenCommand
        from planpals.auth.application import factories as auth_factories

        serializer = FCMTokenSerializer(data=request.data)
        if not serializer.is_valid():
            return Response({'errors': serializer.errors}, status=status.HTTP_400_BAD_REQUEST)

        fcm_token = serializer.validated_data.get('fcm_token')
        try:
            cmd = UpdateFCMTokenCommand(user_id=request.user.id, fcm_token=fcm_token)
            handler = auth_factories.get_update_fcm_token_handler()
            handler.handle(cmd)
            return Response({'message': 'FCM token registered successfully'})
        except Exception as e:
            logger.error(f"Failed to register fcm token for user {request.user.id}: {e}")
            return Response({'error': 'Failed to register token'}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
    
    def list(self, request):
        user = User.objects.with_counts().get(id=request.user.id)
        user_serializer = self.get_serializer(user)
        return Response({
            'user': user_serializer.data,
            'message': 'User profile retrieved successfully'
        })
    
    @action(detail=False, methods=['get'], permission_classes=[IsAuthenticated])
    def search(self, request):
        query = request.query_params.get('q')
        is_valid, message = UserService.validate_search_query(query)
        
        if not is_valid:
            return Response(
                {'error': message}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        users_queryset = UserService.search_users(query, request.user)
        
        blocked_by_user_ids = Friendship.objects.filter(
            models.Q(user_a=request.user) | models.Q(user_b=request.user),
            status=Friendship.BLOCKED
        ).exclude(
            initiator=request.user
        ).values_list(
            models.Case(
                models.When(user_a=request.user, then='user_b'),
                default='user_a'
            ), 
            flat=True
        )
        users_queryset = users_queryset.exclude(id__in=blocked_by_user_ids)
        
        paginator = SearchResultsPagination()
        paginator.set_search_query(query)
        page = paginator.paginate_queryset(users_queryset, request)
        
        if page is not None:
            serializer = UserSummarySerializer(page, many=True, context={'request': request})
            return paginator.get_paginated_response(serializer.data)
        
        serializer = UserSummarySerializer(users_queryset, many=True, context={'request': request})
        return Response({
            'users': serializer.data,
            'count': len(serializer.data),
            'query': query
        })
    
    @action(detail=False, methods=['get'])
    def profile(self, request):
        user = UserService.get_user_with_counts(request.user.id)
        serializer = self.get_serializer(user) 
        return Response(serializer.data)
    
    @action(detail=False, methods=['put', 'patch'])
    def update_profile(self, request):
        user, updated = UserService.update_user_profile(request.user, request.data)
        
        if updated:
            serializer = self.get_serializer(user)
            return Response(serializer.data)
        else:
            return Response({'error': 'Update failed'}, status=status.HTTP_400_BAD_REQUEST)
    
    @action(detail=False, methods=['get'])
    def my_plans(self, request):
        plan_type = request.query_params.get('type', 'all')
        plans = UserService.get_user_plans(request.user, plan_type)
        
        page = self.paginate_queryset(plans)
        if page is not None:
            serializer = PlanSummarySerializer(page, many=True, context={'request': request})
            return self.get_paginated_response(serializer.data)
        
        serializer = PlanSummarySerializer(plans, many=True, context={'request': request})
        return Response(serializer.data)
    
    @action(detail=False, methods=['get'])
    def my_groups(self, request):
        groups = UserService.get_user_groups(request.user)
        
        page = self.paginate_queryset(groups)
        if page is not None:
            serializer = GroupSummarySerializer(page, many=True, context={'request': request})
            return self.get_paginated_response(serializer.data)
        
        serializer = GroupSummarySerializer(groups, many=True, context={'request': request})
        return Response(serializer.data)
    
    @action(detail=False, methods=['get'])
    def my_activities(self, request):

        activities_queryset = UserService.get_user_activities(request.user)
        
        paginator = ActivityCursorPagination()
        page = paginator.paginate_queryset(activities_queryset, request)
        
        if page is not None:
            serializer = PlanActivitySerializer(page, many=True, context={'request': request})
            return paginator.get_paginated_response(serializer.data)
        
        serializer = PlanActivitySerializer(activities_queryset, many=True, context={'request': request})
        return Response(serializer.data)
        
    
    @action(detail=False, methods=['post'])
    def set_online_status(self, request):
        is_online = request.data.get('is_online', True)
        success = UserService.set_user_online_status(request.user, is_online)
        
        if success:
            return Response({
                'is_online': request.user.is_online,
                'last_seen': request.user.last_seen
            })
        else:
            return Response({'error': 'Failed to update status'}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
    
    @action(detail=False, methods=['get'])
    def friendship_stats(self, request):
        stats = UserService.get_friendship_stats(request.user)
        return Response(stats)
    
    @action(detail=False, methods=['get'])
    def recent_conversations(self, request):
        conversations = UserService.get_recent_conversations(request.user)
        serializer = GroupSerializer(conversations, many=True, context={'request': request})
        
        return Response({
            'conversations': serializer.data,
            'timestamp': timezone.now().isoformat()
        })
    
    @action(detail=False, methods=['get'])
    def unread_count(self, request):
        count = UserService.get_unread_count(request.user)
        return Response({
            'unread_count': count,
            'timestamp': timezone.now().isoformat()
        })
        
    
    def retrieve(self, request, pk=None):
        user = get_object_or_404(User, id=pk)
        
        self.check_object_permissions(request, user)
        
        serializer = UserSummarySerializer(user, context={'request': request})
        return Response(serializer.data)
    
    @action(detail=True, methods=['get'])
    def friendship_status(self, request, pk=None):
        target_user = get_object_or_404(User, id=pk)
        current_user = request.user
        
        status_info = UserService.get_friendship_status(current_user, target_user)
        
        return Response(status_info)
    
    @action(detail=True, methods=['delete'])
    def unfriend(self, request, pk=None):        
        target_user = get_object_or_404(User, id=pk)
        current_user = request.user
        
        success, message = UserService.unfriend_user(current_user, target_user)
        
        if not success:
            return Response({'error': message}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        return Response({'message': message})
    
    @action(detail=True, methods=['post'])
    def block(self, request, pk=None):
        target_user = get_object_or_404(User, id=pk)
        current_user = request.user
        
        success, message = UserService.block_user(current_user, target_user)
        
        if not success:
            return Response({'error': message}, 
                          status=status.HTTP_400_BAD_REQUEST)

        return Response({'message': message})
    
    @action(detail=True, methods=['delete'])
    def unblock(self, request, pk=None):
        target_user = get_object_or_404(User, id=pk)
        current_user = request.user
        
        success, message = UserService.unblock_user(current_user, target_user)
        
        if not success:
            return Response({'error': message}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        return Response({'message': message})


class FriendRequestView(generics.CreateAPIView):
    serializer_class = FriendRequestSerializer
    permission_classes = [IsAuthenticated]
    
    def create(self, request):
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
            success, message = UserService.send_friend_request(request.user, friend)
            
            if not success:
                return Response({'error': message}, status=status.HTTP_400_BAD_REQUEST)
            
            friendship = Friendship.objects.between_users(request.user, friend).first()
            return Response({
                'message': message,
                'friendship': FriendshipSerializer(friendship, context={'request': request}).data
            }, status=status.HTTP_201_CREATED)
                
        except ValidationError as e:
            return Response({'error': str(e)}, status=status.HTTP_400_BAD_REQUEST)


class FriendRequestListView(generics.ListAPIView):
    serializer_class = FriendshipSerializer
    permission_classes = [IsAuthenticated]
    pagination_class = StandardResultsPagination
    def get_queryset(self):
        return Friendship.objects.filter(
            models.Q(user_a=self.request.user) | models.Q(user_b=self.request.user),
            status=Friendship.PENDING
        ).exclude(
            initiator=self.request.user
        ).select_related('user_a', 'user_b', 'initiator').order_by('-created_at')
    
    def get_serializer_context(self):
        context = super().get_serializer_context()
        context['list_friend_requests'] = True
        return context


class FriendRequestActionView(APIView):
    permission_classes = [IsAuthenticated]
    
    def post(self, request, request_id):
        action = request.data.get('action')
        allowed_actions = ['accept', 'reject']
        
        if action not in allowed_actions:
            return Response(
                {'error': f'Invalid action. Use one of: {", ".join(allowed_actions)}'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        friendship = get_object_or_404(
            Friendship.objects.filter(
                id=request_id,
                status=Friendship.PENDING
            ).filter(
                models.Q(user_a=request.user) | models.Q(user_b=request.user)
            ).exclude(
                initiator=request.user
            ).select_related('user_a', 'user_b', 'initiator')
        )
        
        initiator = friendship.initiator
        
        try:
            with transaction.atomic():
                if action == 'accept':
                    success, message = UserService.accept_friend_request(request.user, initiator)
                else:
                    success, message = UserService.reject_friend_request(request.user, initiator)

                if not success:
                    return Response({'error': message}, status=status.HTTP_400_BAD_REQUEST)
                
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
