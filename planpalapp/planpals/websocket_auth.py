"""
Middleware cho Channels WebSocket chịu trách nhiệm xác thực người dùng thông qua token OAuth2 được truyền qua query string.
WebSocket không dùng cookies hay sessions như HTTP, nên ta phải lấy token từ query string.
"""
import logging
from urllib.parse import parse_qs
from channels.db import database_sync_to_async
from channels.middleware import BaseMiddleware
from django.contrib.auth.models import AnonymousUser
from oauth2_provider.models import AccessToken

logger = logging.getLogger(__name__)

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

# Hàm đọc token từ query string gán cho user vào scope cho websocket 
class TokenAuthMiddleware(BaseMiddleware):    

    async def __call__(self, scope, receive, send):
        if scope['type'] == 'websocket':
            query_string = scope.get('query_string', b'')
            query_params = parse_qs(query_string.decode())
            token = query_params.get('token', [None])[0]
            
            if token:
                user = await get_user_from_token(token)
                scope['user'] = user
            else:
                scope['user'] = AnonymousUser()
        
        return await super().__call__(scope, receive, send)


def TokenAuthMiddlewareStack(inner):
    return TokenAuthMiddleware(inner)