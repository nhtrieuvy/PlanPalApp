"""
WebSocket consumer for plan-specific real-time updates.
"""
import json
import logging
from typing import Dict, Any

from channels.db import database_sync_to_async

from planpals.shared.consumers import BaseRealtimeConsumer
from planpals.shared.events import ChannelGroups

logger = logging.getLogger(__name__)


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
        from planpals.plans.infrastructure.models import Plan
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
        from planpals.plans.infrastructure.models import Plan
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
