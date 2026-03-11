from __future__ import absolute_import, unicode_literals
import os
from celery import Celery
from celery.signals import worker_ready, task_failure, task_retry, task_success
import logging

logger = logging.getLogger(__name__)

# Set default Django settings module for 'celery' program
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'planpalapp.settings')

app = Celery('planpalapp')

# Using a string here means the worker doesn't have to serialize
# the configuration object to child processes.
app.config_from_object('django.conf:settings', namespace='CELERY')

# Load task modules from all registered Django app configs.
app.autodiscover_tasks()

# Also discover tasks in shared modules that aren't auto-discovered
app.autodiscover_tasks([
    'planpals.shared',
    'planpals.chat.infrastructure',
])


# ============================================================================
# Signal handlers — observability & monitoring
# ============================================================================

@worker_ready.connect
def worker_ready_handler(sender, **kwargs):
    """Log worker configuration when ready"""
    print(f"[WORKER READY] Worker {sender.hostname} is ready")
    try:
        consumer = getattr(sender, 'consumer', None)
        if consumer:
            task_consumer = getattr(consumer, 'task_consumer', None)
            queues = getattr(task_consumer, 'queues', 'unknown') if task_consumer else 'unknown'
        else:
            queues = 'unknown'
        print(f"[WORKER READY] Queues: {queues}")
    except Exception as e:
        print(f"[WORKER READY] Queues: (unable to determine - {e})")
    print(f"[WORKER READY] Registered tasks: {list(sender.app.tasks.keys())}")


@task_failure.connect
def task_failure_handler(sender=None, task_id=None, exception=None,
                         traceback=None, einfo=None, **kwargs):
    """Log task failures for monitoring / alerting."""
    task_name = getattr(sender, 'name', 'unknown')
    logger.error(
        f"[TASK FAILED] {task_name} (id={task_id}): {exception}",
        exc_info=einfo,
    )


@task_retry.connect
def task_retry_handler(sender=None, request=None, reason=None, einfo=None, **kwargs):
    """Log task retries."""
    task_name = getattr(sender, 'name', 'unknown')
    logger.warning(
        f"[TASK RETRY] {task_name} (id={getattr(request, 'id', '?')}): {reason}"
    )


@task_success.connect
def task_success_handler(sender=None, result=None, **kwargs):
    """Log successful task completion (debug level to reduce noise)."""
    task_name = getattr(sender, 'name', 'unknown')
    logger.debug(f"[TASK OK] {task_name} completed successfully")


@app.task(bind=True)
def debug_task(self):
    print(f'Request: {self.request!r}')
