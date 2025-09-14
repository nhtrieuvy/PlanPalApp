from django.shortcuts import get_object_or_404
from django.contrib.auth import get_user_model
from django.utils import timezone
from django.db import models, transaction
from django.core.exceptions import ValidationError, PermissionDenied
from datetime import datetime

from rest_framework import viewsets, status, generics, mixins
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework.views import APIView
from rest_framework.request import Request

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
from .paginators import (
    StandardResultsPagination, SearchResultsPagination, 
    ChatMessageCursorPagination, ActivityCursorPagination,
    MobilePagination, get_paginator_class
)

User = get_user_model()


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
        else:
            permission_classes = [IsAuthenticatedAndActive]
        return [permission() for permission in permission_classes]
    
    def get_queryset(self):
        if not self.request.user.is_authenticated:
            return User.objects.none()
        
        return User.objects.filter(
            id=self.request.user.id
        ).with_counts()
    
    def get_serializer_class(self) -> type:
        if self.action == 'create':
            return UserCreateSerializer
        if self.action == "list":
            return UserSummarySerializer
        return UserSerializer
    
    def list(self, request: Request) -> Response:
        user = User.objects.with_counts().get(id=request.user.id)
        user_serializer = self.get_serializer(user)
        return Response({
            'user': user_serializer.data,
            'message': 'User profile retrieved successfully'
        })
    
    @action(detail=False, methods=['get'])
    def search(self, request):
        query = request.query_params.get('q')
        if not query or len(query) < 2:
            return Response(
                {'error': 'Search query (q) parameter required (min 2 characters)'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        users_queryset = UserService.search_users(query, request.user)
        
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
    def profile(self, request: Request) -> Response:
        user = UserService.get_user_with_counts(request.user.id)
        serializer = self.get_serializer(user) 
        return Response(serializer.data)
    
    @action(detail=False, methods=['put', 'patch'])
    def update_profile(self, request: Request) -> Response:
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
        
        status_info = current_user.get_friendship_status(target_user)
        
        return Response(status_info)
    
    @action(detail=True, methods=['delete'])
    def unfriend(self, request, pk=None):        
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
    
    @action(detail=True, methods=['post'])
    def block(self, request, pk=None):
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
    
    @action(detail=True, methods=['delete'])
    def unblock(self, request, pk=None):
        target_user = get_object_or_404(User, id=pk)
        current_user = request.user
        
        if current_user == target_user:
            return Response({'error': 'Cannot unblock yourself'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        success, message = UserService.unblock_user(current_user, target_user)
        
        if not success:
            return Response({'error': message}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        return Response({'message': message})
    
    def _can_view_profile(self, current_user, target_user):
        if current_user == target_user:
            return True
        
        if getattr(target_user, 'is_profile_public', True):
            return True
        
        return Friendship.are_friends(current_user, target_user)
        

class GroupViewSet(viewsets.GenericViewSet,
                   mixins.CreateModelMixin,
                   mixins.RetrieveModelMixin,
                   mixins.UpdateModelMixin,
                   mixins.DestroyModelMixin):
    serializer_class = GroupSerializer
    permission_classes = [IsAuthenticated, GroupPermission]
    pagination_class = StandardResultsPagination
    
    def get_serializer_class(self):
        if self.action == 'create':
            return GroupCreateSerializer
        elif self.action == 'list':
            return GroupSummarySerializer
        return self.serializer_class

    def get_queryset(self):
        return Group.objects.filter(
            members=self.request.user
        ).select_related(
            'admin'
        ).prefetch_related(
            'members',
            'memberships__user'
        ).with_full_stats()
    
    def list(self, request):
        queryset = self.get_queryset().order_by('-created_at')
        
        page = self.paginate_queryset(queryset)
        if page is not None:
            serializer = self.get_serializer(page, many=True)
            return self.get_paginated_response(serializer.data)
        
        serializer = self.get_serializer(queryset, many=True)
        return Response(serializer.data)
    
    def perform_create(self, serializer):

        with transaction.atomic():
            group = serializer.save(admin=self.request.user)
        return group
    
    @action(detail=False, methods=['post'])
    def join(self, request):
        group_id = request.data.get('group_id')
        invite_code = request.data.get('invite_code')
        
        if not group_id and not invite_code:
            return Response(
                {'error': 'group_id or invite_code required'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        try:
            success, message, group = GroupService.join_group(
                user=request.user,
                group_id=group_id,
                invite_code=invite_code
            )
            
            if not success:
                return Response({'error': message}, status=status.HTTP_400_BAD_REQUEST)
            
            return Response({
                'message': message,
                'group': GroupSummarySerializer(group, context={'request': request}).data
            })
            
        except Exception as e:
            return Response(
                {'error': str(e)}, 
                status=status.HTTP_404_NOT_FOUND
            )
    
    @action(detail=False, methods=['get'])
    def my_groups(self, request):
        queryset = self.get_queryset()
        
        page = self.paginate_queryset(queryset)
        if page is not None:
            serializer = self.get_serializer(page, many=True)
            return self.get_paginated_response(serializer.data)
        
        serializer = self.get_serializer(queryset, many=True)
        return Response(serializer.data)
    
    @action(detail=False, methods=['get'])
    def created_by_me(self, request):
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
        query = request.query_params.get('q')
        if not query:
            return Response(
                {'error': 'q parameter required'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        groups_queryset = GroupService.search_user_groups(request.user, query)
        
        paginator = SearchResultsPagination()
        paginator.set_search_query(query)
        page = paginator.paginate_queryset(groups_queryset, request)
        
        if page is not None:
            serializer = self.get_serializer(page, many=True)
            return paginator.get_paginated_response(serializer.data)
        
        serializer = self.get_serializer(groups_queryset, many=True)
        return Response({
            'groups': serializer.data,
            'query': query,
            'count': len(serializer.data)
        })
    
    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, IsGroupAdmin])
    def add_member(self, request, pk=None):
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
    
    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, IsGroupMember])
    def send_message(self, request, pk=None):
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
    
    @action(detail=True, methods=['get'], permission_classes=[IsAuthenticated, IsGroupMember])
    def recent_messages(self, request, pk=None):
        group = self.get_object()
        limit = int(request.query_params.get('limit', 50))
           
        serializer = ChatMessageSerializer(group.get_recent_messages(limit), many=True, context={'request': request})
        
        return Response({
            'messages': serializer.data,
            'group_id': str(group.id),
            'count': len(serializer.data)
        })
        group = self.get_object()
        limit = int(request.query_params.get('limit', 50))
        messages = group.get_recent_messages(limit=limit)
        serializer = ChatMessageSerializer(messages, many=True)
        return Response(serializer.data)
    
    @action(detail=True, methods=['get'], permission_classes=[IsAuthenticated, IsGroupMember])
    def unread_count(self, request, pk=None):
        group = self.get_object()
        count = group.get_unread_messages_count(request.user)
        return Response({'unread_count': count})
    
    #API lấy danh sách quản trị viên của nhóm
    @action(detail=True, methods=['get'], permission_classes=[IsAuthenticated, IsGroupMember])
    def admins(self, request, pk=None):
        group = self.get_object()
        admins = group.get_admins()
        serializer = UserSerializer(admins, many=True)
        return Response(serializer.data)

    #API lấy danh sách kế hoạch của nhóm
    @action(detail=True, methods=['get'], permission_classes=[IsAuthenticated, IsGroupMember])
    def plans(self, request, pk=None):
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
    serializer_class = PlanSerializer
    permission_classes = [IsAuthenticated, PlanPermission]
    pagination_class = StandardResultsPagination
    
    def get_serializer_class(self):
        if self.action == 'create':
            return PlanCreateSerializer
        elif self.action == 'list':
            return PlanSummarySerializer
        return self.serializer_class
    
    def get_queryset(self):
        return Plan.objects.filter(
            models.Q(group__members=self.request.user) |
            models.Q(creator=self.request.user)
        ).select_related(
            'creator', 'group'
        ).prefetch_related(
            'group__members',
            'activities'
        ).with_stats().distinct().order_by('-created_at')
    
    def perform_create(self, serializer):
        data = serializer.validated_data
        
        # Get group from validated data (already resolved by serializer)
        group = data.get('group')
        
        # Create plan using service layer within transaction
        with transaction.atomic():
            plan = PlanService.create_plan(
                creator=self.request.user,
                title=data['title'],
                description=data.get('description', ''),
                plan_type=data.get('plan_type', 'personal'),
                group=group,
                start_date=data.get('start_date'),
                end_date=data.get('end_date'),
                budget=data.get('budget'),
                is_public=data.get('is_public', False)
            )
        
        serializer.instance = plan
    
    
    @action(detail=False, methods=['get'])
    def my_plans(self, request):
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
    
    @action(detail=True, methods=['get'])
    def activities_by_date(self, request, pk=None):
        plan = self.get_object()
        
        activities_by_date = plan.activities_by_date  # Using property
        
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
        plan = self.get_object()
        
        try:
            activity = PlanService.add_activity_to_plan(plan, request.user, request.data)
            return Response(
                PlanActivitySerializer(activity).data, 
                status=status.HTTP_201_CREATED
            )
        except ValidationError as e:
            return Response({'error': str(e)}, status=status.HTTP_400_BAD_REQUEST)
    
    #API lấy tóm tắt kế hoạch
    @action(detail=True, methods=['get'])
    def summary(self, request, pk=None):
        """Get plan summary - delegate to service"""
        plan = self.get_object()
        
        summary = PlanService.get_plan_statistics(plan)
        return Response(summary)
    
    @action(detail=True, methods=['get'])
    def schedule(self, request, pk=None):
        plan = self.get_object()
        
        schedule_data = PlanService.get_plan_schedule(plan, request.user)
        return Response(schedule_data)
    
    @action(detail=True, methods=['post'])
    def create_activity(self, request, pk=None):
        plan = self.get_object()
        
        try:
            activity = PlanService.add_activity_to_plan(plan, request.user, request.data)
            return Response(
                PlanActivitySerializer(activity, context={'request': request}).data,
                status=status.HTTP_201_CREATED
            )
        except ValidationError as e:
            return Response({'error': str(e)}, status=status.HTTP_400_BAD_REQUEST)
    
    
    @action(detail=True, methods=['put', 'patch'], url_path='activities/(?P<activity_id>[^/.]+)')
    def update_activity(self, request, pk=None, activity_id=None):
        plan = self.get_object()
        
        
        try:
            plan_activity = plan.activities.get(id=activity_id)
        except PlanActivity.DoesNotExist:
            return Response(
                {'error': 'Activity not found in this plan'}, 
                status=status.HTTP_404_NOT_FOUND
            )
        
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
        plan = self.get_object()
       
        try:
            plan_activity = plan.activities.get(id=activity_id)
        except PlanActivity.DoesNotExist:
            return Response(
                {'error': 'Activity not found in this plan'}, 
                status=status.HTTP_404_NOT_FOUND
            )
        
        activity_title = plan_activity.title
        plan_activity.delete()
        
        return Response({
            'message': f'Activity "{activity_title}" removed from plan'
        })
    
    @action(detail=True, methods=['post'], url_path='activities/(?P<activity_id>[^/.]+)/complete')
    def toggle_activity_completion(self, request, pk=None, activity_id=None):
        plan = self.get_object()
        
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
        
        plan_activity.is_completed = not plan_activity.is_completed
        plan_activity.completed_at = timezone.now() if plan_activity.is_completed else None
        plan_activity.save()
        
        return Response({
            'message': f'Activity marked as {"completed" if plan_activity.is_completed else "incomplete"}',
            'activity': PlanActivitySerializer(plan_activity).data
        })

    @action(detail=False, methods=['get'])
    def joined(self, request):
        user = request.user
        
        group_plans = Plan.objects.filter(
            plan_type='group',
            group__members=user
        ).exclude(creator=user).distinct()
        
        search = request.query_params.get('search', None)
        if search:
            group_plans = group_plans.filter(
                models.Q(title__icontains=search) |
                models.Q(description__icontains=search)
            )
        
        serializer = PlanSummarySerializer(group_plans, many=True, context={'request': request})
        return Response({
            'results': serializer.data,
            'count': group_plans.count()
        })
    
    @action(detail=False, methods=['get'])
    def public(self, request):
        user = request.user
        
        public_plans = Plan.objects.filter(
            is_public=True,
            status__in=['upcoming', 'ongoing']
        ).exclude(creator=user)
        
        public_plans = public_plans.exclude(
            plan_type='group',
            group__members=user
        )
        
        search = request.query_params.get('search', None)
        if search:
            public_plans = public_plans.filter(
                models.Q(title__icontains=search) |
                models.Q(description__icontains=search)
            )
        
        public_plans = public_plans.order_by('-created_at')
        
        serializer = PlanSummarySerializer(public_plans, many=True, context={'request': request})
        return Response({
            'results': serializer.data,
            'count': public_plans.count()
        })

    @action(detail=True, methods=['post'])
    def join(self, request, pk=None):
        plan = self.get_object()
        user = request.user
        
        # Check if plan is public
        if not plan.is_public:
            return Response(
                {'error': 'This plan is not public'}, 
                status=status.HTTP_403_FORBIDDEN
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

            # Send notification via service
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
    serializer_class = FriendshipSerializer
    permission_classes = [IsAuthenticated]
    
    def get_queryset(self):
        return Friendship.objects.filter(
            friend=self.request.user,
            status=Friendship.PENDING
        ).select_related('user', 'friend').order_by('-created_at')


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
    serializer_class = ChatMessageSerializer
    permission_classes = [IsAuthenticated, ChatMessagePermission]
    pagination_class = ChatMessageCursorPagination  # Use cursor pagination for messages
    
    def get_queryset(self):
        return ChatMessage.objects.filter(
            group__members=self.request.user
        ).select_related('sender', 'group')
    
    
    
    def create(self, request, *args, **kwargs):
        group_id = request.data.get('group')
        content = request.data.get('content', '')
        message_type = request.data.get('message_type', 'text')
        
        if not group_id:
            return Response(
                {'error': 'group field is required'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        try:
            group = Group.objects.get(id=group_id, members=request.user)
            message = ChatService.send_message(
                sender=request.user,
                group=group,
                content=content,
                message_type=message_type
            )
            
            serializer = self.get_serializer(message)
            return Response(serializer.data, status=status.HTTP_201_CREATED)
            
        except Group.DoesNotExist:
            return Response(
                {'error': 'Cannot send message to this group'}, 
                status=status.HTTP_403_FORBIDDEN
            )
        except ValidationError as e:
            return Response({'error': str(e)}, status=status.HTTP_400_BAD_REQUEST)
    
    def perform_create(self, serializer):
        serializer.save(sender=self.request.user)
    
    def update(self, request, *args, **kwargs):
        message = self.get_object()
        
        success, error_message = chat_service.edit_message(message, request.user, request.data.get('content', ''))
        
        if not success:
            return Response(
                {'error': error_message}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        return super().update(request, *args, **kwargs)
    
    def destroy(self, request, *args, **kwargs):
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
        group_id = request.query_params.get('group_id')
        limit = min(int(request.query_params.get('limit', 50)), 100)
        before_id = request.query_params.get('before_id')
        
        if not group_id:
            return Response(
                {'error': 'group_id parameter required'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        try:
            messages_data = ChatService.get_group_messages(
                user=request.user,
                group_id=group_id,
                limit=limit,
                before_id=before_id
            )
            
            serializer = self.get_serializer(messages_data['messages'], many=True)
            
            return Response({
                'messages': serializer.data,
                'has_more': messages_data['has_more'],
                'next_cursor': messages_data['next_cursor'],
                'count': len(serializer.data)
            })
            
        except ValidationError as e:
            return Response({'error': str(e)}, status=status.HTTP_400_BAD_REQUEST)
    
    #API tìm kiếm tin nhắn
    @action(detail=False, methods=['get'])
    def search(self, request):
        query = request.query_params.get('q')
        group_id = request.query_params.get('group_id')
        
        if not query:
            return Response(
                {'error': 'Search query (q) parameter required'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        queryset = ChatMessage.objects.filter(
            group__members=request.user,
            content__icontains=query
        ).select_related('sender', 'group').order_by('-created_at')
        
        if group_id:
            try:
                Group.objects.get(id=group_id, members=request.user)  # Validate access
                queryset = queryset.filter(group_id=group_id)
            except Group.DoesNotExist:
                return Response(
                    {'error': 'Group not found or access denied'}, 
                    status=status.HTTP_404_NOT_FOUND
                )
        
        # Apply pagination to messages
        page = self.paginate_queryset(queryset)
        if page is not None:
            serializer = self.get_serializer(page, many=True)
            return self.get_paginated_response(serializer.data)
        
        serializer = self.get_serializer(queryset, many=True)
        
        return Response({
            'messages': serializer.data,
            'count': len(messages),
            'query': query
        })
    
    #API lấy tin nhắn gần đây từ tất cả nhóm
    @action(detail=False, methods=['get'])
    def recent(self, request):
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
    serializer_class = PlanActivitySerializer
    permission_classes = [IsAuthenticated, PlanActivityPermission]
    pagination_class = ActivityCursorPagination  # Use cursor pagination for activities
    
    def get_queryset(self):
        return PlanActivity.objects.filter(
            plan__group__members=self.request.user
        ).select_related('plan', 'plan__group')
    
    
    def create(self, request, *args, **kwargs):
        plan_id = request.data.get('plan')
        
        if not plan_id:
            return Response(
                {'error': 'plan field is required'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
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
        plan_id = request.query_params.get('plan_id')
        
        if not plan_id:
            return Response(
                {'error': 'plan_id parameter required'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
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
        
        # Apply pagination to activities
        page = self.paginate_queryset(queryset.order_by('-created_at'))
        if page is not None:
            serializer = self.get_serializer(page, many=True)
            return self.get_paginated_response(serializer.data)
        
        serializer = self.get_serializer(queryset.order_by('-created_at'), many=True)
        
        return Response({
            'activities': serializer.data,
            'count': len(activities),
            'query': query
        })


class PlacesSearchView(APIView):
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


class EnhancedGroupViewSet(GroupViewSet):    
    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, IsGroupMember])
    def send_message_with_notification(self, request, pk=None):
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
    @action(detail=True, methods=['post'])
    def add_activity_with_place(self, request, pk=None):
        plan = self.get_object()
        
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