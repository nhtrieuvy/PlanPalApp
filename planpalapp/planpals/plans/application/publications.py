from django.db import transaction
from django.utils import timezone

from planpals.plans.infrastructure.models import PlanPublication


@transaction.atomic
def publish_completed_plan(plan, *, destination, summary, highlight_ids):
    if plan.plan_type != 'personal' or plan.status != 'completed':
        raise ValueError('Only a completed personal plan can appear on a profile.')

    activities = list(plan.activities.filter(id__in=highlight_ids))
    if len(activities) != len(highlight_ids):
        raise ValueError('All highlights must belong to this plan.')

    by_id = {activity.id: activity for activity in activities}
    highlights = [
        {
            'source_id': str(item_id),
            'title': by_id[item_id].title,
            'place': by_id[item_id].location_name or '',
        }
        for item_id in highlight_ids
    ]
    return PlanPublication.objects.update_or_create(
        plan=plan,
        defaults={
            'destination': destination,
            'summary': summary,
            'highlights': highlights,
            'is_active': True,
            'published_at': timezone.now(),
        },
    )
