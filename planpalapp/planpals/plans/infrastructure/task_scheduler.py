"""
Plans Infrastructure — Celery Task Scheduling

Encapsulates all Celery task scheduling/revocation logic.
The application layer calls this service through an interface,
keeping Celery as an infrastructure concern.
"""
import logging
from typing import Any, Optional
from uuid import UUID

from celery import current_app
from django.db import transaction

from planpals.plans.infrastructure.repositories import DjangoPlanRepository

logger = logging.getLogger(__name__)


class PlanTaskScheduler:
    """
    Infrastructure service that manages Celery task scheduling for plans.
    Called by the application layer to schedule/revoke plan lifecycle tasks.
    """

    def __init__(self, plan_repo: DjangoPlanRepository = None):
        self._plan_repo = plan_repo or DjangoPlanRepository()

    def schedule_plan_tasks(self, plan: Any) -> None:
        """Schedule start and/or completion tasks for a plan, deferred to after commit."""
        try:
            def _do_schedule():
                scheduled_start_id = None
                scheduled_end_id = None

                try:
                    from planpals.plans.infrastructure.tasks import start_plan_task, complete_plan_task

                    if plan.start_date:
                        start_task = start_plan_task.apply_async(
                            args=[str(plan.id)], eta=plan.start_date,
                        )
                        scheduled_start_id = start_task.id

                    if plan.end_date:
                        end_task = complete_plan_task.apply_async(
                            args=[str(plan.id)], eta=plan.end_date,
                        )
                        scheduled_end_id = end_task.id

                    updates = {}
                    if scheduled_start_id:
                        updates['scheduled_start_task_id'] = scheduled_start_id
                    if scheduled_end_id:
                        updates['scheduled_end_task_id'] = scheduled_end_id

                    if updates:
                        self._plan_repo.update_fields(plan.id, **updates)

                except Exception as exc:
                    logger.warning(
                        f"Task scheduling failed for plan {plan.id}: {exc}"
                    )

            transaction.on_commit(_do_schedule)

        except Exception as e:
            logger.warning(f"Task scheduling setup failed for plan {plan.id}: {e}")

    def revoke_plan_tasks(self, plan: Any) -> None:
        """Revoke scheduled start and end tasks for a plan."""
        old_start_id = plan.scheduled_start_task_id
        old_end_id = plan.scheduled_end_task_id

        for task_id in (old_start_id, old_end_id):
            if not task_id:
                continue
            try:
                current_app.control.revoke(task_id, terminate=False)
            except Exception:
                pass

        self._plan_repo.clear_scheduled_task_ids(plan.id)

    def schedule_completion_task(self, plan: Any) -> None:
        """Schedule (or reschedule) a completion task for an ongoing plan."""
        if not plan.end_date:
            return

        try:
            def _do_schedule_completion():
                try:
                    from planpals.plans.infrastructure.tasks import complete_plan_task

                    # Revoke existing completion task
                    if plan.scheduled_end_task_id:
                        try:
                            current_app.control.revoke(
                                plan.scheduled_end_task_id, terminate=False,
                            )
                        except Exception:
                            pass

                    end_task = complete_plan_task.apply_async(
                        args=[str(plan.id)], eta=plan.end_date,
                    )
                    self._plan_repo.update_fields(
                        plan.id, scheduled_end_task_id=end_task.id,
                    )

                except Exception as exc:
                    logger.warning(
                        f"Failed to schedule completion task for plan {plan.id}: {exc}"
                    )

            transaction.on_commit(_do_schedule_completion)

        except Exception as e:
            logger.warning(f"Failed to schedule completion task: {e}")

    def revoke_scheduled_tasks(self, plan: Any) -> None:
        """Revoke tasks with optimistic locking on existing task IDs."""
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
            self._plan_repo.update_scheduled_task_ids(
                plan.id,
                start_task_id=None if old_start_id else ...,
                end_task_id=None if old_end_id else ...,
                expected_start_task_id=old_start_id,
                expected_end_task_id=old_end_id,
            )
