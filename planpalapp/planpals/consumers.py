"""
WebSocket consumers for real-time features
"""
import json
import logging
from typing import Dict, Any
from channels.generic.websocket import AsyncWebsocketConsumer
from channels.db import database_sync_to_async
from django.contrib.auth.models import AnonymousUser
from django.core.cache import cache
from .events import RealtimeEvent, EventType, ChannelGroups
from .models import Plan, Group, User

logger = logging.getLogger(__name__)


class BaseRealtimeConsumer(AsyncWebsocketConsumer):
    """Base consumer with common functionality"""
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.user = None
        self.group_names = []
        
    async def connect(self):
        """Accept WebSocket connection if user is authenticated"""
        self.user = self.scope["user"]
        
        if isinstance(self.user, AnonymousUser):
            await self.close(code=4001)  # Unauthorized
            return
            
        await self.accept()
        await self.on_connect()
        
        # Track connection for monitoring
        await self.track_connection(True)
        
    async def disconnect(self, close_code):
        """Clean up when WebSocket disconnects"""
        try:
            await self.on_disconnect()
            
            # Leave all groups
            for group_name in self.group_names:
                await self.channel_layer.group_discard(group_name, self.channel_name)
                
            await self.track_connection(False)
        except Exception as e:
            logger.error(f"Error during disconnect: {e}")
            
    async def receive(self, text_data):
        """Handle incoming WebSocket messages"""
        try:
            data = json.loads(text_data)
            await self.handle_message(data)
        except json.JSONDecodeError:
            await self.send_error("Invalid JSON")
        except Exception as e:
            logger.error(f"Error handling message: {e}")
            await self.send_error("Internal error")
            
    async def send_event(self, event: RealtimeEvent):
        """Send event to WebSocket client"""
        await self.send(text_data=json.dumps(event.to_dict()))
        
    async def send_error(self, error_message: str):
        """Send error message to client"""
        await self.send(text_data=json.dumps({
            'type': 'error',
            'message': error_message
        }))
        
    async def join_group(self, group_name: str):
        """Join a channel group and track it"""
        await self.channel_layer.group_add(group_name, self.channel_name)
        if group_name not in self.group_names:
            self.group_names.append(group_name)
            
    async def leave_group(self, group_name: str):
        """Leave a channel group"""
        await self.channel_layer.group_discard(group_name, self.channel_name)
        if group_name in self.group_names:
            self.group_names.remove(group_name)
            
    async def track_connection(self, connected: bool):
        """Track user connection status"""
        cache_key = f"ws_connected:{self.user.id}"
        if connected:
            cache.set(cache_key, True, timeout=300)  # 5 minutes
        else:
            cache.delete(cache_key)
            
    # Abstract methods to be implemented by subclasses
    async def on_connect(self):
        """Called after successful connection"""
        pass
        
    async def on_disconnect(self):
        """Called before disconnection"""
        pass
        
    async def handle_message(self, data: Dict[str, Any]):
        """Handle incoming message from client"""
        pass
        
    # Channel layer message handlers (called when messages sent to groups)
    async def event_message(self, event):
        """Handle event messages sent to channel groups"""
        await self.send(text_data=json.dumps(event['data']))


class PlanConsumer(BaseRealtimeConsumer):
    """Consumer for plan-specific real-time updates"""
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.plan_id = None
        self.plan = None
        
    async def on_connect(self):
        """Join plan-specific channel group"""
        self.plan_id = self.scope['url_route']['kwargs']['plan_id']
        
        # Verify user has access to this plan
        plan_access = await self.check_plan_access(self.plan_id, self.user.id)
        if not plan_access:
            await self.close(code=4003)  # Forbidden
            return
            
        # Join plan group
        group_name = ChannelGroups.plan(self.plan_id)
        await self.join_group(group_name)
        
        logger.info(f"User {self.user.id} joined plan {self.plan_id} channel")
        
    async def handle_message(self, data: Dict[str, Any]):
        """Handle plan-specific messages"""
        msg_type = data.get('type')
        
        if msg_type == 'ping':
            await self.send(text_data=json.dumps({'type': 'pong'}))
        elif msg_type == 'subscribe_activity':
            # Client wants updates for specific activity
            activity_id = data.get('activity_id')
            if activity_id:
                group_name = f"activity_{activity_id}"
                await self.join_group(group_name)
        elif msg_type == 'get_plan_status':
            # Send current plan status
            plan_data = await self.get_plan_data(self.plan_id)
            await self.send(text_data=json.dumps({
                'type': 'plan_status',
                'data': plan_data
            }))
            
    @database_sync_to_async
    def check_plan_access(self, plan_id: str, user_id: str) -> bool:
        """Check if user has access to plan"""
        try:
            plan = Plan.objects.get(id=plan_id)
            
            # Creator always has access
            if plan.creator_id == user_id:
                return True
                
            # Group members have access to group plans
            if plan.plan_type == 'group' and plan.group:
                return plan.group.members.filter(id=user_id).exists()
                
            # Public plans are accessible to everyone
            if plan.is_public:
                return True
                
            return False
        except Plan.DoesNotExist:
            return False
            
    @database_sync_to_async
    def get_plan_data(self, plan_id: str) -> Dict[str, Any]:
        """Get current plan data"""
        try:
            plan = Plan.objects.get(id=plan_id)
            return {
                'id': str(plan.id),
                'status': plan.status,
                'title': plan.title,
                'start_date': plan.start_date.isoformat() if plan.start_date else None,
                'end_date': plan.end_date.isoformat() if plan.end_date else None,
                'activities_count': plan.activities_count,
                'last_updated': plan.updated_at.isoformat()
            }
        except Plan.DoesNotExist:
            return {}


class GroupConsumer(BaseRealtimeConsumer):
    """Consumer for group-specific real-time updates"""
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.group_id = None
        
    async def on_connect(self):
        """Join group-specific channel"""
        self.group_id = self.scope['url_route']['kwargs']['group_id']
        
        # Verify user is member of this group
        is_member = await self.check_group_membership(self.group_id, self.user.id)
        if not is_member:
            await self.close(code=4003)  # Forbidden
            return
            
        # Join group channel
        group_name = ChannelGroups.group(self.group_id)
        await self.join_group(group_name)
        
        logger.info(f"User {self.user.id} joined group {self.group_id} channel")
        
    @database_sync_to_async
    def check_group_membership(self, group_id: str, user_id: str) -> bool:
        """Check if user is member of group"""
        try:
            group = Group.objects.get(id=group_id)
            return group.members.filter(id=user_id).exists()
        except Group.DoesNotExist:
            return False


class UserConsumer(BaseRealtimeConsumer):
    """Consumer for user-specific private updates"""
    
    async def on_connect(self):
        """Join user's private channel"""
        group_name = ChannelGroups.user(str(self.user.id))
        await self.join_group(group_name)
        
        # Also join general notifications
        await self.join_group(ChannelGroups.notifications())
        
        logger.info(f"User {self.user.id} joined personal channel")


class NotificationConsumer(BaseRealtimeConsumer):
    """Consumer for general notifications and announcements"""
    
    async def on_connect(self):
        """Join notifications channel"""
        await self.join_group(ChannelGroups.notifications())
        await self.join_group(ChannelGroups.system())
        
        logger.info(f"User {self.user.id} joined notifications channel")


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
            'type': 'message',
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
        try:
            from .models import Conversation, User
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
        try:
            from .models import ChatMessage, MessageReadStatus
            
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
