"""
Convenience functions for publishing plan and activity real-time events.

These functions wrap the shared RealtimeEventPublisher to provide
a simple API for plan-specific event publishing.
"""
from planpals.shared.events import RealtimeEvent, EventType, EventPriority
from planpals.shared.realtime_publisher import event_publisher


# ── Plan Event Helpers ──────────────────────────────────────────────

def publish_plan_created(plan_id: str, title: str, plan_type: str, status: str,
                        creator_id: str, group_id: str = None, is_public: bool = False,
                        start_date: str = None, end_date: str = None):
    """Publish plan created event"""
    event = RealtimeEvent(
        event_type=EventType.PLAN_CREATED,
        plan_id=plan_id,
        user_id=creator_id,
        group_id=group_id,
        data={
            'plan_id': plan_id,
            'title': title,
            'plan_type': plan_type,
            'status': status,
            'creator_id': creator_id,
            'group_id': group_id,
            'is_public': is_public,
            'start_date': start_date,
            'end_date': end_date,
            'initiator_id': creator_id
        }
    )
    
    return event_publisher.publish_event(event, send_push=False)


def publish_plan_updated(plan_id: str, title: str, status: str, last_updated: str):
    """Publish plan updated event"""
    event = RealtimeEvent(
        event_type=EventType.PLAN_UPDATED,
        plan_id=plan_id,
        data={
            'plan_id': plan_id,
            'title': title,
            'status': status,
            'last_updated': last_updated
        }
    )
    
    return event_publisher.publish_event(event, send_push=False)


def publish_plan_status_changed(plan_id: str, old_status: str, new_status: str,
                               title: str, initiator_id: str = None):
    """Publish plan status change event"""
    event = RealtimeEvent(
        event_type=EventType.PLAN_STATUS_CHANGED,
        plan_id=plan_id,
        data={
            'plan_id': plan_id,
            'title': title,
            'old_status': old_status,
            'new_status': new_status,
            'initiator_id': initiator_id
        }
    )
    
    return event_publisher.publish_event(event, priority=EventPriority.HIGH)


def publish_plan_deleted(plan_id: str, title: str):
    """Publish plan deleted event"""
    event = RealtimeEvent(
        event_type=EventType.PLAN_DELETED,
        plan_id=plan_id,
        data={
            'plan_id': plan_id,
            'title': title
        }
    )
    
    return event_publisher.publish_event(event)


# ── Activity Event Helpers ──────────────────────────────────────────

def publish_activity_created(
    plan_id: str,
    activity_id: str,
    title: str,
    activity_type: str,
    version: int = 1,
    start_time: str = None,
    end_time: str = None,
    location_name: str = None,
    estimated_cost: float = None,
    activity: dict | None = None,
):
    """Publish activity created event"""
    event = RealtimeEvent(
        event_type=EventType.ACTIVITY_CREATED,
        plan_id=plan_id,
        data={
            'activity_id': activity_id,
            'plan_id': plan_id,
            'title': title,
            'activity_type': activity_type,
            'version': version,
            'start_time': start_time,
            'end_time': end_time,
            'location_name': location_name,
            'estimated_cost': estimated_cost,
            'activity': activity,
        }
    )
    
    return event_publisher.publish_event(event)


def publish_activity_updated(
    plan_id: str,
    activity_id: str,
    title: str,
    is_completed: bool,
    last_updated: str,
    version: int,
    updated_fields: list[str] | None = None,
    updated_by: str | None = None,
    updated_by_name: str | None = None,
    activity: dict | None = None,
):
    """Publish activity updated event"""
    event = RealtimeEvent(
        event_type=EventType.ACTIVITY_UPDATED,
        plan_id=plan_id,
        data={
            'activity_id': activity_id,
            'plan_id': plan_id,
            'title': title,
            'is_completed': is_completed,
            'last_updated': last_updated,
            'version': version,
            'updated_fields': updated_fields or [],
            'updated_by': updated_by,
            'updated_by_name': updated_by_name,
            'activity': activity,
        }
    )
    
    return event_publisher.publish_event(event)


def publish_activity_completed(
    plan_id: str,
    activity_id: str,
    title: str,
    completed_by: str = None,
    version: int | None = None,
    completed_by_name: str | None = None,
    activity: dict | None = None,
):
    """Publish activity completion event"""
    event = RealtimeEvent(
        event_type=EventType.ACTIVITY_COMPLETED,
        plan_id=plan_id,
        data={
            'activity_id': activity_id,
            'title': title,
            'completed_by': completed_by,
            'completed_by_name': completed_by_name,
            'initiator_id': completed_by,
            'version': version,
            'activity': activity,
        }
    )
    
    return event_publisher.publish_event(event, priority=EventPriority.NORMAL)


def publish_activity_deleted(plan_id: str, activity_id: str, title: str):
    """Publish activity deleted event"""
    event = RealtimeEvent(
        event_type=EventType.ACTIVITY_DELETED,
        plan_id=plan_id,
        data={
            'activity_id': activity_id,
            'plan_id': plan_id,
            'title': title
        }
    )
    
    return event_publisher.publish_event(event)
