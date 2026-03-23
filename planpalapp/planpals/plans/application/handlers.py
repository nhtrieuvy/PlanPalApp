"""
Plans Application — Command Handlers

Each handler implements ONE use case. Handlers:
- Use repository INTERFACES (not Django ORM directly)
- Raise domain events (not infrastructure publishers directly)
- Contain business logic extracted from the old fat PlanService

The Dependency Rule is enforced:
  Handler -> Repository Interface (domain)
  Handler -> DomainEventPublisher Interface (domain)
  Handler does NOT import Django ORM, DRF, or infrastructure directly.
"""
import logging
from typing import Any, Optional
from uuid import UUID

from django.db import transaction

from planpals.shared.interfaces import BaseCommandHandler, DomainEventPublisher
from planpals.plans.domain.repositories import PlanRepository, PlanActivityRepository
from planpals.plans.domain.events import (
    PlanCreated, PlanUpdated, PlanStatusChanged, PlanDeleted,
    ActivityCreated, ActivityUpdated, ActivityCompleted, ActivityDeleted,
)
from planpals.plans.application.commands import (
    CreatePlanCommand, UpdatePlanCommand, ChangePlanStatusCommand,
    DeletePlanCommand, JoinPlanCommand,
    AddActivityCommand, UpdateActivityCommand,
    RemoveActivityCommand, ToggleActivityCompletionCommand,
)
from planpals.shared.domain_exceptions import (
    PlanNotFoundException, NotPlanOwnerException,
    PlanCompletedException, PlanCancelledException,
    ActivityNotFoundException, ActivityOverlapException,
    InvalidStatusTransitionException, DomainException,
)

logger = logging.getLogger(__name__)


class CreatePlanHandler(BaseCommandHandler[CreatePlanCommand, Any]):
    """
    Use case: Create a new plan.
    Validates group membership (if group plan), creates plan entity,
    schedules Celery tasks, and publishes PlanCreated event.
    """

    def __init__(
        self,
        plan_repo: PlanRepository,
        event_publisher: DomainEventPublisher,
        membership_checker=None,  # callable(group_id, user_id) -> bool
    ):
        self.plan_repo = plan_repo
        self.event_publisher = event_publisher
        self.membership_checker = membership_checker

    @transaction.atomic
    def handle(self, command: CreatePlanCommand) -> Any:
        # Business rule: Group plans require group membership
        if command.plan_type == 'group' and command.group_id:
            if self.membership_checker and not self.membership_checker(
                command.group_id, command.creator_id
            ):
                raise NotPlanOwnerException(
                    "Bạn phải là thành viên nhóm để tạo kế hoạch nhóm."
                )

        # Delegate creation to repository (which handles ORM)
        plan = self.plan_repo.save_new(command)

        self._log(f"Plan created: {plan.id} by user {command.creator_id}")

        # Publish domain event (deferred until after transaction)
        self.event_publisher.publish(PlanCreated(
            plan_id=str(plan.id),
            title=command.title,
            plan_type=command.plan_type,
            status=str(plan.status),
            creator_id=str(command.creator_id),
            group_id=str(command.group_id) if command.group_id else None,
            is_public=command.is_public,
            start_date=str(command.start_date) if command.start_date else None,
            end_date=str(command.end_date) if command.end_date else None,
        ))

        return plan


class UpdatePlanHandler(BaseCommandHandler[UpdatePlanCommand, Any]):
    """Use case: Update an existing plan's details."""

    def __init__(self, plan_repo: PlanRepository, event_publisher: DomainEventPublisher):
        self.plan_repo = plan_repo
        self.event_publisher = event_publisher

    @transaction.atomic
    def handle(self, command: UpdatePlanCommand) -> Any:
        plan = self.plan_repo.get_by_id(command.plan_id)
        if not plan:
            raise PlanNotFoundException()

        # Business rule: only creator or group admins can edit
        if str(plan.creator_id) != str(command.user_id):
            # Check if user is group admin (if group plan)
            if not (plan.group and plan.group.is_admin_by_id(command.user_id)):
                raise NotPlanOwnerException()

        # Business rule: can't edit completed/cancelled plans
        if plan.status == 'completed':
            raise PlanCompletedException()
        if plan.status == 'cancelled':
            raise PlanCancelledException()

        # Apply only non-None fields
        update_fields = {}
        for field_name in [
            'title', 'description', 'start_date', 'end_date',
            'is_public', 'cover_image', 'destination', 'budget', 'notes',
        ]:
            value = getattr(command, field_name, None)
            if value is not None:
                update_fields[field_name] = value

        if update_fields:
            for k, v in update_fields.items():
                setattr(plan, k, v)
            plan = self.plan_repo.save(plan)

        self.event_publisher.publish(PlanUpdated(
            plan_id=str(plan.id),
            title=plan.title,
            status=str(plan.status),
            last_updated=str(plan.updated_at),
        ))

        return plan


