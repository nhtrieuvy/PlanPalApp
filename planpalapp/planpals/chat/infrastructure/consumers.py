"""
Chat WebSocket consumer for real-time messaging.
"""
import json
import logging
from typing import Dict, Any
from channels.db import database_sync_to_async

from planpals.shared.consumers import BaseRealtimeConsumer
from planpals.shared.events import ChannelGroups

logger = logging.getLogger(__name__)


class ChatConsumer(BaseRealtimeConsumer):
    """Consumer for chat messaging with conversation support"""
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.conversation_id = None
        
    async def on_connect(self):
        """Join conversation-specific channel"""
        self.conversation_id = self.scope['url_route']['kwargs']['conversation_id']
        
        # Verify user has access to this conversation
        has_access = await self.check_conversation_access(self.conversation_id, self.user.id)
        if not has_access:
            await self.close(code=4003)  # Forbidden
            return
            
        # Join conversation channel
        group_name = ChannelGroups.conversation(self.conversation_id)
        await self.join_group(group_name)
        
        # Also join user's personal channel for DMs
        await self.join_group(ChannelGroups.user(str(self.user.id)))
        
        logger.info(f"User {self.user.id} joined conversation {self.conversation_id}")
        
    async def handle_message(self, data: Dict[str, Any]):
        """Handle chat-specific messages"""
        msg_type = data.get('type')
        
        if msg_type == 'ping':
            await self.send(text_data=json.dumps({'type': 'pong'}))
        elif msg_type == 'typing':
            # Broadcast typing indicator to other participants
            await self.channel_layer.group_send(
                ChannelGroups.conversation(self.conversation_id),
                {
                    'type': 'typing_message',
                    'data': {
                        'user_id': str(self.user.id),
                        'username': self.user.username,
                        'is_typing': data.get('is_typing', True)
                    }
                }
            )
        elif msg_type == 'mark_read':
            # Mark messages as read
            message_ids = data.get('message_ids', [])
            if message_ids:
                await self.mark_messages_read(message_ids)
        elif msg_type == 'join_room':
            # Client explicitly joining room (re-connect scenario)
            await self.send(text_data=json.dumps({
                'type': 'room_joined',
                'conversation_id': self.conversation_id
            }))
            
    async def typing_message(self, event):
        """Handle typing indicator messages"""
        await self.send(text_data=json.dumps({
            'type': 'typing',
            'data': event['data']
        }))
        
    async def chat_message(self, event):
        """Handle new chat messages from channel layer"""
        await self.send(text_data=json.dumps({
            'type': 'chat_message',
            'data': event['data']
        }))
        
    async def message_updated(self, event):
        """Handle message edit events"""
        await self.send(text_data=json.dumps({
            'type': 'message_updated',
            'data': event['data']
        }))
        
    async def message_deleted(self, event):
        """Handle message delete events"""
        await self.send(text_data=json.dumps({
            'type': 'message_deleted',
            'data': event['data']
        }))
        
    @database_sync_to_async
    def check_conversation_access(self, conversation_id: str, user_id: str) -> bool:
        """Check if user has access to conversation"""
        from planpals.chat.infrastructure.models import Conversation
        from django.contrib.auth import get_user_model
        User = get_user_model()
        try:
            conversation = Conversation.objects.get(id=conversation_id)
            user = User.objects.get(id=user_id)
            
            if conversation.conversation_type == 'direct':
                return conversation.user_a == user or conversation.user_b == user
            elif conversation.conversation_type == 'group' and conversation.group:
                return conversation.group.members.filter(id=user_id).exists()
                
            return False
        except (Conversation.DoesNotExist, User.DoesNotExist):
            return False
            
    @database_sync_to_async
    def mark_messages_read(self, message_ids: list):
        """Mark messages as read by current user"""
        from planpals.chat.infrastructure.models import ChatMessage, MessageReadStatus
        try:
            
            messages = ChatMessage.objects.filter(
                id__in=message_ids,
                conversation_id=self.conversation_id
            ).exclude(sender=self.user)
            
            for message in messages:
                MessageReadStatus.objects.get_or_create(
                    message=message,
                    user=self.user
                )
                
        except Exception as e:
            logger.error(f"Error marking messages as read: {e}")
