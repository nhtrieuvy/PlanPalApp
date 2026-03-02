"""
Plans Infrastructure — Domain Event Handler Registration

Bridges domain events from the plans context to the existing
realtime publisher functions. Registered during app ready().
"""
from planpals.shared._event_registry import register_event_handler

from planpals.plans.domain.events import (
    PlanCreated,
    PlanUpdated,
    PlanStatusChanged,
    PlanDeleted,
    ActivityCreated,
    ActivityUpdated,
    ActivityCompleted,
    ActivityDeleted,
)


def _handle_plan_created(event: PlanCreated):
    from planpals.shared.realtime_publisher import publish_plan_created
    publish_plan_created(
        plan_id=event.plan_id,
        title=event.title,
        plan_type=event.plan_type,
        status=event.status,
        creator_id=event.creator_id,
        group_id=event.group_id,
        is_public=event.is_public,
        start_date=event.start_date,
        end_date=event.end_date,
    )


def _handle_plan_updated(event: PlanUpdated):
    from planpals.shared.realtime_publisher import publish_plan_updated
    publish_plan_updated(
        plan_id=event.plan_id,
        title=event.title,
        status=event.status,
        last_updated=event.last_updated,
    )


def _handle_plan_status_changed(event: PlanStatusChanged):
    from planpals.shared.realtime_publisher import publish_plan_status_changed
    publish_plan_status_changed(
        plan_id=event.plan_id,
        old_status=event.old_status,
        new_status=event.new_status,
        title=event.title,
    )


def _handle_plan_deleted(event: PlanDeleted):
    from planpals.shared.realtime_publisher import publish_plan_deleted
    publish_plan_deleted(
        plan_id=event.plan_id,
        title=event.title,
    )


def _handle_activity_created(event: ActivityCreated):
    from planpals.shared.realtime_publisher import publish_activity_created
    publish_activity_created(
        plan_id=event.plan_id,
        activity_id=event.activity_id,
        title=event.title,
        activity_type=event.activity_type,
        start_time=event.start_time,
        end_time=event.end_time,
        location_name=event.location_name,
        estimated_cost=event.estimated_cost,
    )


def _handle_activity_updated(event: ActivityUpdated):
    from planpals.shared.realtime_publisher import publish_activity_updated
    publish_activity_updated(
        plan_id=event.plan_id,
        activity_id=event.activity_id,
        title=event.title,
        is_completed=event.is_completed,
        last_updated=event.last_updated,
    )


def _handle_activity_completed(event: ActivityCompleted):
    from planpals.shared.realtime_publisher import publish_activity_completed
    publish_activity_completed(
        plan_id=event.plan_id,
        activity_id=event.activity_id,
        title=event.title,
        completed_by=event.completed_by,
    )


def _handle_activity_deleted(event: ActivityDeleted):
    from planpals.shared.realtime_publisher import publish_activity_deleted
    publish_activity_deleted(
        plan_id=event.plan_id,
        activity_id=event.activity_id,
        title=event.title,
    )


def register_plan_event_handlers():
    """Register all plan domain event handlers. Call from PlanPalsConfig.ready()."""
    register_event_handler(PlanCreated, _handle_plan_created)
    register_event_handler(PlanUpdated, _handle_plan_updated)
    register_event_handler(PlanStatusChanged, _handle_plan_status_changed)
    register_event_handler(PlanDeleted, _handle_plan_deleted)
    register_event_handler(ActivityCreated, _handle_activity_created)
    register_event_handler(ActivityUpdated, _handle_activity_updated)
    register_event_handler(ActivityCompleted, _handle_activity_completed)
    register_event_handler(ActivityDeleted, _handle_activity_deleted)