class ChangePlanStatusHandler(BaseCommandHandler[ChangePlanStatusCommand, Any]):
    """Use case: Start trip, complete trip, or cancel plan."""

    VALID_TRANSITIONS = {
        'upcoming': ['ongoing', 'cancelled'],
        'ongoing': ['completed', 'cancelled'],
        'overdue': ['ongoing', 'completed', 'cancelled'],
    }

    def __init__(self, plan_repo: PlanRepository, event_publisher: DomainEventPublisher):
        self.plan_repo = plan_repo
        self.event_publisher = event_publisher

    @transaction.atomic
    def handle(self, command: ChangePlanStatusCommand) -> Any:
        plan = self.plan_repo.get_by_id(command.plan_id)
        if not plan:
            raise PlanNotFoundException()

        if str(plan.creator_id) != str(command.user_id):
            raise NotPlanOwnerException()

        old_status = plan.status
        allowed = self.VALID_TRANSITIONS.get(old_status, [])
        if command.new_status not in allowed:
            raise InvalidStatusTransitionException(
                f"Không thể chuyển trạng thái từ '{old_status}' sang '{command.new_status}'."
            )

        plan = self.plan_repo.update_status(command.plan_id, command.new_status)

        self.event_publisher.publish(PlanStatusChanged(
            plan_id=str(plan.id),
            title=plan.title,
            old_status=old_status,
            new_status=command.new_status,
            initiator_id=str(command.user_id),
        ))

        return plan


class DeletePlanHandler(BaseCommandHandler[DeletePlanCommand, bool]):
    """Use case: Delete a plan."""

    def __init__(self, plan_repo: PlanRepository, event_publisher: DomainEventPublisher):
        self.plan_repo = plan_repo
        self.event_publisher = event_publisher

    @transaction.atomic
    def handle(self, command: DeletePlanCommand) -> bool:
        plan = self.plan_repo.get_by_id(command.plan_id)
        if not plan:
            raise PlanNotFoundException()

        if str(plan.creator_id) != str(command.user_id):
            raise NotPlanOwnerException()

        title = plan.title
        self.plan_repo.delete(command.plan_id)

        self.event_publisher.publish(PlanDeleted(
            plan_id=str(command.plan_id),
            title=title,
        ))

        return True


class JoinPlanHandler(BaseCommandHandler[JoinPlanCommand, Any]):
    """Use case: Join a public plan as a collaborator."""

    def __init__(self, plan_repo: PlanRepository):
        self.plan_repo = plan_repo

    @transaction.atomic
    def handle(self, command: JoinPlanCommand) -> Any:
        plan = self.plan_repo.get_by_id(command.plan_id)
        if not plan:
            raise PlanNotFoundException()

        if not plan.is_public:
            raise DomainException("Kế hoạch này không công khai.")

        if self.plan_repo.is_collaborator(command.plan_id, command.user_id):
            raise DomainException("Bạn đã tham gia kế hoạch này rồi.")

        self.plan_repo.add_collaborator(command.plan_id, command.user_id)
        return plan


# ============================================================================
# Activity Handlers
# ============================================================================

