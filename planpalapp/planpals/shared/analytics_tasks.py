"""
Shared Celery Tasks — Analytics & Periodic Maintenance

Scheduled via Celery Beat (see ``settings.CELERY_BEAT_SCHEDULE``).
All tasks are routed to the ``low_priority`` queue so they never
compete with latency-sensitive notification delivery.

Queue: low_priority
Design:
  • Idempotent — safe to run more than once per period.
  • Chunked DB operations to limit memory.
  • Soft time limit to prevent long-running cleanup from blocking.
"""
import logging
from datetime import timedelta
from typing import Any, Dict

from celery import shared_task
from celery.exceptions import SoftTimeLimitExceeded
from django.utils import timezone

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Task 1: Aggregate daily statistics
# ---------------------------------------------------------------------------

@shared_task(
    bind=True,
    name='planpals.shared.analytics_tasks.aggregate_daily_statistics_task',
    max_retries=2,
    default_retry_delay=300,
    soft_time_limit=300,     # 5 min
    rate_limit='1/h',
    acks_late=True,
)
def aggregate_daily_statistics_task(self) -> Dict[str, Any]:
    """
    Compute daily aggregate statistics and store them in cache.

    Runs every day at 02:00 via Celery Beat.  Results are cached for 25 h
    so dashboards can read them without hitting the DB.
    """
    try:
        from django.core.cache import cache
        from planpals.models import Plan, Group, User

        now = timezone.now()
        yesterday = now - timedelta(days=1)

        stats = {
            'date': yesterday.date().isoformat(),
            'new_plans': Plan.objects.filter(created_at__date=yesterday.date()).count(),
            'active_plans': Plan.objects.filter(status='ongoing').count(),
            'completed_plans': Plan.objects.filter(
                status='completed',
                updated_at__date=yesterday.date(),
            ).count(),
            'new_groups': Group.objects.filter(created_at__date=yesterday.date()).count(),
            'active_users': User.objects.filter(
                last_login__gte=yesterday,
            ).count(),
            'total_users': User.objects.count(),
            'computed_at': now.isoformat(),
        }

        cache_key = f"planpal:stats:daily:{yesterday.date().isoformat()}"
        cache.set(cache_key, stats, timeout=90_000)  # 25 h

        # Also store as "latest" for quick dashboard reads
        cache.set('planpal:stats:daily:latest', stats, timeout=90_000)

        logger.info(f"Daily statistics aggregated for {yesterday.date()}: {stats}")
        return {'status': 'completed', **stats}

    except SoftTimeLimitExceeded:
        logger.error("Daily statistics aggregation timed out")
        return {'status': 'timeout'}

    except Exception as exc:
        logger.error(f"Daily statistics aggregation failed: {exc}")
        raise self.retry(exc=exc)


# ---------------------------------------------------------------------------
# Task 2: Cleanup expired offline-event cache entries
# ---------------------------------------------------------------------------

@shared_task(
    bind=True,
    name='planpals.shared.analytics_tasks.cleanup_expired_offline_events_task',
    max_retries=1,
    default_retry_delay=600,
    soft_time_limit=180,
    rate_limit='1/h',
    acks_late=True,
)
def cleanup_expired_offline_events_task(self) -> Dict[str, Any]:
    """
    Trim offline-event caches that have grown beyond the 50-event limit
    or are older than 48 hours.

    Runs every day at 03:00 via Celery Beat.
    """
    try:
        from django.core.cache import cache
        from planpals.models import User

        cleaned = 0
        user_ids = list(
            User.objects.values_list('id', flat=True)
            .order_by('id')[:5000]       # Process in chunks
        )

        for uid in user_ids:
            cache_key = f"offline_events:{uid}"
            events = cache.get(cache_key)
            if events is None:
                continue

            if not events:
                cache.delete(cache_key)
                cleaned += 1
                continue

            # Keep only last 50 events less than 48 hours old
            cutoff = (timezone.now() - timedelta(hours=48)).isoformat()
            filtered = [
                e for e in events[-50:]
                if e.get('timestamp', '') >= cutoff
            ]

            if len(filtered) != len(events):
                if filtered:
                    cache.set(cache_key, filtered, timeout=86400)
                else:
                    cache.delete(cache_key)
                cleaned += 1

        logger.info(f"Offline events cleanup: {cleaned} cache entries trimmed")
        return {'status': 'completed', 'cleaned_entries': cleaned}

    except SoftTimeLimitExceeded:
        logger.error("Offline events cleanup timed out")
        return {'status': 'timeout'}

    except Exception as exc:
        logger.error(f"Offline events cleanup failed: {exc}")
        raise self.retry(exc=exc)


# ---------------------------------------------------------------------------
# Task 3: Cleanup invalid FCM tokens (weekly)
# ---------------------------------------------------------------------------

@shared_task(
    bind=True,
    name='planpals.shared.analytics_tasks.cleanup_invalid_fcm_tokens_task',
    max_retries=1,
    default_retry_delay=600,
    soft_time_limit=300,
    rate_limit='1/d',
    acks_late=True,
)
def cleanup_invalid_fcm_tokens_task(self) -> Dict[str, Any]:
    """
    Detect and clear FCM tokens that haven't been refreshed in 60 days.

    Runs weekly (Sunday 04:00) via Celery Beat.  Stale tokens waste FCM
    quota and slow down batch sends.
    """
    try:
        from planpals.models import User

        cutoff = timezone.now() - timedelta(days=60)

        # Users with tokens who haven't logged in for 60+ days
        stale_qs = User.objects.filter(
            fcm_token__isnull=False,
            last_login__lt=cutoff,
        ).exclude(fcm_token='')

        stale_count = stale_qs.count()

        if stale_count > 0:
            stale_qs.update(fcm_token=None)
            logger.info(f"Cleared {stale_count} stale FCM tokens")
        else:
            logger.info("No stale FCM tokens found")

        return {'status': 'completed', 'cleared_tokens': stale_count}

    except SoftTimeLimitExceeded:
        logger.error("FCM token cleanup timed out")
        return {'status': 'timeout'}

    except Exception as exc:
        logger.error(f"FCM token cleanup failed: {exc}")
        raise self.retry(exc=exc)
