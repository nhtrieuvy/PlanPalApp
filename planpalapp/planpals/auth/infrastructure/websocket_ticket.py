import secrets
import time

from django.conf import settings
from django.core.cache import cache


class WebSocketTicketService:
    """Issues and consumes short-lived, single-use WebSocket credentials."""

    key_prefix = 'ws_ticket'

    @classmethod
    def ttl_seconds(cls) -> int:
        return int(getattr(settings, 'WEBSOCKET_TICKET_TTL_SECONDS', 45))

    @classmethod
    def issue(cls, user_id) -> str:
        ticket = secrets.token_urlsafe(32)
        ttl = cls.ttl_seconds()
        cache.set(
            cls._key(ticket),
            {'user_id': str(user_id), 'expires_at': time.time() + ttl},
            timeout=ttl,
        )
        return ticket

    @classmethod
    def consume(cls, ticket: str):
        if not ticket:
            return None

        key = cls._key(ticket)
        payload = cache.get(key)
        if (
            not isinstance(payload, dict)
            or not payload.get('user_id')
            or float(payload.get('expires_at', 0)) <= time.time()
        ):
            return None

        # cache.add is atomic for Redis and prevents concurrent replays.
        claim_key = f'{key}:claimed'
        if not cache.add(claim_key, True, timeout=cls.ttl_seconds()):
            return None

        cache.delete(key)
        return payload

    @classmethod
    def _key(cls, ticket: str) -> str:
        return f'{cls.key_prefix}:{ticket}'
