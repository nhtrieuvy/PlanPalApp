"""
Notification Celery tasks.
"""
from __future__ import annotations

import logging
from datetime import timedelta

from celery import shared_task
from celery.exceptions import SoftTimeLimitExceeded
from django.core.cache import cache
from django.utils import timezone

from planpals.audit.domain.entities import AuditAction
from planpals.notifications.application import factories as notification_factories
from planpals.notifications.domain.entities import NotificationType

logger = logging.getLogger(__name__)


@shared_task(
    bind=True,
    name='planpals.notifications.infrastructure.tasks.send_notification_task',
    max_retries=3,
    autoretry_for=(Exception,),
    retry_backoff=True,
    retry_jitter=True,
    retry_backoff_max=120,
    soft_time_limit=60,
    acks_late=True,
)
def send_notification_task(
    self,
    user_id: str,
    notification_type: str,
    data: dict | None = None,
    send_push: bool = True,
):
    try:
        service = notification_factories.get_notification_service()
        notification = service.notify(
            user_id=user_id,
            notification_type=notification_type,
            data=data or {},
            send_push=send_push,
        )
        return {'status': 'sent', 'notification_id': str(notification.id)}
    except SoftTimeLimitExceeded:
        logger.error("send_notification_task timed out for user=%s", user_id)
        return {'status': 'timeout'}


@shared_task(
    bind=True,
    name='planpals.notifications.infrastructure.tasks.fanout_group_notification_task',
    max_retries=3,
    autoretry_for=(Exception,),
    retry_backoff=True,
    retry_jitter=True,
    retry_backoff_max=120,
    soft_time_limit=90,
    acks_late=True,
)
def fanout_group_notification_task(
    self,
    notification_type: str,
    data: dict | None = None,
    recipient_user_ids: list[str] | None = None,
    exclude_user_ids: list[str] | None = None,
    send_push: bool = True,
):
    try:
        service = notification_factories.get_notification_service()
        notifications = service.notify_many(
            user_ids=recipient_user_ids or [],
            notification_type=notification_type,
            data=data or {},
            send_push=send_push,
            exclude_user_ids=exclude_user_ids or [],
        )
        return {'status': 'sent', 'count': len(notifications)}
    except SoftTimeLimitExceeded:
        logger.error("fanout_group_notification_task timed out for type=%s", notification_type)
        return {'status': 'timeout'}


