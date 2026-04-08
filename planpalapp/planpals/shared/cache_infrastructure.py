"""
Django-Redis cache implementation.

Provides the concrete ``CachePort`` backed by django-redis.
All cache operations fail gracefully (log + return ``None`` / no-op)
so the application keeps working when Redis is unavailable.
"""
import logging
import time
from typing import Any, Callable, Optional

from django.core.cache import cache

from planpals.shared.cache import CachePort

logger = logging.getLogger(__name__)


class DjangoCacheService(CachePort):
    """
    Redis-backed cache via ``django-redis``.

    Overrides ``get_or_set`` with lock-based stampede prevention so that
    only ONE process recomputes on a cache miss while others briefly wait.
    """

    def get(self, key: str) -> Optional[Any]:
        try:
            return cache.get(key)
        except Exception as e:
            logger.warning("Cache GET failed for key=%s: %s", key, e)
            return None

    def set(self, key: str, value: Any, ttl: int = None) -> None:
        try:
            cache.set(key, value, timeout=ttl)
        except Exception as e:
            logger.warning("Cache SET failed for key=%s: %s", key, e)

    def delete(self, key: str) -> None:
        try:
            cache.delete(key)
        except Exception as e:
            logger.warning("Cache DELETE failed for key=%s: %s", key, e)

    def delete_pattern(self, pattern: str) -> None:
        try:
            delete_pattern = getattr(cache, 'delete_pattern', None)
            if callable(delete_pattern):
                delete_pattern(pattern)
        except Exception as e:
            logger.warning("Cache DELETE_PATTERN failed for pattern=%s: %s", pattern, e)

    # ------------------------------------------------------------------
    # Stampede-prevention override
    # ------------------------------------------------------------------

    def get_or_set(
        self,
        key: str,
        compute_fn: Callable[[], Any],
        ttl: int = None,
    ) -> Any:
        """
        Fetch from cache with lock-based stampede prevention.

        On a miss the first process acquires a short-lived lock via
        ``cache.add()`` so only it runs *compute_fn()*.  Other processes
        poll briefly then fall back to direct computation.
        """
        value = self.get(key)
        if value is not None:
            return value

        lock_key = f"{key}:_lock"
        lock_acquired = False
        try:
            lock_acquired = cache.add(lock_key, "1", timeout=10)
        except Exception:
            pass

        if lock_acquired:
            try:
                # Double-check after acquiring lock
                value = self.get(key)
                if value is not None:
                    return value

                value = compute_fn()
                if value is not None:
                    self.set(key, value, ttl)
                return value
            finally:
                self.delete(lock_key)
        else:
            # Another process holds the lock — poll briefly
            for _ in range(5):
                time.sleep(0.05)
                value = self.get(key)
                if value is not None:
                    return value

            # Fallback: compute ourselves
            value = compute_fn()
            if value is not None:
                self.set(key, value, ttl)
            return value


class NullCacheService(CachePort):
    """
    No-op cache — useful for tests or when Redis is intentionally disabled.
    Every ``get`` returns ``None``; ``get_or_set`` always computes.
    """

    def get(self, key: str) -> Optional[Any]:
        return None

    def set(self, key: str, value: Any, ttl: int = None) -> None:
        pass

    def delete(self, key: str) -> None:
        pass

    def delete_pattern(self, pattern: str) -> None:
        pass
