"""
Base WebSocket consumer for real-time features.
"""
import json
import logging
from typing import Dict, Any
from channels.generic.websocket import AsyncWebsocketConsumer
from channels.db import database_sync_to_async
from django.core.cache import cache
from planpals.shared.events import RealtimeEvent, EventType, ChannelGroups

logger = logging.getLogger(__name__)


class BaseRealtimeConsumer(AsyncWebsocketConsumer):    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.user = None
        self.group_names = []
        
    async def connect(self):
        self.user = self.scope["user"]
        
        # Check if user is authenticated
        if not self.user or not self.user.is_authenticated:
            await self.close(code=4001)  # Unauthorized
            return

        await self.accept()
        await self.on_connect()
        
        await self.track_connection(True)
        
    async def disconnect(self, close_code):
        try:
            await self.on_disconnect()
            
            # Leave all groups
            for group_name in self.group_names:
                await self.channel_layer.group_discard(group_name, self.channel_name)
                
            await self.track_connection(False)
        except Exception as e:
            logger.error(f"Error during disconnect: {e}")
            
    async def receive(self, text_data):
        try:
            data = json.loads(text_data)
            await self.handle_message(data)
        except json.JSONDecodeError:
            await self.send_error("Invalid JSON")
        except Exception as e:
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
        cache_key = f"ws_connected:{self.user.id}"
        if connected:
            cache.set(cache_key, True, timeout=300)  # 5 minutes
        else:
            cache.delete(cache_key)
            
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
