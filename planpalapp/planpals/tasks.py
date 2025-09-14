from celery import shared_task
from django.utils import timezone
import logging
from .models import Plan
from .realtime_publisher import publish_plan_status_changed

logger = logging.getLogger(__name__)


@shared_task(bind=True, max_retries=3, default_retry_delay=60)
def start_plan_task(self, plan_id):
    try:
        from .services import PlanService
        
        plan = Plan.objects.get(pk=plan_id)
        
        # Call the business logic method from service
        result = PlanService.start_trip(plan, user=None, force=False)
        
        logger.info(f"Plan {plan_id} started successfully via scheduled task")
        
        # Enhanced return with task metadata
        return {
            'plan_id': plan_id,
            'task_id': self.request.id,
            'task_name': 'start_plan_task',
            'status': 'started',
            'previous_status': 'upcoming',
            'current_status': result.status if result else 'ongoing',
            'attempt': self.request.retries,
            'timestamp': timezone.now().isoformat()
        }
        
    except Plan.DoesNotExist:
        logger.warning(f"Plan {plan_id} not found for start task")
        return {
            'plan_id': plan_id, 
            'task_id': self.request.id,
            'task_name': 'start_plan_task',
            'status': 'not_found',
            'attempt': self.request.retries,
            'timestamp': timezone.now().isoformat()
        }
        
    except ValueError as e:
        logger.info(f"Plan {plan_id} start skipped: {str(e)}")
        return {
            'plan_id': plan_id, 
            'task_id': self.request.id,
            'task_name': 'start_plan_task',
            'status': 'skipped', 
            'reason': str(e),
            'attempt': self.request.retries,
            'timestamp': timezone.now().isoformat()
        }
        
    except Exception as exc:
        logger.error(f"Unexpected error starting plan {plan_id}: {str(exc)}")
        raise self.retry(exc=exc)


@shared_task(bind=True, max_retries=3, default_retry_delay=60)
def complete_plan_task(self, plan_id):
    try:
        # Import locally to avoid circular import
        from .services import PlanService
        
        plan = Plan.objects.get(pk=plan_id)
        
        # Call the business logic method from service
        result = PlanService.complete_trip(plan, user=None, force=False)
        
        logger.info(f"Plan {plan_id} completed successfully via scheduled task")
        
        # Enhanced return with task metadata
        return {
            'plan_id': plan_id,
            'task_id': self.request.id,
            'task_name': 'complete_plan_task',
            'status': 'completed',
            'previous_status': 'ongoing', 
            'current_status': result.status if result else 'completed',
            'attempt': self.request.retries,
            'timestamp': timezone.now().isoformat()
        }
        
    except Plan.DoesNotExist:
        logger.warning(f"Plan {plan_id} not found for complete task")
        return {
            'plan_id': plan_id, 
            'task_id': self.request.id,
            'task_name': 'complete_plan_task',
            'status': 'not_found',
            'attempt': self.request.retries,
            'timestamp': timezone.now().isoformat()
        }
        
    except ValueError as e:
        logger.info(f"Plan {plan_id} completion skipped: {str(e)}")
        return {
            'plan_id': plan_id,
            'task_id': self.request.id,
            'task_name': 'complete_plan_task',
            'status': 'skipped', 
            'reason': str(e),
            'attempt': self.request.retries,
            'timestamp': timezone.now().isoformat()
        }
        
    except Exception as exc:
        logger.error(f"Unexpected error completing plan {plan_id}: {str(exc)}")
        raise self.retry(exc=exc)


@shared_task(bind=True, max_retries=2, default_retry_delay=120)
def bulk_update_plan_statuses(self):
    """
    Fallback periodic task to catch any plans that missed ETA scheduling.
    Runs every 5-10 minutes as safety net.
    Enhanced with real-time broadcasting.
    """
    try:
        from .services import PlanService
        
        # Use service method which includes realtime publishing
        stats = PlanService.bulk_update_plan_statuses()
        
        # Enhanced stats with task metadata
        stats.update({
            'task_id': self.request.id,
            'task_name': 'bulk_update_plan_statuses',
            'attempt': self.request.retries
        })
        
        if stats['total_updated'] > 0:
            logger.info(f"Bulk status update completed: {stats}")
            
        return {
            'task_id': self.request.id,
            'task_name': 'bulk_update_plan_statuses',
            'status': 'completed',
            'stats': stats,
            'attempt': self.request.retries,
            'timestamp': timezone.now().isoformat()
        }
        
    except Exception as exc:
        logger.error(f"Bulk status update failed: {str(exc)}")
        raise self.retry(exc=exc)


@shared_task(bind=True, max_retries=3, default_retry_delay=30)
def send_plan_reminder(self, plan_id, reminder_type='start_soon'):
    """
    Send reminder notifications for plans
    Args:
        plan_id: Plan ID to send reminder for
        reminder_type: 'start_soon', 'ending_soon', 'overdue'
    """
    try:
        plan = Plan.objects.get(pk=plan_id)
        
        from .realtime_publisher import event_publisher
        from .events import RealtimeEvent, EventType
        
        # Create reminder event
        event = RealtimeEvent(
            event_type=EventType.SYSTEM_NOTIFICATION,
            plan_id=plan_id,
            data={
                'plan_id': plan_id,
                'title': plan.title,
                'reminder_type': reminder_type,
                'message': f"Plan '{plan.title}' {reminder_type.replace('_', ' ')}",
                'plan_status': plan.status
            }
        )
        
        # Send reminder
        success = event_publisher.publish_event(event, send_push=True)
        
        return {
            'plan_id': plan_id,
            'task_id': self.request.id,
            'task_name': 'send_plan_reminder',
            'reminder_type': reminder_type,
            'status': 'sent' if success else 'failed',
            'attempt': self.request.retries,
            'timestamp': timezone.now().isoformat()
        }
        
    except Plan.DoesNotExist:
        logger.warning(f"Plan {plan_id} not found for reminder")
        return {
            'plan_id': plan_id,
            'task_id': self.request.id,
            'status': 'not_found',
            'timestamp': timezone.now().isoformat()
        }
        
    except Exception as exc:
        logger.error(f"Failed to send reminder for plan {plan_id}: {str(exc)}")
        raise self.retry(exc=exc)
