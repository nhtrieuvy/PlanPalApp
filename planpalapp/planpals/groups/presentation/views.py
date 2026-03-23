import logging

from django.shortcuts import get_object_or_404
from django.contrib.auth import get_user_model
from django.db import transaction
from django.core.exceptions import ValidationError, PermissionDenied

from rest_framework import viewsets, status, mixins
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from rest_framework.exceptions import ValidationError as DRFValidationError, PermissionDenied as DRFPermissionDenied, NotFound

from planpals.groups.infrastructure.models import Group, GroupMembership
from planpals.groups.presentation.serializers import (
    GroupDetailSerializer, GroupCreateSerializer, GroupSummarySerializer
)
from planpals.groups.presentation.permissions import (
    GroupPermission, IsGroupMember, IsGroupAdmin
)
from planpals.groups.application.services import GroupService
from planpals.auth.presentation.serializers import UserSerializer
from planpals.chat.presentation.serializers import ChatMessageSerializer
from planpals.plans.presentation.serializers import PlanSummarySerializer
from planpals.chat.application.services import ChatService
from planpals.shared.paginators import StandardResultsPagination, SearchResultsPagination

User = get_user_model()
logger = logging.getLogger(__name__)


class GroupViewSet(viewsets.GenericViewSet,
                   mixins.CreateModelMixin,
                   mixins.RetrieveModelMixin,
                   mixins.UpdateModelMixin,
                   mixins.DestroyModelMixin):
    serializer_class = GroupDetailSerializer
    permission_classes = [IsAuthenticated, GroupPermission]
    pagination_class = StandardResultsPagination
    
    def get_serializer_class(self):
        if self.action == 'create':
            return GroupCreateSerializer
        elif self.action in ('list', 'my_groups', 'created_by_me', 'search'):
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

    def retrieve(self, request, *args, **kwargs):
        pk = kwargs.get('pk') or kwargs.get(self.lookup_field)
        serializer_class = self.get_serializer_class()

        def serialize(group):
            return serializer_class(group, context={'request': request}).data

        data = GroupService.get_group_detail_cached(pk, request.user.id, serialize)
        if data is None:
            return Response({'error': 'Group not found'}, status=status.HTTP_404_NOT_FOUND)
        return Response(data)
    
    def list(self, request):
        queryset = self.get_queryset().order_by('-created_at')
        
        page = self.paginate_queryset(queryset)
        if page is not None:
            serializer = self.get_serializer(page, many=True)
            return self.get_paginated_response(serializer.data)
        
        serializer = self.get_serializer(queryset, many=True)
        return Response(serializer.data)
    
    def perform_create(self, serializer):
        # Delegate to GroupService (which delegates to CreateGroupHandler)
        data = serializer.validated_data
        group = GroupService.create_group(
            creator=self.request.user,
            name=data.get('name', ''),
            description=data.get('description', ''),
            avatar=data.get('avatar'),
            cover_image=data.get('cover_image'),
        )
        serializer.instance = group
    
    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated])
    def join(self, request, pk=None):
        try:
            success, message, group = GroupService.join_group(
                user=request.user,
                group_id=pk,
            )
            
            if not success:
                if 'not found' in message.lower():
                    return Response({'error': message}, status=status.HTTP_404_NOT_FOUND)
                if 'permission' in message.lower():
                    return Response({'error': message}, status=status.HTTP_403_FORBIDDEN)
                return Response({'error': message}, status=status.HTTP_400_BAD_REQUEST)

            return Response(GroupDetailSerializer(group, context={'request': request}).data)
        except DRFValidationError as e:
            return Response({'error': str(e)}, status=status.HTTP_400_BAD_REQUEST)
        except DRFPermissionDenied as e:
            return Response({'error': str(e)}, status=status.HTTP_403_FORBIDDEN)
        except NotFound as e:
            return Response({'error': str(e)}, status=status.HTTP_404_NOT_FOUND)
        except Exception:
            logger.exception("Unexpected error while joining group %s", pk)
            return Response({'error': 'Internal server error'}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
    
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

    # API rời nhóm (member tự rời)
    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, IsGroupMember])
    def leave(self, request, pk=None):
        group = self.get_object()
        user = request.user
        
        try:
            success, message = GroupService.leave_group(group, user)
            if not success:
                return Response({'error': message}, status=status.HTTP_400_BAD_REQUEST)
            
            return Response({
                'message': message,
                'group_id': str(group.id)
            })
        except Exception as e:
            return Response(
                {'error': 'Đã có lỗi xảy ra khi rời nhóm'}, 
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )

    # API xóa thành viên khỏi nhóm (admin thực hiện)
    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, IsGroupAdmin])
    def remove_member(self, request, pk=None):
        group = self.get_object()
        user_id = request.data.get('user_id')
        
        if not user_id:
            return Response({'error': 'user_id là bắt buộc'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        try:
            from django.contrib.auth import get_user_model
            User = get_user_model()
            
            user_to_remove = User.objects.get(id=user_id)
            success, message = GroupService.remove_member_from_group(
                group, user_to_remove, removed_by=request.user
            )
            
            if not success:
                return Response({'error': message}, status=status.HTTP_400_BAD_REQUEST)
            
            return Response({
                'message': message,
                'group_id': str(group.id),
                'user_id': user_id
            })
        except User.DoesNotExist:
            return Response({'error': 'Không tìm thấy người dùng'}, 
                          status=status.HTTP_404_NOT_FOUND)
        except Exception as e:
            return Response(
                {'error': 'Đã có lỗi xảy ra khi xóa thành viên'}, 
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
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
            
            serializer = ChatMessageSerializer(message)
            return Response(serializer.data, status=status.HTTP_201_CREATED)
            
        except ValidationError as e:
            return Response(
                {'error': str(e)}, 
                status=status.HTTP_403_FORBIDDEN
            )
