"""
PlanPal Tasks - Facade Module

Re-exports all Celery tasks from their bounded context packages.
Import tasks from here for consistent task naming in CELERY_TASK_ROUTES.
"""

# Plans — scheduled lifecycle (queue: plan_status)
from planpals.plans.infrastructure.tasks import (  # noqa: F401
    start_plan_task,
    complete_plan_task,
)

# Shared — push notification delivery (queue: high_priority)
from planpals.shared.tasks import (  # noqa: F401
    send_push_notification_task,
    send_event_push_notification_task,
)

# Chat — fan-out push notifications (queue: high_priority)
from planpals.chat.infrastructure.tasks import (  # noqa: F401
    fanout_chat_push_notification_task,
)

# Notifications — in-app + push delivery
from planpals.notifications.infrastructure.tasks import (  # noqa: F401
    send_notification_task,
    fanout_group_notification_task,
    process_audit_log_notification_task,
    dispatch_plan_reminders_task,
)

# Analytics — pre-aggregated dashboard metrics
from planpals.analytics.infrastructure.tasks import (  # noqa: F401
    aggregate_daily_metrics_task,
)

# Shared — analytics & maintenance (queue: low_priority, scheduled by Beat)
from planpals.shared.analytics_tasks import (  # noqa: F401
    aggregate_daily_statistics_task,
    cleanup_expired_offline_events_task,
    cleanup_invalid_fcm_tokens_task,
)

__all__ = [
    # Plan lifecycle
    'start_plan_task',
    'complete_plan_task',
    # Push notifications
    'send_push_notification_task',
    'send_event_push_notification_task',
    # Chat fan-out
    'fanout_chat_push_notification_task',
    # Notifications
    'send_notification_task',
    'fanout_group_notification_task',
    'process_audit_log_notification_task',
    'dispatch_plan_reminders_task',
    'aggregate_daily_metrics_task',
    # Analytics
    'aggregate_daily_statistics_task',
    'cleanup_expired_offline_events_task',
    'cleanup_invalid_fcm_tokens_task',
]