@shared_task(
    bind=True,
    name='planpals.notifications.infrastructure.tasks.process_audit_log_notification_task',
    max_retries=3,
    autoretry_for=(Exception,),
    retry_backoff=True,
    retry_jitter=True,
    retry_backoff_max=120,
    soft_time_limit=90,
    acks_late=True,
)
def process_audit_log_notification_task(self, audit_log_id: str):
    from planpals.audit.infrastructure.models import AuditLog
    from planpals.groups.infrastructure.models import GroupMembership
    from planpals.plans.infrastructure.models import Plan

    try:
        audit_log = AuditLog.objects.select_related('user').get(id=audit_log_id)
    except AuditLog.DoesNotExist:
        return {'status': 'skipped', 'reason': 'audit_log_not_found'}

    actor_name = 'Someone'
    if audit_log.user:
        actor_name = audit_log.user.get_full_name() or audit_log.user.username

    metadata = audit_log.metadata or {}
    recipients: list[str] = []
    notification_type: str | None = None
    data: dict = {'actor_name': actor_name}

    if audit_log.action == AuditAction.JOIN_GROUP.value:
        recipients = list(
            GroupMembership.objects.filter(
                group_id=audit_log.resource_id,
                role=GroupMembership.ADMIN,
            )
            .exclude(user_id=audit_log.user_id)
            .values_list('user_id', flat=True)
        )
        notification_type = NotificationType.GROUP_JOIN.value
        data.update(
            {
                'group_id': str(audit_log.resource_id),
                'group_name': metadata.get('group_name') or _get_group_name(audit_log.resource_id),
                'membership_event': 'join',
            }
        )

    elif audit_log.action == AuditAction.LEAVE_GROUP.value:
        recipients = list(
            GroupMembership.objects.filter(
                group_id=audit_log.resource_id,
                role=GroupMembership.ADMIN,
            )
            .exclude(user_id=audit_log.user_id)
            .values_list('user_id', flat=True)
        )
        notification_type = NotificationType.GROUP_JOIN.value
        data.update(
            {
                'group_id': str(audit_log.resource_id),
                'group_name': metadata.get('group_name') or _get_group_name(audit_log.resource_id),
                'membership_event': 'leave',
            }
        )

    elif audit_log.action in {
        AuditAction.CREATE_PLAN.value,
        AuditAction.UPDATE_PLAN.value,
        AuditAction.DELETE_PLAN.value,
    }:
        if audit_log.action == AuditAction.DELETE_PLAN.value:
            recipients = [
                str(user_id)
                for user_id in (metadata.get('participant_ids') or [])
                if str(user_id) != str(audit_log.user_id)
            ]
        else:
            try:
                plan = Plan.objects.select_related('group').get(id=audit_log.resource_id)
                recipients = [
                    str(user_id)
                    for user_id in plan.get_members().values_list('id', flat=True)
                    if str(user_id) != str(audit_log.user_id)
                ]
            except Plan.DoesNotExist:
                recipients = []

        notification_type = NotificationType.PLAN_UPDATED.value
        change_type = {
            AuditAction.CREATE_PLAN.value: 'created',
            AuditAction.UPDATE_PLAN.value: 'updated',
            AuditAction.DELETE_PLAN.value: 'deleted',
        }[audit_log.action]
        data.update(
            {
                'plan_id': str(audit_log.resource_id),
                'plan_title': metadata.get('title') or 'Plan',
                'change_type': change_type,
            }
        )

    elif audit_log.action == AuditAction.CHANGE_ROLE.value:
        target_user_id = metadata.get('target_user_id')
        if target_user_id:
            recipients = [str(target_user_id)]
            notification_type = NotificationType.ROLE_CHANGED.value
            data.update(
                {
                    'group_id': str(audit_log.resource_id),
                    'group_name': _get_group_name(audit_log.resource_id),
                    'new_role': metadata.get('new_role'),
                }
            )

    elif audit_log.action == AuditAction.DELETE_GROUP.value:
        recipients = [
            str(user_id)
            for user_id in (metadata.get('member_ids') or [])
            if str(user_id) != str(audit_log.user_id)
        ]
        notification_type = NotificationType.GROUP_JOIN.value
        data.update(
            {
                'group_id': str(audit_log.resource_id),
                'group_name': metadata.get('group_name') or 'Group',
                'membership_event': 'deleted',
            }
        )

    if not notification_type or not recipients:
        return {'status': 'skipped', 'reason': 'no_targets'}

    fanout_group_notification_task.delay(
        notification_type=notification_type,
        data=data,
        recipient_user_ids=recipients,
        exclude_user_ids=[str(audit_log.user_id)] if audit_log.user_id else [],
        send_push=True,
    )
    return {'status': 'queued', 'type': notification_type, 'recipient_count': len(recipients)}


@shared_task(
    bind=True,
    name='planpals.notifications.infrastructure.tasks.dispatch_plan_reminders_task',
    soft_time_limit=120,
    acks_late=True,
)
def dispatch_plan_reminders_task(self):
    from planpals.plans.infrastructure.models import Plan

    service = notification_factories.get_notification_service()
    now = timezone.now()
    reminder_window_end = now + timedelta(hours=24)

    plans = (
        Plan.objects.filter(
            status='upcoming',
            start_date__gte=now,
            start_date__lte=reminder_window_end,
        )
        .select_related('group', 'creator')
        .prefetch_related('group__members')
    )

    notifications_created = 0
    for plan in plans:
        if plan.group_id:
            recipient_ids = list(plan.group.members.values_list('id', flat=True))
        else:
            recipient_ids = [plan.creator_id]

        pending_recipients = []
        for recipient_id in recipient_ids:
            cache_key = f'plan_reminder:{plan.id}:{recipient_id}:{plan.start_date.isoformat()}'
            if cache.add(cache_key, True, timeout=60 * 60 * 36):
                pending_recipients.append(str(recipient_id))

        if not pending_recipients:
            continue

        service.notify_many(
            user_ids=pending_recipients,
            notification_type=NotificationType.PLAN_REMINDER.value,
            data={
                'plan_id': str(plan.id),
                'plan_title': plan.title,
                'start_date': plan.start_date.isoformat(),
                'start_date_display': plan.start_date.strftime('%H:%M %d/%m/%Y'),
            },
            send_push=True,
        )
        notifications_created += len(pending_recipients)

    return {'status': 'sent', 'count': notifications_created}


def _get_group_name(group_id) -> str:
    from planpals.groups.infrastructure.models import Group

    try:
        return Group.objects.only('name').get(id=group_id).name
    except Group.DoesNotExist:
        return 'your group'
