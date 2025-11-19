"""
ASGI config for planpalapp project.
"""

import os
from django.core.asgi import get_asgi_application

# Initialize Django ASGI application early to ensure AppRegistry is ready
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'planpalapp.settings')
django_asgi_app = get_asgi_application()

# NOW we can import Django models
from channels.routing import ProtocolTypeRouter, URLRouter
from planpals.websocket_auth import TokenAuthMiddlewareStack
from planpals.routing import get_websocket_urlpatterns  # ← FIX: Import function

application = ProtocolTypeRouter({
    "http": django_asgi_app,
    "websocket": TokenAuthMiddlewareStack(
        URLRouter(
            get_websocket_urlpatterns()  # ← FIX: CALL function
        )
    ),
})
