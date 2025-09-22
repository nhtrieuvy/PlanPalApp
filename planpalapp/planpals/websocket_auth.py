"""
Simple WebSocket token authentication middleware
"""
import logging
from urllib.parse import parse_qs
from channels.db import database_sync_to_async
from channels.middleware import BaseMiddleware
from django.contrib.auth.models import AnonymousUser
from oauth2_provider.models import AccessToken

logger = logging.getLogger(__name__)


@database_sync_to_async
def get_user_from_token(token_key):
    try:
        access_token = AccessToken.objects.select_related('user').get(
            token=token_key
        )
        
        if access_token.is_valid():
            return access_token.user
        else:
            return AnonymousUser()
            
    except Exception as e:
        return AnonymousUser()


class TokenAuthMiddleware(BaseMiddleware):    
    def __init__(self, inner):
        super().__init__(inner)
        logger.info("TokenAuthMiddleware initialized")
        print("TokenAuthMiddleware initialized")  # Debug print
    
    async def __call__(self, scope, receive, send):
        if scope['type'] == 'websocket':
            logger.info("WebSocket connection attempt")
            print(f"WebSocket connection attempt: {scope.get('path')}")  # Debug print
            # Parse query string to get token
            query_string = scope.get('query_string', b'')
            query_params = parse_qs(query_string.decode())
            token = query_params.get('token', [None])[0]
            
            logger.info(f"Token from query: {token[:10] if token else 'None'}...")
            print(f"Token from query: {token[:10] if token else 'None'}...")  # Debug print
            
            if token:
                user = await get_user_from_token(token)
                scope['user'] = user
                logger.info(f"Set scope user to: {user}")
                print(f"Set scope user to: {user}")  # Debug print
            else:
                scope['user'] = AnonymousUser()
                logger.warning("No token provided, setting AnonymousUser")
                print("No token provided, setting AnonymousUser")  # Debug print
        
        return await super().__call__(scope, receive, send)


def TokenAuthMiddlewareStack(inner):
    return TokenAuthMiddleware(inner)