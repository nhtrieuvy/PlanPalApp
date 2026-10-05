"""Lightweight liveness and readiness probes for the ASGI service."""

from __future__ import annotations

import time

from django.conf import settings
from django.db import connection
from django.http import JsonResponse
from django.utils import timezone
from django.views.decorators.cache import never_cache
from django.views.decorators.http import require_GET
from redis import Redis


def _timed_check(check):
    started = time.perf_counter()
    try:
        check()
        return {
            'status': 'ok',
            'latency_ms': round((time.perf_counter() - started) * 1000, 2),
        }
    except Exception:
        return {
            'status': 'unavailable',
            'latency_ms': round((time.perf_counter() - started) * 1000, 2),
        }


def _check_database() -> None:
    with connection.cursor() as cursor:
        cursor.execute('SELECT 1')
        cursor.fetchone()


def _check_redis() -> None:
    urls = {
        url
        for url in (
            settings.CACHE_REDIS_URL,
            settings.CHANNEL_REDIS_URL,
            settings.CELERY_REDIS_URL,
        )
        if url
    }
    if not urls:
        raise RuntimeError('Redis is enabled without a configured endpoint')

    for url in urls:
        client = Redis.from_url(
            url,
            socket_connect_timeout=settings.REDIS_HEALTHCHECK_TIMEOUT,
            socket_timeout=settings.REDIS_HEALTHCHECK_TIMEOUT,
        )
        try:
            client.ping()
        finally:
            client.close()


@never_cache
@require_GET
def live(request):
    return JsonResponse({
        'status': 'ok',
        'service': 'planpal-api',
        'timestamp': timezone.now().isoformat(),
    })


@never_cache
@require_GET
def ready(request):
    checks = {'database': _timed_check(_check_database)}
    if settings.USE_REDIS_CACHE or settings.USE_REDIS_CHANNELS:
        checks['redis'] = _timed_check(_check_redis)
    else:
        checks['redis'] = {
            'status': 'skipped',
            'reason': 'in-memory backend',
        }

    is_ready = all(
        result['status'] in {'ok', 'skipped'}
        for result in checks.values()
    )
    return JsonResponse(
        {
            'status': 'ok' if is_ready else 'unavailable',
            'service': 'planpal-api',
            'checks': checks,
            'timestamp': timezone.now().isoformat(),
        },
        status=200 if is_ready else 503,
    )
