from django.shortcuts import get_object_or_404
from django.contrib.auth import get_user_model
from django.utils import timezone
from django.db import models, transaction
from django.core.exceptions import ValidationError, PermissionDenied
from rest_framework.exceptions import ValidationError as DRFValidationError
from datetime import datetime
import logging

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
    ChatMessageSerializer, PlanActivitySerializer, PlanActivitySummarySerializer,
    PlanActivityCreateSerializer, ConversationSerializer
)
from .permissions import (
    IsAuthenticatedAndActive, PlanPermission, GroupPermission,
    ChatMessagePermission, FriendshipPermission, UserProfilePermission,
    IsGroupMember, IsGroupAdmin, PlanActivityPermission, ConversationPermission,
    CanNotTargetSelf, CanViewUserProfile, CanManageFriendship, 
    CanEditMyPlans, IsOwnerOrGroupAdmin, CanJoinPlan, CanAccessPlan, CanModifyPlan
)

from .services import UserService, GroupService, PlanService, ChatService, ConversationService
from .integrations import GoongMapService, NotificationService
from .oauth2_utils import OAuth2ResponseFormatter
from .paginators import (
    StandardResultsPagination, SearchResultsPagination, 
    ChatMessageCursorPagination, ActivityCursorPagination,
    MobilePagination, get_paginator_class
)

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
        
        success, message = GroupService.add_member_by_id(group, user_id, added_by=request.user)
        
        if not success:
            status_code = status.HTTP_404_NOT_FOUND if "not found" in message else status.HTTP_400_BAD_REQUEST
            return Response({'error': message}, status=status_code)
        
        return Response({'message': message})
    
    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, IsGroupMember])
    def send_message(self, request, pk=None):
        """
        Send message to group.
        
        Same interface as ConversationViewSet.send_message for consistency.
        """
        group = self.get_object()
        
        # Check group membership
        if not group.members.filter(id=request.user.id).exists():
            return Response(
                {'error': 'You are not a member of this group'}, 
                status=status.HTTP_403_FORBIDDEN
            )
        
        # Use DRF serializer for validation
        serializer = ChatMessageSerializer(data=request.data, context={'request': request})
        
        if not serializer.is_valid():
            return Response(
                {'errors': serializer.errors}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        try:
            # Use ChatService which delegates to ConversationService.create_message
            message = ChatService.send_message(
                sender=request.user,
                group=group,
                **serializer.validated_data
            )
            
            # Return serialized response
            response_serializer = ChatMessageSerializer(message, context={'request': request})
            return Response(response_serializer.data, status=status.HTTP_201_CREATED)
            
        except PermissionDenied as e:
            return Response(
                {'error': str(e)}, 
                status=status.HTTP_403_FORBIDDEN
            )
        except ValidationError as e:
            return Response(
                {'error': str(e)}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        except Exception as e:
            logger.error(f"Unexpected error in group send_message: {e}")
            return Response(
                {'error': 'Internal server error'}, 
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
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
        
        plans_data = GroupService.get_group_plans(group, request.user)
        
        serializer = PlanSummarySerializer(plans_data['plans'], many=True, context={'request': request})
        
        return Response({
            'plans': serializer.data,
            'group_id': plans_data['group_id'],
            'group_name': plans_data['group_name'],
            'count': plans_data['count'],
            'can_create_plan': plans_data['can_create_plan']
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
        
        group = data.get('group')
        
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
    
    
    @action(detail=False, methods=['get'], permission_classes=[IsAuthenticated, CanEditMyPlans])
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
    
    @action(detail=True, methods=['get'], permission_classes=[IsAuthenticated, CanAccessPlan])
    def activities_by_date(self, request, pk=None):
        plan = self.get_object()
        
        activities_by_date = plan.activities_by_date
        
        result = {}
        for date, activities in activities_by_date.items():
            result[date.isoformat()] = PlanActivitySerializer(
                activities, many=True, context={'request': request}
            ).data
        
        return Response({
            'activities_by_date': result,
            'plan_id': str(plan.id),
            'total_activities': plan.activities_count
        })
        
    
    #API lấy người tham gia kế hoạch
    @action(detail=True, methods=['get'], permission_classes=[IsAuthenticated, CanAccessPlan])
    def collaborators(self, request, pk=None):
        """Get plan collaborators - OPTIMIZED using property"""
        plan = self.get_object()
        collaborators = plan.collaborators
        
        serializer = UserSerializer(collaborators, many=True, context={'request': request})
        
        return Response({
            'collaborators': serializer.data,
            'count': len(collaborators),
            'plan_type': plan.plan_type
        })
        
    
    #API thêm hoạt động vào kế hoạch
    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, CanModifyPlan])
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
    @action(detail=True, methods=['get'], permission_classes=[IsAuthenticated, CanAccessPlan])
    def summary(self, request, pk=None):
        """Get plan summary - delegate to service"""
        plan = self.get_object()
        
        summary = PlanService.get_plan_statistics(plan)
        return Response(summary)
    
    @action(detail=True, methods=['get'], permission_classes=[IsAuthenticated, CanAccessPlan])
    def schedule(self, request, pk=None):
        plan = self.get_object()
        
        schedule_data = PlanService.get_plan_schedule(plan, request.user)
        return Response(schedule_data)
    
    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, CanModifyPlan])
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
    
    
    @action(detail=True, methods=['put', 'patch'], url_path='activities/(?P<activity_id>[^/.]+)', 
            permission_classes=[IsAuthenticated, CanModifyPlan])
    def update_activity(self, request, pk=None, activity_id=None):
        plan = self.get_object()
        
        success, message, activity = PlanService.update_activity(plan, activity_id, request.user, request.data)
        
        if not success:
            status_code = status.HTTP_403_FORBIDDEN if "permission" in message else status.HTTP_404_NOT_FOUND
            return Response({'error': message}, status=status_code)
        
        return Response({
            'message': message,
            'activity': PlanActivitySerializer(activity).data
        })
    
    @action(detail=True, methods=['delete'], url_path='activities/(?P<activity_id>[^/.]+)',
            permission_classes=[IsAuthenticated, CanModifyPlan])
    def remove_activity(self, request, pk=None, activity_id=None):
        plan = self.get_object()
        
        success, message = PlanService.remove_activity(plan, activity_id, request.user)
        
        if not success:
            status_code = status.HTTP_403_FORBIDDEN if "permission" in message else status.HTTP_404_NOT_FOUND
            return Response({'error': message}, status=status_code)
        
        return Response({'message': message})
    
    @action(detail=True, methods=['post'], url_path='activities/(?P<activity_id>[^/.]+)/complete',
            permission_classes=[IsAuthenticated, CanModifyPlan])
    def toggle_activity_completion(self, request, pk=None, activity_id=None):
        plan = self.get_object()
        
        success, message, activity = PlanService.toggle_activity_completion(plan, activity_id, request.user)
        
        if not success:
            status_code = status.HTTP_403_FORBIDDEN if "permission" in message else status.HTTP_404_NOT_FOUND
            return Response({'error': message}, status=status_code)
        
        return Response({
            'message': message,
            'activity': PlanActivitySerializer(activity).data
        })

    @action(detail=False, methods=['get'])
    def joined(self, request):
        search = request.query_params.get('search', None)
        group_plans = PlanService.get_joined_plans(request.user, search)
        
        serializer = PlanSummarySerializer(group_plans, many=True, context={'request': request})
        return Response({
            'results': serializer.data,
            'count': group_plans.count()
        })
    
    @action(detail=False, methods=['get'])
    def public(self, request):
        search = request.query_params.get('search', None)
        public_plans = PlanService.get_public_plans(request.user, search)
        
        serializer = PlanSummarySerializer(public_plans, many=True, context={'request': request})
        return Response({
            'results': serializer.data,
            'count': public_plans.count()
        })


    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, CanJoinPlan])
    def join(self, request, pk=None):
        plan = self.get_object()
        user = request.user
        
        success, message = PlanService.join_plan(plan, user)
        
        if not success:
            return Response(
                {'error': message}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        return Response({
            'message': message,
            'plan': PlanSerializer(plan, context={'request': request}).data
        })
        


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

            try:
                NotificationService.notify_friend_request(
                    friend_id, 
                    request.user.get_full_name()
                )
            except Exception:
                pass
            
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

                if action == 'accept':
                    try:
                        NotificationService.notify_friend_request_accepted(
                            initiator.id, 
                            request.user.get_full_name()
                        )
                    except Exception:
                        pass
                
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
    pagination_class = ChatMessageCursorPagination
    
    def get_queryset(self):
        return ChatMessage.objects.filter(
            conversation__group__members=self.request.user
        ).select_related('sender', 'conversation__group')
    
    def create(self, request, *args, **kwargs):
        """
        Create a new message in a group conversation.
        Supports both multipart/form-data for file uploads and JSON for text messages.
        """
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        
        # Get group from request data
        group_id = request.data.get('group_id')
        if not group_id:
            return Response(
                {'error': 'group_id is required'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        try:
            group = Group.objects.get(id=group_id)
            
            # Send message using ChatService
            message = ChatService.send_message(
                sender=request.user,
                group=group,
                **serializer.validated_data
            )
            
            # Return serialized message
            response_serializer = self.get_serializer(message)
            return Response(response_serializer.data, status=status.HTTP_201_CREATED)
            
        except Group.DoesNotExist:
            return Response(
                {'error': 'Group not found'}, 
                status=status.HTTP_404_NOT_FOUND
            )
        except ValidationError as e:
            return Response(
                {'error': str(e)}, 
                status=status.HTTP_400_BAD_REQUEST
            )
    
    def update(self, request, *args, **kwargs):
        """Edit a message (content only, within 15 minutes)."""
        instance = self.get_object()
        new_content = request.data.get('content', '').strip()
        
        if not new_content:
            return Response(
                {'error': 'Content is required for message edit'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        success, message = ChatService.edit_message(instance, request.user, new_content)
        
        if success:
            # Refresh instance and return updated data
            instance.refresh_from_db()
            serializer = self.get_serializer(instance)
            return Response(serializer.data)
        else:
            return Response(
                {'error': message}, 
                status=status.HTTP_400_BAD_REQUEST
            )
    
    def destroy(self, request, *args, **kwargs):
        """Soft delete a message."""
        instance = self.get_object()
        
        success, message = ChatService.delete_message(instance, request.user)
        
        if success:
            return Response({'message': message}, status=status.HTTP_200_OK)
        else:
            return Response(
                {'error': message}, 
                status=status.HTTP_403_FORBIDDEN
            )
    
    
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


class ConversationViewSet(viewsets.GenericViewSet,
                         mixins.ListModelMixin,
                         mixins.RetrieveModelMixin,
                         mixins.CreateModelMixin):
    serializer_class = ConversationSerializer
    permission_classes = [IsAuthenticated]
    pagination_class = None  # No pagination for conversations list
    
    def get_queryset(self):
        return ConversationService.get_user_conversations(self.request.user)
    
    def list(self, request, *args, **kwargs):
        """List all conversations for current user"""
        conversations = self.get_queryset()
        serializer = self.get_serializer(conversations, many=True)
        return Response({'conversations': serializer.data})
    
    
    @action(detail=False, methods=['post'])
    def create_direct(self, request):
        other_user_id = request.data.get('user_id')
        
        if not other_user_id:
            return Response(
                {'error': 'user_id is required'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        try:
            from django.contrib.auth import get_user_model
            User = get_user_model()
            
            other_user = User.objects.get(id=other_user_id)
            
            if other_user == request.user:
                return Response(
                    {'error': 'Cannot create conversation with yourself'}, 
                    status=status.HTTP_400_BAD_REQUEST
                )
            
            conversation, created = ConversationService.get_or_create_direct_conversation(
                request.user, other_user
            )
            
            serializer = self.get_serializer(conversation)
            return Response({
                'conversation': serializer.data,
                'created': created
            }, status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)
            
        except User.DoesNotExist:
            return Response(
                {'error': 'User not found'}, 
                status=status.HTTP_404_NOT_FOUND
            )
        except ValidationError as e:
            return Response(
                {'error': str(e)}, 
                status=status.HTTP_400_BAD_REQUEST
            )
    
    @action(detail=True, methods=['get'])
    def messages(self, request, pk=None):
        conversation = self.get_object()
        
        if not ConversationService._can_user_access_conversation(request.user, conversation):
            return Response(
                {'error': 'Access denied to this conversation'}, 
                status=status.HTTP_403_FORBIDDEN
            )
        
        limit = min(int(request.query_params.get('limit', 50)), 100)
        before_id = request.query_params.get('before_id')
        
        try:
            messages_data = ConversationService.get_conversation_messages(
                user=request.user,
                conversation_id=str(conversation.id),
                limit=limit,
                before_id=before_id
            )
            
            from .serializers import ChatMessageSerializer
            serializer = ChatMessageSerializer(
                messages_data['messages'], 
                many=True, 
                context={'request': request}
            )
            
            if not before_id and serializer.data:  # Only on first load, not pagination
                message_ids = [msg['id'] for msg in serializer.data if msg['sender']['id'] != str(request.user.id)]
                if message_ids:
                    ConversationService.mark_messages_read(
                        user=request.user,
                        conversation_id=str(conversation.id),
                        message_ids=message_ids
                    )
            
            return Response({
                'messages': serializer.data,
                'has_more': messages_data['has_more'],
                'next_cursor': messages_data['next_cursor'],
                'count': len(serializer.data)
            })
            
        except ValidationError as e:
            return Response({'error': str(e)}, status=status.HTTP_400_BAD_REQUEST)
    
    @action(detail=True, methods=['post'])
    def send_message(self, request, pk=None):
 
        conversation = self.get_object()
        
        if not ConversationService._can_user_access_conversation(request.user, conversation):
            return Response(
                {'error': 'Access denied to this conversation'}, 
                status=status.HTTP_403_FORBIDDEN
            )
        
        # Use DRF serializer for validation and data cleaning
        serializer = ChatMessageSerializer(data=request.data, context={'request': request})
        
        if not serializer.is_valid():
            return Response(
                {'errors': serializer.errors}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        try:
            # Create message using service layer
            message = ConversationService.create_message(
                conversation=conversation,
                sender=request.user,
                validated_data=serializer.validated_data
            )
            
            # Return serialized response
            response_serializer = ChatMessageSerializer(message, context={'request': request})
            return Response(response_serializer.data, status=status.HTTP_201_CREATED)
            
        except PermissionDenied as e:
            return Response(
                {'error': str(e)}, 
                status=status.HTTP_403_FORBIDDEN
            )
        except ValidationError as e:
            return Response(
                {'error': str(e)}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        except Exception as e:
            logger.error(f"Unexpected error in send_message: {e}")
            return Response(
                {'error': 'Internal server error'}, 
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )
        
    
    @action(detail=True, methods=['post'])
    def mark_read(self, request, pk=None):
        conversation = self.get_object()
        
        if not ConversationService._can_user_access_conversation(request.user, conversation):
            return Response(
                {'error': 'Access denied to this conversation'}, 
                status=status.HTTP_403_FORBIDDEN
            )
        
        message_ids = request.data.get('message_ids', [])
        
        if not message_ids:
            return Response(
                {'error': 'message_ids is required'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        success, error_message = ConversationService.mark_messages_read(
            user=request.user,
            conversation_id=str(conversation.id),
            message_ids=message_ids
        )
        
        if not success:
            return Response({'error': error_message}, status=status.HTTP_400_BAD_REQUEST)
        
        return Response({'success': True, 'message': error_message})


class PlanActivityViewSet(viewsets.GenericViewSet,
                          mixins.CreateModelMixin,
                          mixins.RetrieveModelMixin,
                          mixins.UpdateModelMixin,
                          mixins.DestroyModelMixin):
    serializer_class = PlanActivitySerializer
    permission_classes = [IsAuthenticated, PlanActivityPermission]
    pagination_class = ActivityCursorPagination  # Use cursor pagination for activities
    
    def get_serializer_class(self):
        if self.action == 'create':
            return PlanActivityCreateSerializer
        return PlanActivitySerializer
    
    def get_queryset(self):
        return PlanActivity.objects.filter(
            plan__group__members=self.request.user
        ).select_related('plan', 'plan__group')
    
    def create(self, request, *args, **kwargs):
        return super().create(request, *args, **kwargs)
    
    def retrieve(self, request, *args, **kwargs):
        """
        Get full activity details - returns complete PlanActivitySerializer data
        This is called when user opens activity detail dialog
        """
        return super().retrieve(request, *args, **kwargs)
    
    
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


# ============================================================================
# MINIMAP LOCATION VIEWS - Enhanced location services for minimap integration
# ============================================================================

class LocationReverseGeocodeView(APIView):
    """
    API endpoint for reverse geocoding coordinates to address
    """
    permission_classes = [IsAuthenticated]

    def post(self, request):
        try:
            latitude = request.data.get('latitude')
            longitude = request.data.get('longitude')
            
            if latitude is None or longitude is None:
                return Response(
                    {'error': 'Latitude and longitude are required'},
                    status=status.HTTP_400_BAD_REQUEST
                )
            
            # Convert to float and validate
            try:
                lat = float(latitude)
                lng = float(longitude)
                
                if not (-90 <= lat <= 90):
                    return Response(
                        {'error': 'Latitude must be between -90 and 90'},
                        status=status.HTTP_400_BAD_REQUEST
                    )
                
                if not (-180 <= lng <= 180):
                    return Response(
                        {'error': 'Longitude must be between -180 and 180'},
                        status=status.HTTP_400_BAD_REQUEST
                    )
                
            except (ValueError, TypeError):
                return Response(
                    {'error': 'Invalid latitude or longitude format'},
                    status=status.HTTP_400_BAD_REQUEST
                )
            
            # Use Goong service for reverse geocoding
            goong_service = GoongMapService()
            
            if goong_service.is_available():
                result = goong_service.reverse_geocode(lat, lng)
                
                if result:
                    return Response({
                        'formatted_address': result.get('formatted_address', ''),
                        'location_name': result.get('formatted_address', 'Vị trí đã chọn'),
                        'latitude': lat,
                        'longitude': lng,
                        'place_id': result.get('place_id'),
                        'address_components': result.get('address_components', []),
                        'compound': result.get('compound', {})
                    })
            
            # Fallback response if Goong service is not available
            return Response({
                'formatted_address': f'{lat:.6f}, {lng:.6f}',
                'location_name': 'Vị trí đã chọn',
                'latitude': lat,
                'longitude': lng,
                'place_id': None,
                'address_components': [],
                'compound': {}
            })
            
        except Exception as e:
            return Response(
                {'error': 'Internal server error'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


class LocationSearchView(APIView):
    """
    API endpoint for searching places
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        try:
            query = request.query_params.get('q', '').strip()
            
            if not query:
                return Response(
                    {'error': 'Search query is required'},
                    status=status.HTTP_400_BAD_REQUEST
                )
            
            if len(query) < 2:
                return Response(
                    {'error': 'Search query must be at least 2 characters'},
                    status=status.HTTP_400_BAD_REQUEST
                )
            
            # Use Goong service for place search
            goong_service = GoongMapService()
            
            if goong_service.is_available():
                results = goong_service.search_places(query)
                return Response({'results': results})
            else:
                return Response({
                    'results': [],
                    'message': 'Location search service is not available'
                })
                
        except Exception as e:
            return Response(
                {'error': 'Internal server error'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


class LocationAutocompleteView(APIView):
    """
    API endpoint for place autocomplete suggestions
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        try:
            input_text = request.query_params.get('input', '').strip()
            
            if not input_text:
                return Response({'predictions': []})
            
            if len(input_text) < 2:
                return Response({'predictions': []})
            
            # Use Goong service for autocomplete
            goong_service = GoongMapService()
            
            if goong_service.is_available():
                suggestions = goong_service.autocomplete(input_text)
                
                # Format suggestions for frontend
                predictions = []
                for suggestion in suggestions:
                    predictions.append({
                        'place_id': suggestion.get('place_id'),
                        'description': suggestion.get('description', ''),
                        'structured_formatting': suggestion.get('structured_formatting', {}),
                        'types': suggestion.get('types', []),
                        # Note: Goong autocomplete doesn't return coordinates directly
                        # You would need to call place details API to get coordinates
                        'latitude': None,
                        'longitude': None,
                    })
                
                return Response({'predictions': predictions})
            else:
                return Response({
                    'predictions': [],
                    'message': 'Autocomplete service is not available'
                })
                
        except Exception as e:
            return Response(
                {'error': 'Internal server error'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


class LocationPlaceDetailsView(APIView):
    """
    API endpoint for getting place details by place_id
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        try:
            place_id = request.query_params.get('place_id', '').strip()
            
            if not place_id:
                return Response(
                    {'error': 'place_id is required'},
                    status=status.HTTP_400_BAD_REQUEST
                )
            
            # Use Goong service for place details
            goong_service = GoongMapService()
            
            if goong_service.is_available():
                details = goong_service.get_place_details(place_id)
                
                if details:
                    return Response(details)
                else:
                    return Response(
                        {'error': 'Place not found'},
                        status=status.HTTP_404_NOT_FOUND
                    )
            else:
                return Response(
                    {'error': 'Place details service is not available'},
                    status=status.HTTP_503_SERVICE_UNAVAILABLE
                )
                
        except Exception as e:
            return Response(
                {'error': 'Internal server error'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )