"""Channels authentication using one-time tickets with legacy token fallback."""
import logging
from urllib.parse import parse_qs
from channels.db import database_sync_to_async
from channels.middleware import BaseMiddleware
from django.contrib.auth.models import AnonymousUser
from oauth2_provider.models import AccessToken
from django.contrib.auth import get_user_model

from planpals.auth.infrastructure.websocket_ticket import WebSocketTicketService

logger = logging.getLogger(__name__)
User = get_user_model()

# Gọi hàm đồng bộ trong môi trường bất đồng bộ, Django ORM chỉ hoạt động đồng bộ(sync), nếu gọi trực tiếp trong async sẽ lỗi block event loop
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
            
    except Exception:
        return AnonymousUser()


@database_sync_to_async
def get_user_from_ticket(ticket):
    try:
        payload = WebSocketTicketService.consume(ticket)
        if payload is None:
            return AnonymousUser()
        return User.objects.get(id=payload['user_id'], is_active=True)
    except (User.DoesNotExist, TypeError, ValueError):
        return AnonymousUser()
    except Exception:
        logger.warning('WebSocket ticket authentication failed', exc_info=True)
        return AnonymousUser()

# Hàm đọc token từ query string gán cho user vào scope cho websocket 
class TokenAuthMiddleware(BaseMiddleware):    

    async def __call__(self, scope, receive, send):
        if scope['type'] == 'websocket':
            query_string = scope.get('query_string', b'')
            query_params = parse_qs(query_string.decode())
            ticket = query_params.get('ticket', [None])[0]
            token = query_params.get('token', [None])[0]
            
            if ticket:
                user = await get_user_from_ticket(ticket)
                scope['user'] = user
            elif token:
                user = await get_user_from_token(token)
                scope['user'] = user
            else:
                scope['user'] = AnonymousUser()
        
        return await super().__call__(scope, receive, send)


def TokenAuthMiddlewareStack(inner):
    return TokenAuthMiddleware(inner)
