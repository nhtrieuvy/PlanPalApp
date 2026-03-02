"""
Định nghĩa các endpoint websocket cho frontend kết nối
"""
from django.urls import re_path


def get_websocket_urlpatterns():
    """
    Lazy import consumers để tránh AppRegistryNotReady khi ASGI load
    Import consumers chỉ khi function được gọi (sau khi Django đã sẵn sàng)
    """
    from planpals.chat.infrastructure.consumers import ChatConsumer
    from planpals.plans.infrastructure.consumers import PlanConsumer
    from planpals.groups.infrastructure.consumers import GroupConsumer
    from planpals.notifications.infrastructure.consumers import (
        UserConsumer,
        NotificationConsumer,
    )
    
    return [
        # Chat realtime messaging - conversation based
        re_path(r'ws/chat/(?P<conversation_id>[\w-]+)/$', ChatConsumer.as_asgi()),
        
        # Plan realtime updates - requires plan_id and authentication
        re_path(r'ws/plans/(?P<plan_id>[\w-]+)/$', PlanConsumer.as_asgi()),
        
        # Group realtime updates - for group plans and notifications
        re_path(r'ws/groups/(?P<group_id>[\w-]+)/$', GroupConsumer.as_asgi()),
        
        # User personal updates - private channel for user-specific notifications
        re_path(r'ws/user/$', UserConsumer.as_asgi()),
        
        # General notifications - public announcements, system status
        re_path(r'ws/notifications/$', NotificationConsumer.as_asgi()),
    ]
