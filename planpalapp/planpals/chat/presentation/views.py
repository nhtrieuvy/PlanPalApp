import logging

from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError, PermissionDenied

from rest_framework import viewsets, status, mixins
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated

from planpals.chat.infrastructure.models import ChatMessage, Conversation
from planpals.chat.presentation.serializers import ChatMessageSerializer, ConversationSerializer
from planpals.chat.presentation.permissions import ChatMessagePermission, ConversationPermission
from planpals.chat.application.services import ConversationService, ChatService
from planpals.models import Group
from planpals.shared.paginators import StandardResultsPagination, ChatMessageCursorPagination

User = get_user_model()
logger = logging.getLogger(__name__)


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
        ).select_related(
            'sender', 'conversation__group', 'reply_to__sender'
        )
    
    def create(self, request, *args, **kwargs):
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
    pagination_class = StandardResultsPagination
    
    def get_queryset(self):
        return ConversationService.get_user_conversations(self.request.user)
    
    def list(self, request, *args, **kwargs):
        """List all conversations for current user with optional search"""
        query = request.query_params.get('q')
        
        if query:
            conversations = ConversationService.search_user_conversations(request.user, query)
        else:
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
