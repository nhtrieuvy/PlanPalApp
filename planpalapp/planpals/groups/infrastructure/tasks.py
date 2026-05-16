"""
Celery tasks for group invite lifecycle maintenance.
"""
from __future__ import annotations

import logging

from celery import shared_task
from django.utils import timezone

from planpals.notifications.domain.entities import NotificationType

logger = logging.getLogger(__name__)


@shared_task(
    bind=True,
    name='planpals.groups.infrastructure.tasks.expire_group_invites_task',
    max_retries=2,
    retry_backoff=True,
    retry_jitter=True,
    soft_time_limit=60,
    acks_late=True,
)
def expire_group_invites_task(self):
    from planpals.groups.infrastructure.models import GroupInvite
    from planpals.notifications.application.factories import get_notification_service

    now = timezone.now()
    invites = list(
        GroupInvite.objects
        .filter(is_active=True, expires_at__isnull=False, expires_at__lte=now)
        .select_related('group', 'created_by')[:1000]
    )
    if not invites:
        return {'status': 'skipped', 'reason': 'no_expired_invites'}

    invite_ids = [invite.id for invite in invites]
    GroupInvite.objects.filter(id__in=invite_ids).update(is_active=False)

    notification_service = get_notification_service()
    sent_count = 0
    for invite in invites:
        try:
            notification_service.notify(
                user_id=invite.created_by_id,
                notification_type=NotificationType.GROUP_INVITE.value,
                data={
                    'invite_event': 'expired',
                    'group_id': str(invite.group_id),
                    'group_name': invite.group.name,
                    'invite_id': str(invite.id),
                },
                send_push=True,
            )
            sent_count += 1
        except Exception as exc:
            logger.warning("Failed to notify expired invite %s: %s", invite.id, exc)

    return {'status': 'expired', 'count': len(invites), 'notifications_sent': sent_count}
