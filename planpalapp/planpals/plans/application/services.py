from django.db import transaction, models
from django.db.models import Q
from django.utils import timezone
from django.core.exceptions import ValidationError
from typing import Dict, List, Optional, Tuple, Any
import logging
import re

from celery import current_app

from planpals.shared.base_service import BaseService
from planpals.plans.infrastructure.models import Plan, PlanActivity
from planpals.models import User, Group, GroupMembership
from planpals.shared.events import RealtimeEvent, EventType
from planpals.shared.realtime_publisher import RealtimeEventPublisher
from planpals.plans.presentation.serializers import PlanActivitySummarySerializer

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
    def create_plan(cls, creator: User, title: str, description: str = "",
                   plan_type: str = 'personal', group: Group = None,
                   start_date=None, end_date=None, budget=None,
                   is_public: bool = False) -> Plan:
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
        cls._schedule_plan_tasks(plan)

        cls.log_operation("plan_created", {
            'plan_id': plan.id,
            'creator': creator.id,
            'plan_type': plan_type,
            'group_id': group.id if group else None
        })

        return plan

    @classmethod
    def update_plan(cls, plan: Plan, data: Dict[str, Any], user: User = None) -> Plan:
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
        if (('start_date' in data and new_start != old_start) or
                ('end_date' in data and new_end != old_end)):
            try:
                cls.revoke_scheduled_tasks(plan)
            except Exception as e:
                logger.warning(f"Failed to revoke existing scheduled tasks for plan {plan.id}: {e}")
            try:
                cls._schedule_plan_tasks(plan)
            except Exception as e:
                logger.warning(f"Failed to schedule tasks after updating plan {plan.id}: {e}")

        cls.log_operation("plan_updated", {
            'plan_id': str(plan.id),
            'updated_by': str(user.id) if user else None,
            'updated_fields': list(data.keys())
        })

        plan.refresh_from_db()
        return plan
    
    @classmethod
    def add_activity_to_plan(cls, plan: Plan, user: User, activity_data: Dict[str, Any]) -> PlanActivity:
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
    def add_activity_with_place(cls, plan: Plan, title: str, start_time, end_time, 
                               place_id: str = None, **extra_fields):        
        activity_data = {
            'title': title,
            'start_time': start_time,
            'end_time': end_time,
            **extra_fields
        }
        
        if place_id:
            activity_data['location_name'] = f"Place ID: {place_id}"
        
        with transaction.atomic():
            activity = PlanActivity.objects.create(
                plan=plan,
                title=title,
                start_time=start_time,
                end_time=end_time,
                **{k: v for k, v in extra_fields.items() 
                   if k in ['description', 'activity_type', 'estimated_cost', 
                           'location_name', 'location_address', 'notes']}
            )
        
        cls.log_operation("activity_added_with_place", {
            'plan_id': plan.id,
            'activity_id': activity.id,
            'place_id': place_id
        })
        
        return activity

    
    @classmethod
    def start_trip(cls, plan: Plan, user: User = None, force: bool = False):
        if plan.status != 'upcoming' and not force:
            raise ValueError(f"Cannot start trip in status: {plan.status}")
        
        if not force and plan.start_date and timezone.now() < plan.start_date:
            raise ValueError("Trip start time has not been reached yet")
        
        with transaction.atomic():
            updated_count = Plan.objects.filter(
                pk=plan.pk,
                status='upcoming'
            ).update(
                status='ongoing',
                updated_at=timezone.now()
            )
            
            if updated_count == 0 and not force:
                # Log current DB state for debugging race conditions
                try:
                    latest = Plan.objects.get(pk=plan.pk)
                    logger.warning(f"start_trip update_count=0 for plan {plan.id}: db_status={latest.status} start_date={latest.start_date}")
                except Exception:
                    logger.exception(f"start_trip failed to introspect plan {plan.id} after update_count==0")
                raise ValueError("Plan status was changed by another operation")
            
            plan.refresh_from_db()
            
            try:
                cls._schedule_completion_task(plan)
            except Exception as e:
                logger.warning(f"Failed to schedule completion task for plan {plan.id}: {e}")
        
        cls.log_operation("trip_started", {
            'plan_id': str(plan.id),
            'user_id': str(user.id) if user else None,
            'forced': force,
            'timestamp': timezone.now().isoformat()
        })
        
        def _publish_start_event():
            try:
                publisher = RealtimeEventPublisher()
                event = RealtimeEvent(
                    event_type=EventType.PLAN_STATUS_CHANGED,
                    plan_id=str(plan.id),
                    user_id=str(user.id) if user else None,
                    group_id=str(plan.group_id) if plan.group_id else None,
                    data={
                        'plan_id': str(plan.id),
                        'title': plan.title,
                        'old_status': 'upcoming',
                        'new_status': 'ongoing',
                        'started_by': str(user.id) if user else 'system',
                        'started_by_name': user.get_full_name() or user.username if user else 'System',
                        'timestamp': timezone.now().isoformat(),
                        'forced': force,
                        'initiator_id': str(user.id) if user else None
                    }
                )
                publisher.publish_event(event, send_push=True)
            except Exception as e:
                logger.warning(f"Failed to publish start event for plan {plan.id}: {e}")
        
        transaction.on_commit(_publish_start_event)
        
        return plan
    
    @classmethod
    def complete_trip(cls, plan: Plan, user: User = None, force: bool = False):
        if plan.status != 'ongoing' and not force:
            raise ValueError(f"Cannot complete trip in status: {plan.status}")
        
        if not force and plan.end_date and timezone.now() < plan.end_date:
            raise ValueError("Trip end time has not been reached yet")
        
        with transaction.atomic():
            updated_count = Plan.objects.filter(
                pk=plan.pk,
                status='ongoing'
            ).update(
                status='completed',
                updated_at=timezone.now()
            )
            
            if updated_count == 0 and not force:
                try:
                    latest = Plan.objects.get(pk=plan.pk)
                    logger.warning(f"complete_trip update_count=0 for plan {plan.id}: db_status={latest.status} end_date={latest.end_date}")
                except Exception:
                    logger.exception(f"complete_trip failed to introspect plan {plan.id} after update_count==0")
                raise ValueError("Plan status was changed by another operation")
            
            plan.refresh_from_db()
            
            try:
                cls._revoke_plan_tasks(plan)
            except Exception as e:
                logger.warning(f"Failed to revoke tasks for plan {plan.id}: {e}")
        
        cls.log_operation("trip_completed", {
            'plan_id': str(plan.id),
            'user_id': str(user.id) if user else None,
            'forced': force,
            'timestamp': timezone.now().isoformat()
        })
        
        def _publish_complete_event():
            try:
                publisher = RealtimeEventPublisher()
                event = RealtimeEvent(
                    event_type=EventType.PLAN_STATUS_CHANGED,
                    plan_id=str(plan.id),
                    user_id=str(user.id) if user else None,
                    group_id=str(plan.group_id) if plan.group_id else None,
                    data={
                        'plan_id': str(plan.id),
                        'title': plan.title,
                        'old_status': 'ongoing',
                        'new_status': 'completed',
                        'completed_by': str(user.id) if user else 'system',
                        'completed_by_name': user.get_full_name() or user.username if user else 'System',
                        'timestamp': timezone.now().isoformat(),
                        'forced': force,
                        'initiator_id': str(user.id) if user else None
                    }
                )
                publisher.publish_event(event, send_push=True)
            except Exception as e:
                logger.warning(f"Failed to publish complete event for plan {plan.id}: {e}")
        
        transaction.on_commit(_publish_complete_event)
        
        return plan
    
    @classmethod
    def cancel_trip(cls, plan: Plan, user: User = None, reason: str = None, force: bool = False):
        if user and not cls.can_edit_plan(plan, user):
            raise ValueError("Permission denied to cancel this plan")
        
        if plan.status in ['cancelled', 'completed'] and not force:
            raise ValueError(f"Cannot cancel plan that is already {plan.status}")
        
        with transaction.atomic():
            # Atomic status update
            updated_count = Plan.objects.filter(
                pk=plan.pk
            ).exclude(
                status__in=['cancelled'] if not force else []
            ).update(
                status='cancelled',
                updated_at=timezone.now()
            )
            
            if updated_count == 0 and not force:
                raise ValueError("Plan was already cancelled or status changed")
            
            # Refresh plan instance
            plan.refresh_from_db()
            
            # Revoke any scheduled tasks
            try:
                cls._revoke_plan_tasks(plan)
            except Exception as e:
                logger.warning(f"Failed to revoke tasks for plan {plan.id}: {e}")
        
        cls.log_operation("trip_cancelled", {
            'plan_id': str(plan.id),
            'user_id': str(user.id) if user else None,
            'reason': reason,
            'forced': force,
            'timestamp': timezone.now().isoformat()
        })
        
        return plan
    
    @classmethod
    def can_view_plan(cls, plan: Plan, user: User) -> bool:
        if plan.is_public:
            return True
        
        if plan.creator == user:
            return True
        
        return user in plan.collaborators
    
    @classmethod
    def can_edit_plan(cls, plan: Plan, user: User) -> bool:
        if plan.creator == user:
            return True
        
        if plan.is_group_plan() and plan.group:
            return plan.group.is_admin(user)
        
        return False
    
    @classmethod
    def get_plan_statistics(cls, plan: Plan) -> Dict[str, Any]:
        plan_with_stats = Plan.objects.with_stats().get(id=plan.id)
        
        activities_count = plan_with_stats.activities_count
        total_cost = plan_with_stats.total_estimated_cost
        
        completed_activities = plan.activities.filter(is_completed=True).count()
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
    def get_plan_schedule(cls, plan: 'Plan', user: User) -> Dict[str, Any]:      
        activities = plan.activities.order_by('start_time')
        
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
                
                # Use summary serializer for lightweight data
                activity_data = PlanActivitySummarySerializer(activity).data
                schedule_by_date[date_str]['activities'].append(activity_data)
        
        total_activities = activities.count()
        completed_activities = activities.filter(is_completed=True).count()
        
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
        return Plan.objects.plans_need_status_update()
    
    @classmethod
    def revoke_scheduled_tasks(cls, plan: Plan) -> None:
        
        old_start_id = plan.scheduled_start_task_id
        old_end_id = plan.scheduled_end_task_id
        
        for task_id in (old_start_id, old_end_id):
            if not task_id:
                continue
            try:
                current_app.control.revoke(task_id, terminate=False)
            except Exception:
                pass

        updates = {}
        if old_start_id:
            updates['scheduled_start_task_id'] = None
        if old_end_id:
            updates['scheduled_end_task_id'] = None
            
        if updates:
            Plan.objects.filter(
                pk=plan.pk,
                scheduled_start_task_id=old_start_id,
                scheduled_end_task_id=old_end_id
            ).update(**updates)
    
    @classmethod
    def refresh_plan_status(cls, plan: Plan) -> bool:
        if not cls.needs_status_update(plan):
            return False
            
        old_status = plan.status
        new_status = cls.get_expected_status(plan)
        
        if new_status != old_status:
            plan.status = new_status
            plan.save(update_fields=['status', 'updated_at'])
            
            cls.log_operation("plan_status_refreshed", {
                'plan_id': plan.id,
                'old_status': old_status,
                'new_status': new_status
            })
            
            return True
        return False
    
    @classmethod
    def needs_status_update(cls, plan: Plan) -> bool:
        if not (plan.start_date and plan.end_date):
            return False
            
        now = timezone.now()
        return (
            (plan.status == 'upcoming' and now >= plan.start_date) or
            (plan.status == 'ongoing' and now > plan.end_date)
        )
    
    @classmethod
    def get_expected_status(cls, plan: Plan) -> str:
        if not (plan.start_date and plan.end_date):
            return plan.status
            
        now = timezone.now()
        if now < plan.start_date:
            return 'upcoming'
        elif now <= plan.end_date:
            return 'ongoing'
        else:
            return 'completed'
    
    
    @classmethod
    def _schedule_plan_tasks(cls, plan: Plan):
        try:
            def _do_schedule():
                scheduled_start_id = None
                scheduled_end_id = None

                try:
                    # Lazy import to avoid circular imports
                    from planpals.plans.application.tasks import start_plan_task, complete_plan_task

                    if plan.start_date:
                        start_task = start_plan_task.apply_async(args=[str(plan.id)], eta=plan.start_date)
                        scheduled_start_id = start_task.id

                    if plan.end_date:
                        end_task = complete_plan_task.apply_async(args=[str(plan.id)], eta=plan.end_date)
                        scheduled_end_id = end_task.id

                    updates = {}
                    if scheduled_start_id:
                        updates['scheduled_start_task_id'] = scheduled_start_id
                    if scheduled_end_id:
                        updates['scheduled_end_task_id'] = scheduled_end_id

                    if updates:
                        Plan.objects.filter(pk=plan.pk).update(**updates)

                except Exception as exc:
                    cls.log_operation("task_scheduling_failed", {
                        'plan_id': plan.id,
                        'error': str(exc)
                    })

            transaction.on_commit(_do_schedule)

        except Exception as e:
            cls.log_operation("task_scheduling_failed", {
                'plan_id': plan.id,
                'error': str(e)
            })
    
    @classmethod
    def _revoke_plan_tasks(cls, plan: Plan):
        old_start_id = plan.scheduled_start_task_id
        old_end_id = plan.scheduled_end_task_id
        
        for task_id in (old_start_id, old_end_id):
            if not task_id:
                continue
            try:
                current_app.control.revoke(task_id, terminate=False)
            except Exception:
                pass

        Plan.objects.filter(pk=plan.pk).update(
            scheduled_start_task_id=None,
            scheduled_end_task_id=None
        )
    
    @classmethod
    def _schedule_completion_task(cls, plan: Plan):
        if not plan.end_date:
            return
            
        try:            
            def _do_schedule_completion():
                try:
                    from planpals.plans.application.tasks import complete_plan_task

                    if plan.scheduled_end_task_id:
                        try:
                            current_app.control.revoke(plan.scheduled_end_task_id, terminate=False)
                        except Exception:
                            pass

                    end_task = complete_plan_task.apply_async(args=[str(plan.id)], eta=plan.end_date)

                    Plan.objects.filter(pk=plan.pk).update(scheduled_end_task_id=end_task.id)
                except Exception as exc:
                    logger.warning(f"Failed to schedule completion task for plan {plan.id}: {exc}")

            transaction.on_commit(_do_schedule_completion)

        except Exception as e:
            logger.warning(f"Failed to schedule completion task: {e}")
    
    @classmethod
    def update_activity(cls, plan: 'Plan', activity_id: str, user: User, data: Dict[str, Any]) -> Tuple[bool, str, Optional['PlanActivity']]:
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
    def remove_activity(cls, plan: 'Plan', activity_id: str, user: User) -> Tuple[bool, str]:
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
    def toggle_activity_completion(cls, plan: 'Plan', activity_id: str, user: User) -> Tuple[bool, str, Optional['PlanActivity']]:
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
    def get_joined_plans(cls, user: User, search: str = None):        
        group_plans = Plan.objects.filter(
            plan_type='group',
            group__members=user
        ).exclude(creator=user).distinct()
        
        if search:
            group_plans = group_plans.filter(
                models.Q(title__icontains=search) |
                models.Q(description__icontains=search)
            )
        
        return group_plans
    
    @classmethod
    def get_public_plans(cls, user: User, search: str = None):
        
        public_plans = Plan.objects.filter(
            is_public=True,
            status__in=['upcoming', 'ongoing']
        ).exclude(creator=user)
        
        public_plans = public_plans.exclude(
            plan_type='group',
            group__members=user
        )
        
        if search:
            public_plans = public_plans.filter(
                models.Q(title__icontains=search) |
                models.Q(description__icontains=search)
            )
        
        return public_plans.order_by('-created_at')
    
    @classmethod
    def join_plan(cls, plan: 'Plan', user: User) -> Tuple[bool, str]:
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
