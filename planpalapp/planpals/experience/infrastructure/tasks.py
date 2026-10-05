from celery import shared_task
from django.utils import timezone

from planpals.experience.infrastructure.repositories import DjangoExperienceRepository


@shared_task(name='planpals.experience.infrastructure.tasks.expire_live_locations_task')
def expire_live_locations_task():
    expired = DjangoExperienceRepository().expire_live_locations(timezone.now())
    return {'expired': expired}
