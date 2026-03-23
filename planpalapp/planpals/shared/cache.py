"""
Cache abstractions for the application layer.

Domain and application layers depend on these interfaces.
Infrastructure provides concrete implementations (e.g. Redis).

Design decisions
────────────────
• CachePort is an ABC with get / set / delete / delete_pattern.
• get_or_set has a *default* implementation (no stampede prevention).
  The concrete DjangoCacheService overrides it with lock-based prevention.
• CacheKeys centralises all key patterns in one place so invalidation
  is always consistent with reads.
• CacheTTL keeps TTL constants together for easy tuning.
"""
from abc import ABC, abstractmethod
from typing import Any, Callable, Optional


# ============================================================================
# ABSTRACT INTERFACE
# ============================================================================

class CachePort(ABC):
    """Abstract cache interface — application layer depends on this."""

    @abstractmethod
    def get(self, key: str) -> Optional[Any]:
        """Retrieve a value by key.  Returns ``None`` on miss."""
        ...

    @abstractmethod
    def set(self, key: str, value: Any, ttl: int = None) -> None:
        """Store *value* under *key* with an optional TTL (seconds)."""
        ...

    @abstractmethod
    def delete(self, key: str) -> None:
        """Remove a single key."""
        ...

    @abstractmethod
    def delete_pattern(self, pattern: str) -> None:
        """Remove all keys matching a glob pattern (e.g. ``v1:group:*``)."""
        ...

    # Non-abstract — subclasses may override for stampede prevention.
    def get_or_set(
        self,
        key: str,
        compute_fn: Callable[[], Any],
        ttl: int = None,
    ) -> Any:
        """
        Return the cached value for *key*.  On a miss call *compute_fn()*,
        cache the result (unless ``None``), and return it.
        """
        value = self.get(key)
        if value is not None:
            return value
        value = compute_fn()
        if value is not None:
            self.set(key, value, ttl)
        return value


# ============================================================================
# CACHE KEY BUILDER  (versioned, namespaced)
# ============================================================================

class CacheKeys:
    """
    Centralised, versioned cache-key builder.

    Key format: ``v{VERSION}:{context}:{entity}:{id}``

    Bump ``_V`` when the cached data shape changes so old entries
    are naturally ignored.
    """
    _V = "v1"

    # -- User profile -------------------------------------------------------
    @classmethod
    def user_profile(cls, user_id) -> str:
        return f"{cls._V}:user:profile:{user_id}"

    # -- Plan summary -------------------------------------------------------
    @classmethod
    def plan_summary(cls, plan_id) -> str:
        return f"{cls._V}:plan:summary:{plan_id}"

    # -- Group detail (per-user because serializer includes user-specific fields)
    @classmethod
    def group_detail(cls, group_id, user_id=None) -> str:
        base = f"{cls._V}:group:detail:{group_id}"
        return f"{base}:u{user_id}" if user_id else base

    @classmethod
    def group_detail_pattern(cls, group_id) -> str:
        """Glob pattern to invalidate ALL per-user variants."""
        return f"{cls._V}:group:detail:{group_id}*"


# ============================================================================
# TTL CONSTANTS (seconds)
# ============================================================================

class CacheTTL:
    USER_PROFILE = 120   # 2 minutes
    PLAN_SUMMARY = 180   # 3 minutes
    GROUP_DETAIL = 180   # 3 minutes
