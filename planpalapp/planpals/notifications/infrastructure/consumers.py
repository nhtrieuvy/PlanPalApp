import json
import logging
from typing import Dict, Any

from planpals.shared.consumers import BaseRealtimeConsumer
from planpals.shared.events import ChannelGroups

logger = logging.getLogger(__name__)


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
