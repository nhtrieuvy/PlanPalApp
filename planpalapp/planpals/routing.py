"""
Định nghĩa các endpoint websocket cho frontend kết nối
"""
from django.urls import re_path


def get_websocket_urlpatterns():
    """
    Lazy import consumers để tránh AppRegistryNotReady khi ASGI load
    Import consumers chỉ khi function được gọi (sau khi Django đã sẵn sàng)
    """
    from . import consumers
    
    return [
        # Chat realtime messaging - conversation based
        re_path(r'ws/chat/(?P<conversation_id>[\w-]+)/$', consumers.ChatConsumer.as_asgi()),
        
        # Plan realtime updates - requires plan_id and authentication
        re_path(r'ws/plans/(?P<plan_id>[\w-]+)/$', consumers.PlanConsumer.as_asgi()),
        
        # Group realtime updates - for group plans and notifications
        re_path(r'ws/groups/(?P<group_id>[\w-]+)/$', consumers.GroupConsumer.as_asgi()),
        
        # User personal updates - private channel for user-specific notifications
        re_path(r'ws/user/$', consumers.UserConsumer.as_asgi()),
        
        # General notifications - public announcements, system status
        re_path(r'ws/notifications/$', consumers.NotificationConsumer.as_asgi()),
    ]
