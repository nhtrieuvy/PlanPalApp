from __future__ import annotations

from dataclasses import dataclass
from datetime import timedelta
from uuid import UUID

from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.utils import timezone

from planpals.shared.cache import CacheKeys
from planpals.shared.realtime_publisher import (
    publish_user_offline,
    publish_user_online,
)

RECENTLY_ONLINE_WINDOW = timedelta(minutes=5)


@dataclass(frozen=True)
class PresenceTransition:
    active_connections: int
    became_online: bool = False
    became_offline: bool = False


def _presence_counter_key(user_id: UUID | str) -> str:
    return f"ws_presence_count:{user_id}"


def _presence_connection_key(user_id: UUID | str, channel_name: str) -> str:
    return f"ws_presence:{user_id}:{channel_name}"


def register_connection(user_id: UUID | str, channel_name: str) -> PresenceTransition:
    connection_key = _presence_connection_key(user_id, channel_name)
    counter_key = _presence_counter_key(user_id)

    # Ignore duplicate connects for the same socket channel.
    if not cache.add(connection_key, True, timeout=None):
        current = int(cache.get(counter_key) or 0)
        return PresenceTransition(active_connections=current)

    try:
        active_connections = cache.incr(counter_key)
    except ValueError:
        active_connections = 1
        cache.set(counter_key, active_connections, timeout=None)

    return PresenceTransition(
        active_connections=active_connections,
        became_online=active_connections == 1,
    )


def unregister_connection(user_id: UUID | str, channel_name: str) -> PresenceTransition:
    connection_key = _presence_connection_key(user_id, channel_name)
    counter_key = _presence_counter_key(user_id)

    if cache.get(connection_key) is None:
        current = int(cache.get(counter_key) or 0)
        return PresenceTransition(active_connections=current)

    cache.delete(connection_key)

    try:
        active_connections = cache.decr(counter_key)
    except ValueError:
        active_connections = 0

    if active_connections <= 0:
        cache.delete(counter_key)
        return PresenceTransition(active_connections=0, became_offline=True)

    return PresenceTransition(active_connections=active_connections)


def has_active_connection(user_id: UUID | str) -> bool:
    return int(cache.get(_presence_counter_key(user_id)) or 0) > 0


def is_recently_online(last_seen) -> bool:
    if last_seen is None:
        return False
    return last_seen >= timezone.now() - RECENTLY_ONLINE_WINDOW


def resolve_online_status(is_online: bool, last_seen) -> str:
    if is_online:
        return 'online'
    if is_recently_online(last_seen):
        return 'recently_online'
    return 'offline'


def sync_presence_transition(
    user_id: UUID | str,
    username: str,
    transition: PresenceTransition,
) -> None:
    User = get_user_model()

    if transition.active_connections > 0:
        updated = User.objects.filter(id=user_id, is_online=False).update(is_online=True)
        if updated:
            cache.delete(CacheKeys.user_profile(user_id))
            publish_user_online(user_id=str(user_id), username=username)
        return

    if transition.became_offline:
        last_seen = timezone.now()
        updated = User.objects.filter(id=user_id, is_online=True).update(
            is_online=False,
            last_seen=last_seen,
        )
        if updated:
            cache.delete(CacheKeys.user_profile(user_id))
            publish_user_offline(
                user_id=str(user_id),
                username=username,
                last_seen=last_seen.isoformat(),
            )
