from __future__ import annotations

import logging

from celery import shared_task
from celery.exceptions import SoftTimeLimitExceeded

from planpals.budgets.application.factories import get_budget_service

logger = logging.getLogger(__name__)


@shared_task(
    bind=True,
    name='planpals.budgets.infrastructure.tasks.process_expense_notifications_task',
    max_retries=3,
    autoretry_for=(Exception,),
    retry_backoff=True,
    retry_jitter=True,
    retry_backoff_max=120,
    soft_time_limit=60,
    acks_late=True,
)
def process_expense_notifications_task(self, expense_id: str):
    try:
        return get_budget_service().process_expense_notifications(expense_id)
    except SoftTimeLimitExceeded:
        logger.error(
            "process_expense_notifications_task timed out for expense=%s",
            expense_id,
        )
        return {'status': 'timeout'}
