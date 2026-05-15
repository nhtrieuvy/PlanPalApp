"""
Infrastructure cache helpers for group read models.
"""
import logging

from planpals.shared.cache import CacheKeys
from planpals.shared.cache_infrastructure import DjangoCacheService

logger = logging.getLogger(__name__)


def invalidate_group_detail_cache(group_id) -> None:
    """Invalidate all per-user cached group detail variants for one group."""
    try:
        cache_svc = DjangoCacheService()
        version_key = CacheKeys.group_detail_version(group_id)
        raw_version = cache_svc.get(version_key)
        try:
            current_version = int(raw_version)
        except (TypeError, ValueError):
            current_version = 1
        cache_svc.set(version_key, max(current_version, 1) + 1)
        cache_svc.delete_pattern(CacheKeys.group_detail_pattern(group_id))
    except Exception as exc:
        logger.warning(
            "Failed to invalidate group detail cache for %s: %s",
            group_id,
            exc,
        )
