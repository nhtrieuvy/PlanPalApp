"""
Shared Celery Tasks — Push Notification Delivery

These tasks offload push-notification I/O (FCM calls + DB queries for target
resolution) from the synchronous request cycle into Celery workers.

Queue: high_priority
Design:
  • Idempotent — duplicate deliveries are acceptable (FCM deduplicates).
  • Simple data — only serialisable primitives (str, list, dict) as args.
  • Retry with exponential back-off on transient failures.
  • Soft time limit to prevent runaway FCM calls.
"""
import logging
from typing import Any, Dict, List, Optional

from celery import shared_task
from celery.exceptions import SoftTimeLimitExceeded

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Task 1: Direct push — caller already has FCM tokens
# ---------------------------------------------------------------------------

@shared_task(
    bind=True,
    name='planpals.shared.tasks.send_push_notification_task',
    max_retries=3,
    default_retry_delay=10,
    autoretry_for=(Exception,),
    retry_backoff=True,        # Exponential back-off: 10s, 20s, 40s
    retry_backoff_max=120,     # Cap at 2 min
    retry_jitter=True,         # ±random jitter to avoid thundering herd
    soft_time_limit=60,        # SoftTimeLimitExceeded after 60 s
    rate_limit='200/m',        # Max 200 push sends per minute per worker
    acks_late=True,            # Re-deliver on worker crash
)
def send_push_notification_task(
    self,
    fcm_tokens: List[str],
    title: str,
    body: str,
    data: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """
    Send a push notification to a list of FCM tokens.

    This is the low-level "fire" task.  Callers that already have tokens
    (e.g. chat fan-out) should use this directly.

    Args:
        fcm_tokens: List of FCM device tokens.
        title: Notification title.
        body: Notification body text.
        data: Optional extra data payload.
    """
    if not fcm_tokens:
        return {'status': 'skipped', 'reason': 'no_tokens'}

    try:
        from planpals.integrations.notification_service import NotificationService

        service = NotificationService()
        success_count, total_count = service.send_push_notification_batch(
            fcm_tokens, title, body, data,
        )

        logger.info(
            f"Push notification sent: {success_count}/{total_count} successful "
            f"(task_id={self.request.id})"
        )
        return {
            'status': 'sent',
            'success_count': success_count,
            'total_count': total_count,
            'task_id': self.request.id,
        }

    except SoftTimeLimitExceeded:
        logger.error(f"Push notification timed out (task_id={self.request.id})")
        return {'status': 'timeout', 'task_id': self.request.id}

    except Exception as exc:
        logger.error(f"Push notification failed: {exc} (task_id={self.request.id})")
        raise  # autoretry_for will handle the retry


# ---------------------------------------------------------------------------
# Task 2: Event-driven push — resolve targets from event data, then send
# ---------------------------------------------------------------------------

@shared_task(
    bind=True,
    name='planpals.shared.tasks.send_event_push_notification_task',
    max_retries=3,
    default_retry_delay=15,
    autoretry_for=(Exception,),
    retry_backoff=True,
    retry_backoff_max=120,
    retry_jitter=True,
    soft_time_limit=90,
    rate_limit='100/m',
    acks_late=True,
)
def send_event_push_notification_task(
    self,
    event_dict: Dict[str, Any],
) -> Dict[str, Any]:
    """
    Resolve notification targets from a ``RealtimeEvent`` and send push
    notifications.

    This replaces the synchronous ``_send_push_notification()`` call that
    previously ran inside ``RealtimeEventPublisher.publish_event()``.

    The event is passed as a plain dict (JSON-serialisable) — never pass
    ORM model instances to Celery tasks.

    Args:
        event_dict: ``RealtimeEvent.to_dict()`` output.
    """
    try:
        from planpals.shared.events import RealtimeEvent
        from planpals.integrations.notification_service import NotificationService

        event = RealtimeEvent.from_dict(event_dict)

        # --- Resolve notification text -----------------------------------
        notification_data = _get_notification_data(event)
        if not notification_data:
            return {'status': 'skipped', 'reason': 'no_notification_data'}

        # --- Resolve target user IDs (DB queries — now off hot path) -----
        target_user_ids = _get_notification_targets(event)
        if not target_user_ids:
            return {'status': 'skipped', 'reason': 'no_targets'}

        # --- Resolve FCM tokens ------------------------------------------
        fcm_tokens = _get_fcm_tokens(target_user_ids)
        if not fcm_tokens:
            return {'status': 'skipped', 'reason': 'no_fcm_tokens'}

        # --- Send --------------------------------------------------------
        service = NotificationService()
        success_count, total_count = service.send_push_notification_batch(
            fcm_tokens=fcm_tokens,
            title=notification_data['title'],
            body=notification_data['body'],
            data={
                'event_type': event.event_type.value,
                'event_id': event.event_id,
                'plan_id': event.plan_id or '',
                'group_id': event.group_id or '',
                **notification_data.get('extra_data', {}),
            },
        )

        logger.info(
            f"Event push sent: {success_count}/{total_count} for "
            f"{event.event_type.value} (task_id={self.request.id})"
        )
        return {
            'status': 'sent',
            'event_type': event.event_type.value,
            'success_count': success_count,
            'total_count': total_count,
            'task_id': self.request.id,
        }

    except SoftTimeLimitExceeded:
        logger.error(
            f"Event push timed out for {event_dict.get('event_type', '?')} "
            f"(task_id={self.request.id})"
        )
        return {'status': 'timeout', 'task_id': self.request.id}

    except Exception as exc:
        logger.error(
            f"Event push failed for {event_dict.get('event_type', '?')}: {exc} "
            f"(task_id={self.request.id})"
        )
        raise


# ---------------------------------------------------------------------------
# Helper functions — shared by tasks (NOT exported as tasks themselves)
# ---------------------------------------------------------------------------

def _get_notification_data(event) -> Optional[Dict[str, Any]]:
    """Map event type → notification title + body."""
    from planpals.shared.events import EventType

    event_data = event.data
    notification_map = {
        EventType.PLAN_STATUS_CHANGED: {
            'title': "Plan Status Updated",
            'body': f"'{event_data.get('title', 'Your plan')}' is now "
                    f"{event_data.get('new_status', 'updated')}",
        },
        EventType.ACTIVITY_CREATED: {
            'title': "New Activity Added",
            'body': f"New activity '{event_data.get('title', 'an activity')}' added to plan",
        },
        EventType.ACTIVITY_UPDATED: {
            'title': "Activity Updated",
            'body': f"Activity '{event_data.get('title', 'an activity')}' was updated",
        },
        EventType.ACTIVITY_COMPLETED: {
            'title': "Activity Completed",
            'body': f"'{event_data.get('title', 'An activity')}' was completed",
        },
        EventType.ACTIVITY_DELETED: {
            'title': "Activity Removed",
            'body': f"Activity '{event_data.get('title', 'an activity')}' was removed from plan",
        },
        EventType.GROUP_MEMBER_ADDED: {
            'title': "New Group Member",
            'body': (
                f"{event_data.get('username', 'Someone')} joined "
                f"{event_data.get('group_name', 'the group')}"
            ),
        },
        EventType.MESSAGE_SENT: {
            'title': "New Message",
            'body': (
                f"{event_data.get('sender_username', 'Someone')}: "
                f"{event_data.get('content', 'Sent a message')[:50]}..."
            ),
        },
        EventType.FRIEND_REQUEST: {
            'title': "Friend Request",
            'body': f"{event_data.get('from_name', 'Someone')} sent you a friend request",
        },
        EventType.FRIEND_REQUEST_ACCEPTED: {
            'title': "Friend Request Accepted",
            'body': f"{event_data.get('accepter_name', 'Someone')} accepted your friend request",
        },
    }
    return notification_map.get(event.event_type)


def _get_notification_targets(event) -> List[str]:
    """Resolve user IDs that should receive push notifications for *event*."""
    target_users: list[str] = []

    try:
        from planpals.models import Plan, Group

        if event.plan_id:
            plan = Plan.objects.select_related('group').get(id=event.plan_id)
            if plan.plan_type == 'personal':
                target_users.append(str(plan.creator_id))
            elif plan.group:
                target_users.extend(
                    str(uid) for uid in
                    plan.group.members.values_list('id', flat=True)
                )

        elif event.group_id:
            group = Group.objects.get(id=event.group_id)
            target_users.extend(
                str(uid) for uid in
                group.members.values_list('id', flat=True)
            )

        elif event.user_id:
            target_users.append(event.user_id)

        # Exclude the user who triggered the event
        initiator = event.data.get('initiator_id')
        if initiator and initiator in target_users:
            target_users.remove(initiator)

    except Exception as e:
        logger.error(f"Failed to get notification targets: {e}")

    return list(set(target_users))


def _get_fcm_tokens(user_ids: List[str]) -> List[str]:
    """Fetch FCM tokens for the given user IDs."""
    try:
        from planpals.models import User

        tokens = (
            User.objects.filter(id__in=user_ids, fcm_token__isnull=False)
            .exclude(fcm_token='')
            .values_list('fcm_token', flat=True)
        )
        return list(tokens)
    except Exception as e:
        logger.error(f"Failed to get FCM tokens: {e}")
        return []