class AddActivityHandler(BaseCommandHandler[AddActivityCommand, Any]):
    """Use case: Add an activity to a plan."""

    def __init__(
        self,
        plan_repo: PlanRepository,
        activity_repo: PlanActivityRepository,
        event_publisher: DomainEventPublisher,
    ):
        self.plan_repo = plan_repo
        self.activity_repo = activity_repo
        self.event_publisher = event_publisher

    @transaction.atomic
    def handle(self, command: AddActivityCommand) -> Any:
        plan = self.plan_repo.get_by_id(command.plan_id)
        if not plan:
            raise PlanNotFoundException()

        if plan.status in ('completed', 'cancelled'):
            if plan.status == 'completed':
                raise PlanCompletedException()
            raise PlanCancelledException()

        # Business rule: check time conflicts
        if command.start_time and command.end_time:
            conflicts = self.activity_repo.check_time_conflicts(
                command.plan_id, command.start_time, command.end_time
            )
            if conflicts:
                raise ActivityOverlapException()

        activity = self.activity_repo.save_new(command)

        self.event_publisher.publish(ActivityCreated(
            plan_id=str(command.plan_id),
            activity_id=str(activity.id),
            title=command.title,
            activity_type=command.activity_type,
            start_time=str(command.start_time) if command.start_time else None,
            end_time=str(command.end_time) if command.end_time else None,
            location_name=command.location_name or None,
            estimated_cost=command.estimated_cost,
        ))

        return activity


class UpdateActivityHandler(BaseCommandHandler[UpdateActivityCommand, Any]):
    """Use case: Update an activity."""

    def __init__(
        self,
        activity_repo: PlanActivityRepository,
        event_publisher: DomainEventPublisher,
    ):
        self.activity_repo = activity_repo
        self.event_publisher = event_publisher

    @transaction.atomic
    def handle(self, command: UpdateActivityCommand) -> Any:
        activity = self.activity_repo.get_by_id(command.activity_id)
        if not activity:
            raise ActivityNotFoundException()

        # Check time conflicts if times changed
        if command.start_time and command.end_time:
            conflicts = self.activity_repo.check_time_conflicts(
                activity.plan_id,
                command.start_time,
                command.end_time,
                exclude_activity_id=command.activity_id,
            )
            if conflicts:
                raise ActivityOverlapException()

        for field_name in [
            'title', 'description', 'activity_type', 'start_time', 'end_time',
            'location_name', 'location_address', 'latitude', 'longitude',
            'estimated_cost', 'notes',
        ]:
            value = getattr(command, field_name, None)
            if value is not None:
                setattr(activity, field_name, value)
        activity = self.activity_repo.save(activity)

        self.event_publisher.publish(ActivityUpdated(
            plan_id=str(activity.plan_id),
            activity_id=str(activity.id),
            title=activity.title,
            is_completed=activity.is_completed,
            last_updated=str(activity.updated_at),
        ))

        return activity


class RemoveActivityHandler(BaseCommandHandler[RemoveActivityCommand, bool]):

    def __init__(self, activity_repo: PlanActivityRepository, event_publisher: DomainEventPublisher):
        self.activity_repo = activity_repo
        self.event_publisher = event_publisher

    @transaction.atomic
    def handle(self, command: RemoveActivityCommand) -> bool:
        activity = self.activity_repo.get_by_id(command.activity_id)
        if not activity:
            raise ActivityNotFoundException()

        plan_id = str(activity.plan_id)
        title = activity.title
        activity_id = str(activity.id)

        self.activity_repo.delete(command.activity_id)

        self.event_publisher.publish(ActivityDeleted(
            plan_id=plan_id,
            activity_id=activity_id,
            title=title,
        ))
        return True


class ToggleActivityCompletionHandler(BaseCommandHandler[ToggleActivityCompletionCommand, Any]):

    def __init__(self, activity_repo: PlanActivityRepository, event_publisher: DomainEventPublisher):
        self.activity_repo = activity_repo
        self.event_publisher = event_publisher

    @transaction.atomic
    def handle(self, command: ToggleActivityCompletionCommand) -> Any:
        activity = self.activity_repo.get_by_id(command.activity_id)
        if not activity:
            raise ActivityNotFoundException()

        activity.is_completed = not activity.is_completed
        activity = self.activity_repo.save(activity)

        if activity.is_completed:
            self.event_publisher.publish(ActivityCompleted(
                plan_id=str(activity.plan_id),
                activity_id=str(activity.id),
                title=activity.title,
                completed_by=str(command.user_id),
            ))
        else:
            self.event_publisher.publish(ActivityUpdated(
                plan_id=str(activity.plan_id),
                activity_id=str(activity.id),
                title=activity.title,
                is_completed=False,
                last_updated=str(activity.updated_at),
            ))

        return activity
