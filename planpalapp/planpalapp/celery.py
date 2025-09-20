from __future__ import absolute_import, unicode_literals
import os
from celery import Celery
from celery.signals import worker_ready
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

@worker_ready.connect
def worker_ready_handler(sender, **kwargs):
    """Log worker configuration when ready"""
    print(f"[WORKER READY] Worker {sender.hostname} is ready")
    print(f"[WORKER READY] Queues: {getattr(sender.consumer.task_consumer, 'queues', 'unknown')}")
    print(f"[WORKER READY] Registered tasks: {list(sender.app.tasks.keys())}")

@app.task(bind=True)
def debug_task(self):
    print(f'Request: {self.request!r}')
