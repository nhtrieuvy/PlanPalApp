from celery import shared_task
from django.utils import timezone
from django.db import transaction
from .models import Plan


@shared_task(bind=True, max_retries=3, default_retry_delay=30)
def start_plan_task(self, plan_id):
    try:
        with transaction.atomic():
            plan = Plan.objects.select_for_update().get(pk=plan_id)
            if plan.status != 'upcoming':
                return {'skipped': True, 'status': plan.status}
            now = timezone.now()
            Plan.objects.filter(pk=plan.pk, status='upcoming').update(
                status='ongoing', updated_at=now
            )
        return {'updated': True}
    except Exception as exc:
        raise self.retry(exc=exc)


@shared_task(bind=True, max_retries=3, default_retry_delay=30)
def complete_plan_task(self, plan_id):
    try:
        with transaction.atomic():
            plan = Plan.objects.select_for_update().get(pk=plan_id)
            if plan.status != 'ongoing':
                return {'skipped': True, 'status': plan.status}
            now = timezone.now()
            Plan.objects.filter(pk=plan.pk, status='ongoing').update(
                status='completed', updated_at=now
            )
        return {'updated': True}
    except Exception as exc:
        raise self.retry(exc=exc)
