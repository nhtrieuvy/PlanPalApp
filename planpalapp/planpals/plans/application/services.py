import datetime
import re
import logging
from typing import Dict, List, Optional, Tuple, Any

from planpals.shared.base_service import BaseService
from planpals.shared.events import RealtimeEvent, EventType

# Commands & factories — thin delegation layer
from planpals.plans.application.commands import (
    CreatePlanCommand,
    UpdatePlanCommand,
    DeletePlanCommand,
    JoinPlanCommand,
    AddActivityCommand,
    UpdateActivityCommand,
    RemoveActivityCommand,
    ToggleActivityCompletionCommand,
)
from planpals.plans.application import factories as plan_factories

logger = logging.getLogger(__name__)


class PlanService(BaseService): 
       
    @classmethod
    def create_plan(cls, creator, title: str, description: str = "",
                   plan_type: str = 'personal', group=None,
                   start_date=None, end_date=None, budget=None,
                   is_public: bool = False):
        """Delegate to CreatePlanHandler, then schedule Celery tasks."""
        cmd = CreatePlanCommand(
            creator_id=creator.id,
            title=title,
            description=description,
            plan_type=plan_type,
            group_id=group.id if group else None,
            start_date=start_date,
            end_date=end_date,
            is_public=is_public,
            budget=budget,
        )
        handler = plan_factories.get_create_plan_handler()
        plan = handler.handle(cmd)

        # Infrastructure concern: schedule Celery tasks (not in handler)
        plan_factories.get_task_scheduler().schedule_plan_tasks(plan)

        cls.log_operation("plan_created", {
            'plan_id': plan.id,
            'creator': creator.id,
            'plan_type': plan_type,
            'group_id': group.id if group else None
        })

        return plan

    @classmethod
    def update_plan(cls, plan, data: Dict[str, Any], user=None):
        """Delegate to UpdatePlanHandler, then reschedule Celery tasks."""
        # Determine whether schedule-affecting fields are changing
        old_start = getattr(plan, 'start_date', None)
        old_end = getattr(plan, 'end_date', None)
        new_start = data.get('start_date', old_start)
        new_end = data.get('end_date', old_end)

        cmd = UpdatePlanCommand(
            plan_id=plan.id,
            user_id=user.id if user else plan.creator_id,
            **{k: v for k, v in data.items() if k in (
                'title', 'description', 'start_date', 'end_date',
                'is_public', 'cover_image', 'destination', 'budget', 'notes',
            )}
        )
        handler = plan_factories.get_update_plan_handler()
        plan = handler.handle(cmd)

        # Infrastructure concern: reschedule Celery tasks if dates changed
        task_scheduler = plan_factories.get_task_scheduler()
        if (('start_date' in data and new_start != old_start) or
                ('end_date' in data and new_end != old_end)):
            try:
                task_scheduler.revoke_scheduled_tasks(plan)
            except Exception as e:
                logger.warning(f"Failed to revoke existing scheduled tasks for plan {plan.id}: {e}")
            try:
                task_scheduler.schedule_plan_tasks(plan)
            except Exception as e:
                logger.warning(f"Failed to schedule tasks after updating plan {plan.id}: {e}")

        cls.log_operation("plan_updated", {
            'plan_id': str(plan.id),
            'updated_by': str(user.id) if user else None,
            'updated_fields': list(data.keys())
        })

        plan = plan_factories.get_plan_repo().refresh(plan)
        return plan
    
    @classmethod
    def add_activity_to_plan(cls, plan, user, activity_data: Dict[str, Any]):
        """Delegate to AddActivityHandler."""
        cmd = AddActivityCommand(
            plan_id=plan.id,
            user_id=user.id,
            title=activity_data['title'],
            description=activity_data.get('description', ''),
            activity_type=activity_data.get('activity_type', 'other'),
            start_time=activity_data.get('start_time'),
            end_time=activity_data.get('end_time'),
            estimated_cost=activity_data.get('estimated_cost'),
            location_name=activity_data.get('location_name', ''),
            location_address=activity_data.get('location_address', ''),
            notes=activity_data.get('notes', ''),
        )
        handler = plan_factories.get_add_activity_handler()
        activity = handler.handle(cmd)

        cls.log_operation("activity_added_to_plan", {
            'plan_id': plan.id,
            'activity_id': activity.id,
            'user_id': user.id
        })

        return activity
    
    @classmethod
    def add_activity_with_place(cls, plan, title: str, start_time, end_time, 
                               place_id: str = None, **extra_fields):        
        activity_data = {
            'title': title,
            'start_time': start_time,
            'end_time': end_time,
            **{k: v for k, v in extra_fields.items() 
               if k in ['description', 'activity_type', 'estimated_cost', 
                        'location_name', 'location_address', 'notes']}
        }
        
        if place_id:
            activity_data['location_name'] = f"Place ID: {place_id}"
        
        activity_repo = plan_factories.get_activity_repo()
        activity = activity_repo.save_new_from_dict(plan.id, activity_data)
        
        cls.log_operation("activity_added_with_place", {
            'plan_id': plan.id,
            'activity_id': activity.id,
            'place_id': place_id
        })
        
        return activity

    
    @classmethod
    def start_trip(cls, plan, user=None, force: bool = False):
        now = datetime.datetime.now(datetime.timezone.utc)

        if plan.status != 'upcoming' and not force:
            raise ValueError(f"Cannot start trip in status: {plan.status}")
        
        if not force and plan.start_date and now < plan.start_date:
            raise ValueError("Trip start time has not been reached yet")
        
        plan_repo = plan_factories.get_plan_repo()
        success, updated_plan = plan_repo.update_status_atomic(plan.id, 'upcoming', 'ongoing')
        
        if not success and not force:
            raise ValueError("Plan status was changed by another operation")
        
        if success and updated_plan:
            plan = updated_plan
        else:
            plan = plan_repo.refresh(plan)
        
        try:
            plan_factories.get_task_scheduler().schedule_completion_task(plan)
        except Exception as e:
            logger.warning(f"Failed to schedule completion task for plan {plan.id}: {e}")
        
        cls.log_operation("trip_started", {
            'plan_id': str(plan.id),
            'user_id': str(user.id) if user else None,
            'forced': force,
            'timestamp': now.isoformat()
        })
        
        try:
            publisher = plan_factories.get_realtime_publisher()
            event = RealtimeEvent(
                event_type=EventType.PLAN_STATUS_CHANGED,
                plan_id=str(plan.id),
                user_id=str(user.id) if user else None,
                group_id=str(plan.group_id) if plan.group_id else None,
                timestamp=now.isoformat(),
                data={
                    'plan_id': str(plan.id),
                    'title': plan.title,
                    'old_status': 'upcoming',
                    'new_status': 'ongoing',
                    'started_by': str(user.id) if user else 'system',
                    'started_by_name': user.get_full_name() or user.username if user else 'System',
                    'timestamp': now.isoformat(),
                    'forced': force,
                    'initiator_id': str(user.id) if user else None
                }
            )
            publisher.publish_event(event, send_push=True)
        except Exception as e:
            logger.warning(f"Failed to publish start event for plan {plan.id}: {e}")
        
        return plan
    
    @classmethod
    def complete_trip(cls, plan, user=None, force: bool = False):
        now = datetime.datetime.now(datetime.timezone.utc)

        if plan.status != 'ongoing' and not force:
            raise ValueError(f"Cannot complete trip in status: {plan.status}")
        
        if not force and plan.end_date and now < plan.end_date:
            raise ValueError("Trip end time has not been reached yet")
        
        plan_repo = plan_factories.get_plan_repo()
        success, updated_plan = plan_repo.update_status_atomic(plan.id, 'ongoing', 'completed')
        
        if not success and not force:
            raise ValueError("Plan status was changed by another operation")
        
        if success and updated_plan:
            plan = updated_plan
        else:
            plan = plan_repo.refresh(plan)
        
        try:
            plan_factories.get_task_scheduler().revoke_plan_tasks(plan)
        except Exception as e:
            logger.warning(f"Failed to revoke tasks for plan {plan.id}: {e}")
        
        cls.log_operation("trip_completed", {
            'plan_id': str(plan.id),
            'user_id': str(user.id) if user else None,
            'forced': force,
            'timestamp': now.isoformat()
        })
        
        try:
            publisher = plan_factories.get_realtime_publisher()
            event = RealtimeEvent(
                event_type=EventType.PLAN_STATUS_CHANGED,
                plan_id=str(plan.id),
                user_id=str(user.id) if user else None,
                group_id=str(plan.group_id) if plan.group_id else None,
                timestamp=now.isoformat(),
                data={
                    'plan_id': str(plan.id),
                    'title': plan.title,
                    'old_status': 'ongoing',
                    'new_status': 'completed',
                    'completed_by': str(user.id) if user else 'system',
                    'completed_by_name': user.get_full_name() or user.username if user else 'System',
                    'timestamp': now.isoformat(),
                    'forced': force,
                    'initiator_id': str(user.id) if user else None
                }
            )
            publisher.publish_event(event, send_push=True)
        except Exception as e:
            logger.warning(f"Failed to publish complete event for plan {plan.id}: {e}")
        
        return plan
    
    @classmethod
    def cancel_trip(cls, plan, user=None, reason: str = None, force: bool = False):
        now = datetime.datetime.now(datetime.timezone.utc)

        if user and not cls.can_edit_plan(plan, user):
            raise ValueError("Permission denied to cancel this plan")
        
        if plan.status in ['cancelled', 'completed'] and not force:
            raise ValueError(f"Cannot cancel plan that is already {plan.status}")
        
        plan_repo = plan_factories.get_plan_repo()
        plan_repo.update_fields(plan.id, status='cancelled')
        plan = plan_repo.refresh(plan)
        
        # Revoke any scheduled tasks
        try:
            plan_factories.get_task_scheduler().revoke_plan_tasks(plan)
        except Exception as e:
            logger.warning(f"Failed to revoke tasks for plan {plan.id}: {e}")
        
        cls.log_operation("trip_cancelled", {
            'plan_id': str(plan.id),
            'user_id': str(user.id) if user else None,
            'reason': reason,
            'forced': force,
            'timestamp': now.isoformat()
        })
        
        return plan
    
    @classmethod
    def can_view_plan(cls, plan, user) -> bool:
        if plan.is_public:
            return True
        
        if plan.creator == user:
            return True
        
        return user in plan.collaborators
    
    @classmethod
    def can_edit_plan(cls, plan, user) -> bool:
        if plan.creator == user:
            return True
        
        if plan.is_group_plan() and plan.group:
            return plan.group.is_admin(user)
        
        return False
    
    @classmethod
    def get_plan_statistics(cls, plan) -> Dict[str, Any]:
        plan_repo = plan_factories.get_plan_repo()
        activity_repo = plan_factories.get_activity_repo()

        plan_with_stats = plan_repo.get_by_id_with_stats(plan.id)
        
        activities_count = plan_with_stats.activities_count
        total_cost = plan_with_stats.total_estimated_cost
        
        completed_activities = activity_repo.count_completed(plan.id)
        completion_rate = (completed_activities / activities_count * 100) if activities_count > 0 else 0
        
        return {
            'activities': {
                'total': activities_count,
                'completed': completed_activities,
                'completion_rate': completion_rate
            },
            'budget': {
                'estimated': float(total_cost),
                'over_budget': False
            },
            'duration': {
                'days': plan.duration_days,
                'start_date': plan.start_date,
                'end_date': plan.end_date
            },
            'status': plan.status,
            'collaboration': {
                'type': plan.plan_type,
                'group_id': plan.group.id if plan.group else None,
                'collaborators_count': len(plan.collaborators)
            }
        }
    
    @classmethod
    def get_plan_schedule(cls, plan, user) -> Dict[str, Any]:      
        activity_repo = plan_factories.get_activity_repo()
        activities = activity_repo.get_activities_for_plan(plan.id)
        
        schedule_by_date = {}
        for activity in activities:
            if activity.start_time:
                activity_date = activity.start_time.date()
                date_str = activity_date.strftime('%Y-%m-%d')
                
                if date_str not in schedule_by_date:
                    schedule_by_date[date_str] = {
                        'date': date_str,
                        'activities': []
                    }
                
                # Lightweight summary — no serializer dependency
                activity_data = {
                    'id': str(activity.id),
                    'title': activity.title,
                    'activity_type': getattr(activity, 'activity_type', 'other'),
                    'start_time': activity.start_time.isoformat() if activity.start_time else None,
                    'end_time': activity.end_time.isoformat() if activity.end_time else None,
                    'is_completed': getattr(activity, 'is_completed', False),
                    'location_name': getattr(activity, 'location_name', ''),
                    'estimated_cost': str(getattr(activity, 'estimated_cost', 0) or 0),
                }
                schedule_by_date[date_str]['activities'].append(activity_data)
        
        total_activities = activity_repo.count_total(plan.id)
        completed_activities = activity_repo.count_completed(plan.id)
        
        total_duration = 0
        for activity in activities:
            if activity.start_time and activity.end_time:
                duration_delta = activity.end_time - activity.start_time
                total_duration += int(duration_delta.total_seconds() / 60)
        
        return {
            'plan_id': str(plan.id),
            'plan_title': plan.title,
            'schedule_by_date': schedule_by_date,
            'statistics': {
                'total_activities': total_activities,
                'completed_activities': completed_activities,
                'completion_rate': (completed_activities / total_activities * 100) if total_activities > 0 else 0,
                'total_duration_minutes': total_duration,
                'total_duration_display': f"{total_duration // 60}h {total_duration % 60}m" if total_duration > 0 else "0m",
                'date_range': {
                    'start_date': plan.start_date,
                    'end_date': plan.end_date,
                    'duration_days': plan.duration_days
                }
            },
            'permissions': {
                'can_edit': cls.can_edit_plan(plan, user),
                'can_add_activity': cls.can_edit_plan(plan, user)
            }
        }
    
    
    @classmethod
    def get_plans_needing_updates(cls):
        return plan_factories.get_plan_repo().get_plans_needing_status_update()
    
    @classmethod
    def revoke_scheduled_tasks(cls, plan) -> None:
        plan_factories.get_task_scheduler().revoke_scheduled_tasks(plan)
    
    @classmethod
    def refresh_plan_status(cls, plan) -> bool:
        if not cls.needs_status_update(plan):
            return False
            
        old_status = plan.status
        new_status = cls.get_expected_status(plan)
        
        if new_status != old_status:
            plan_factories.get_plan_repo().update_fields(plan.id, status=new_status)
            
            cls.log_operation("plan_status_refreshed", {
                'plan_id': plan.id,
                'old_status': old_status,
                'new_status': new_status
            })
            
            return True
        return False
    
    @classmethod
    def needs_status_update(cls, plan) -> bool:
        if not (plan.start_date and plan.end_date):
            return False
            
        now = datetime.datetime.now(datetime.timezone.utc)
        return (
            (plan.status == 'upcoming' and now >= plan.start_date) or
            (plan.status == 'ongoing' and now > plan.end_date)
        )
    
    @classmethod
    def get_expected_status(cls, plan) -> str:
        if not (plan.start_date and plan.end_date):
            return plan.status
            
        now = datetime.datetime.now(datetime.timezone.utc)
        if now < plan.start_date:
            return 'upcoming'
        elif now <= plan.end_date:
            return 'ongoing'
        else:
            return 'completed'
    
    @classmethod
    def update_activity(cls, plan, activity_id: str, user, data: Dict[str, Any]) -> Tuple[bool, str, Optional[Any]]:
        """Delegate to UpdateActivityHandler."""
        from uuid import UUID as _UUID
        cmd = UpdateActivityCommand(
            activity_id=activity_id if isinstance(activity_id, _UUID) else _UUID(str(activity_id)),
            user_id=user.id,
            **{k: v for k, v in data.items() if k in (
                'title', 'description', 'activity_type', 'start_time', 'end_time',
                'location_name', 'location_address', 'latitude', 'longitude',
                'estimated_cost', 'notes',
            )}
        )
        handler = plan_factories.get_update_activity_handler()
        try:
            activity = handler.handle(cmd)
        except Exception as e:
            return False, str(e), None

        cls.log_operation("activity_updated", {
            'plan_id': plan.id,
            'activity_id': activity_id,
            'user_id': user.id
        })

        return True, "Activity updated successfully", activity
    
    @classmethod
    def remove_activity(cls, plan, activity_id: str, user) -> Tuple[bool, str]:
        """Delegate to RemoveActivityHandler."""
        from uuid import UUID as _UUID
        cmd = RemoveActivityCommand(
            activity_id=activity_id if isinstance(activity_id, _UUID) else _UUID(str(activity_id)),
            user_id=user.id,
        )
        handler = plan_factories.get_remove_activity_handler()
        try:
            handler.handle(cmd)
        except Exception as e:
            return False, str(e)

        cls.log_operation("activity_removed", {
            'plan_id': plan.id,
            'activity_id': activity_id,
            'user_id': user.id
        })

        return True, "Activity removed from plan"
    
    @classmethod
    def toggle_activity_completion(cls, plan, activity_id: str, user) -> Tuple[bool, str, Optional[Any]]:
        """Delegate to ToggleActivityCompletionHandler."""
        from uuid import UUID as _UUID
        cmd = ToggleActivityCompletionCommand(
            activity_id=activity_id if isinstance(activity_id, _UUID) else _UUID(str(activity_id)),
            user_id=user.id,
        )
        handler = plan_factories.get_toggle_activity_completion_handler()
        try:
            activity = handler.handle(cmd)
        except Exception as e:
            return False, str(e), None

        status_text = "completed" if activity.is_completed else "incomplete"

        cls.log_operation("activity_completion_toggled", {
            'plan_id': plan.id,
            'activity_id': activity_id,
            'is_completed': activity.is_completed,
            'user_id': user.id
        })

        return True, f'Activity marked as {status_text}', activity
    
    @classmethod
    def get_joined_plans(cls, user, search: str = None):        
        return plan_factories.get_plan_repo().get_joined_group_plans(user.id, search=search)
    
    @classmethod
    def get_public_plans(cls, user, search: str = None):
        return plan_factories.get_plan_repo().get_public_plans(exclude_user_id=user.id, search=search)
    
    @classmethod
    def join_plan(cls, plan, user) -> Tuple[bool, str]:
        """Delegate to JoinPlanHandler."""
        cmd = JoinPlanCommand(
            plan_id=plan.id,
            user_id=user.id,
        )
        handler = plan_factories.get_join_plan_handler()
        try:
            handler.handle(cmd)
        except Exception as e:
            return False, str(e)

        cls.log_operation("plan_joined", {
            'plan_id': plan.id,
            'user_id': user.id,
        })

        return True, f'Successfully joined plan "{plan.title}"'


# Helper functions for attachment handling
def is_local_path(attachment_value: str) -> bool:
    if not attachment_value or not isinstance(attachment_value, str):
        return False
    
    local_patterns = [
        r'^file://',  # file:// protocol
        r'^/data/user/',  # Android app data
        r'^/storage/emulated/',  # Android storage
        r'\\AppData\\Local\\Temp\\',  # Windows temp paths
        r'^/tmp/',  # Unix temp paths
        r'^/var/folders/',  # macOS temp paths
        r'^C:\\Users\\.*\\AppData\\',  # Windows user data
        r'^/Users/.*/Library/Caches/',  # macOS cache paths
    ]
    
    for pattern in local_patterns:
        if re.search(pattern, attachment_value, re.IGNORECASE):
            return True
    
    if ('/' in attachment_value or '\\' in attachment_value) and not attachment_value.startswith(('http://', 'https://')):
        if not attachment_value.startswith('/') and '\\' not in attachment_value:
            return False
        return True
    
    return False
