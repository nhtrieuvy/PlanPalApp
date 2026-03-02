"""
WebSocket consumer for group-specific real-time updates.
"""
import logging
from typing import Dict, Any
from channels.db import database_sync_to_async

from planpals.shared.consumers import BaseRealtimeConsumer
from planpals.shared.events import ChannelGroups

logger = logging.getLogger(__name__)


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
        from planpals.groups.infrastructure.models import Group
        try:
            group = Group.objects.get(id=group_id)
            return group.members.filter(id=user_id).exists()
        except Group.DoesNotExist:
            return False
