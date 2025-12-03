from celery import shared_task
from django.utils import timezone
import logging
from .models import Plan


logger = logging.getLogger(__name__)


@shared_task(bind=True, max_retries=3, default_retry_delay=60)
def start_plan_task(self, plan_id):
    try:
        from .services import PlanService
        
        plan = Plan.objects.get(pk=plan_id)
        
        result = PlanService.start_trip(plan, user=None, force=False)
        
        logger.info(f"Plan {plan_id} started successfully via scheduled task")
        
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
        return {
            'plan_id': plan_id, 
            'task_id': self.request.id,
            'task_name': 'start_plan_task',
            'status': 'not_found',
            'attempt': self.request.retries,
            'timestamp': timezone.now().isoformat()
        }
        
    except ValueError as e:
        msg = str(e)
        logger.info(f"Plan {plan_id} start skipped: {msg}")
        try:
            plan = Plan.objects.get(pk=plan_id)
            if plan.start_date and 'start time has not been reached' in msg.lower():
                remaining = (plan.start_date - timezone.now()).total_seconds()
                # Add a small cushion
                delay = max(1, int(remaining) + 1)
                logger.info(f"Rescheduling start_plan_task for {plan_id} in {delay}s (remaining until start: {remaining}s)")
                raise self.retry(countdown=delay)
        except Plan.DoesNotExist:
            pass

        return {
            'plan_id': plan_id,
            'task_id': self.request.id,
            'task_name': 'start_plan_task',
            'status': 'skipped',
            'reason': msg,
            'attempt': self.request.retries,
            'timestamp': timezone.now().isoformat()
        }
        
    except Exception as exc:
        logger.error(f"Unexpected error starting plan {plan_id}: {str(exc)}")
        raise self.retry(exc=exc)


@shared_task(bind=True, max_retries=3, default_retry_delay=60)
def complete_plan_task(self, plan_id):
    try:
        # Visible console/debug output to help trace task invocation
        print(f"[TASK START] complete_plan_task invoked for plan_id={plan_id} request_id={getattr(self.request, 'id', None)}")
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
        # If the task ran early (end time not reached), retry later
        msg = str(e)
        logger.info(f"Plan {plan_id} completion skipped: {msg}")
        try:
            plan = Plan.objects.get(pk=plan_id)
            if plan.end_date and 'end time has not been reached' in msg.lower():
                remaining = (plan.end_date - timezone.now()).total_seconds()
                delay = max(1, int(remaining) + 1)
                logger.info(f"Rescheduling complete_plan_task for {plan_id} in {delay}s (remaining until end: {remaining}s)")
                raise self.retry(countdown=delay)
        except Plan.DoesNotExist:
            pass

        return {
            'plan_id': plan_id,
            'task_id': self.request.id,
            'task_name': 'complete_plan_task',
            'status': 'skipped',
            'reason': msg,
            'attempt': self.request.retries,
            'timestamp': timezone.now().isoformat()
        }
        
    except Exception as exc:
        logger.error(f"Unexpected error completing plan {plan_id}: {str(exc)}")
        raise self.retry(exc=exc)
