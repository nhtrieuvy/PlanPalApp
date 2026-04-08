"""
Analytics Celery tasks.
"""
from __future__ import annotations

from datetime import date, timedelta

from celery import shared_task
from celery.exceptions import SoftTimeLimitExceeded
from django.utils import timezone

from planpals.analytics.application.factories import get_analytics_service


@shared_task(
    bind=True,
    name='planpals.analytics.infrastructure.tasks.aggregate_daily_metrics_task',
    max_retries=2,
    default_retry_delay=300,
    soft_time_limit=300,
    acks_late=True,
)
def aggregate_daily_metrics_task(self, target_date: str | None = None):
    try:
        metric_date = (
            date.fromisoformat(target_date)
            if target_date
            else timezone.localdate() - timedelta(days=1)
        )
        metric = get_analytics_service().aggregate_daily_metrics(metric_date)
        return {
            'status': 'completed',
            'date': metric.metric_date.isoformat(),
            'active_users': metric.active_users,
            'plans_created': metric.plans_created,
            'plans_completed': metric.plans_completed,
            'group_joins': metric.group_joins,
            'notification_open_rate': metric.notification_open_rate,
        }
    except SoftTimeLimitExceeded:
        return {'status': 'timeout'}
