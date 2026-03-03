"""
Plans Infrastructure — Celery Tasks

These are Celery tasks that handle asynchronous plan lifecycle operations.
They live in the infrastructure layer because Celery is an infrastructure concern.
They delegate business logic to the application-layer PlanService.
"""
import datetime
import logging

from celery import shared_task

logger = logging.getLogger(__name__)


def _utc_now():
    return datetime.datetime.now(datetime.timezone.utc)


@shared_task(bind=True, max_retries=3, default_retry_delay=60)
def start_plan_task(self, plan_id):
    try:
        from planpals.plans.infrastructure.repositories import DjangoPlanRepository
        from planpals.plans.application.services import PlanService

        repo = DjangoPlanRepository()
        plan = repo.get_by_id(plan_id)

        if not plan:
            return {
                'plan_id': plan_id,
                'task_id': self.request.id,
                'task_name': 'start_plan_task',
                'status': 'not_found',
                'attempt': self.request.retries,
                'timestamp': _utc_now().isoformat(),
            }

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
            'timestamp': _utc_now().isoformat(),
        }

    except ValueError as e:
        msg = str(e)
        logger.info(f"Plan {plan_id} start skipped: {msg}")
        try:
            from planpals.plans.infrastructure.repositories import DjangoPlanRepository

            repo = DjangoPlanRepository()
            plan = repo.get_by_id(plan_id)
            if plan and plan.start_date and 'start time has not been reached' in msg.lower():
                remaining = (plan.start_date - _utc_now()).total_seconds()
                delay = max(1, int(remaining) + 1)
                logger.info(
                    f"Rescheduling start_plan_task for {plan_id} in {delay}s "
                    f"(remaining until start: {remaining}s)"
                )
                raise self.retry(countdown=delay)
        except ValueError:
            pass

        return {
            'plan_id': plan_id,
            'task_id': self.request.id,
            'task_name': 'start_plan_task',
            'status': 'skipped',
            'reason': msg,
            'attempt': self.request.retries,
            'timestamp': _utc_now().isoformat(),
        }

    except Exception as exc:
        logger.error(f"Unexpected error starting plan {plan_id}: {str(exc)}")
        raise self.retry(exc=exc)


@shared_task(bind=True, max_retries=3, default_retry_delay=60)
def complete_plan_task(self, plan_id):
    try:
        from planpals.plans.infrastructure.repositories import DjangoPlanRepository
        from planpals.plans.application.services import PlanService

        repo = DjangoPlanRepository()
        plan = repo.get_by_id(plan_id)

        if not plan:
            logger.warning(f"Plan {plan_id} not found for complete task")
            return {
                'plan_id': plan_id,
                'task_id': self.request.id,
                'task_name': 'complete_plan_task',
                'status': 'not_found',
                'attempt': self.request.retries,
                'timestamp': _utc_now().isoformat(),
            }

        result = PlanService.complete_trip(plan, user=None, force=False)

        logger.info(f"Plan {plan_id} completed successfully via scheduled task")

        return {
            'plan_id': plan_id,
            'task_id': self.request.id,
            'task_name': 'complete_plan_task',
            'status': 'completed',
            'previous_status': 'ongoing',
            'current_status': result.status if result else 'completed',
            'attempt': self.request.retries,
            'timestamp': _utc_now().isoformat(),
        }

    except ValueError as e:
        msg = str(e)
        logger.info(f"Plan {plan_id} completion skipped: {msg}")
        try:
            from planpals.plans.infrastructure.repositories import DjangoPlanRepository

            repo = DjangoPlanRepository()
            plan = repo.get_by_id(plan_id)
            if plan and plan.end_date and 'end time has not been reached' in msg.lower():
                remaining = (plan.end_date - _utc_now()).total_seconds()
                delay = max(1, int(remaining) + 1)
                logger.info(
                    f"Rescheduling complete_plan_task for {plan_id} in {delay}s "
                    f"(remaining until end: {remaining}s)"
                )
                raise self.retry(countdown=delay)
        except ValueError:
            pass

        return {
            'plan_id': plan_id,
            'task_id': self.request.id,
            'task_name': 'complete_plan_task',
            'status': 'skipped',
            'reason': msg,
            'attempt': self.request.retries,
            'timestamp': _utc_now().isoformat(),
        }

    except Exception as exc:
        logger.error(f"Unexpected error completing plan {plan_id}: {str(exc)}")
        raise self.retry(exc=exc)
