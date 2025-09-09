"""
WebSocket URL routing for real-time features
"""
from django.urls import re_path
from . import consumers

websocket_urlpatterns = [
    # Plan realtime updates - requires plan_id and authentication
    re_path(r'ws/plans/(?P<plan_id>[\w-]+)/$', consumers.PlanConsumer.as_asgi()),
    
    # Group realtime updates - for group plans and chat
    re_path(r'ws/groups/(?P<group_id>[\w-]+)/$', consumers.GroupConsumer.as_asgi()),
    
    # User personal updates - private channel for user-specific notifications
    re_path(r'ws/user/$', consumers.UserConsumer.as_asgi()),
    
    # General notifications - public announcements, system status
    re_path(r'ws/notifications/$', consumers.NotificationConsumer.as_asgi()),
]
