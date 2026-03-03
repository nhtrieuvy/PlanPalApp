"""
Plans Application — Handler Factories

Construct fully-wired handler instances with concrete
infrastructure dependencies. Views and services call these
factories instead of constructing handlers manually.
"""
from planpals.shared.infrastructure import ChannelsDomainEventPublisher
from planpals.plans.infrastructure.repositories import (
    DjangoPlanRepository,
    DjangoPlanActivityRepository,
)
from planpals.plans.application.handlers import (
    CreatePlanHandler,
    UpdatePlanHandler,
    ChangePlanStatusHandler,
    DeletePlanHandler,
    JoinPlanHandler,
    AddActivityHandler,
    UpdateActivityHandler,
    RemoveActivityHandler,
    ToggleActivityCompletionHandler,
)


def _plan_repo():
    return DjangoPlanRepository()


def _activity_repo():
    return DjangoPlanActivityRepository()


def _event_publisher():
    return ChannelsDomainEventPublisher()


def _membership_checker():
    """Returns a callable(group_id, user_id) -> bool."""
    from planpals.groups.infrastructure.repositories import DjangoGroupMembershipRepository
    repo = DjangoGroupMembershipRepository()
    return repo.is_member


def get_create_plan_handler() -> CreatePlanHandler:
    return CreatePlanHandler(
        plan_repo=_plan_repo(),
        event_publisher=_event_publisher(),
        membership_checker=_membership_checker(),
    )


def get_update_plan_handler() -> UpdatePlanHandler:
    return UpdatePlanHandler(
        plan_repo=_plan_repo(),
        event_publisher=_event_publisher(),
    )


def get_change_plan_status_handler() -> ChangePlanStatusHandler:
    return ChangePlanStatusHandler(
        plan_repo=_plan_repo(),
        event_publisher=_event_publisher(),
    )


def get_delete_plan_handler() -> DeletePlanHandler:
    return DeletePlanHandler(
        plan_repo=_plan_repo(),
        event_publisher=_event_publisher(),
    )


def get_join_plan_handler() -> JoinPlanHandler:
    return JoinPlanHandler(
        plan_repo=_plan_repo(),
    )


def get_add_activity_handler() -> AddActivityHandler:
    return AddActivityHandler(
        plan_repo=_plan_repo(),
        activity_repo=_activity_repo(),
        event_publisher=_event_publisher(),
    )


def get_update_activity_handler() -> UpdateActivityHandler:
    return UpdateActivityHandler(
        activity_repo=_activity_repo(),
        event_publisher=_event_publisher(),
    )


def get_remove_activity_handler() -> RemoveActivityHandler:
    return RemoveActivityHandler(
        activity_repo=_activity_repo(),
        event_publisher=_event_publisher(),
    )


def get_toggle_activity_completion_handler() -> ToggleActivityCompletionHandler:
    return ToggleActivityCompletionHandler(
        activity_repo=_activity_repo(),
        event_publisher=_event_publisher(),
    )


# --- Repo / infrastructure service factories for service layer ---

def get_plan_repo():
    return DjangoPlanRepository()


def get_activity_repo():
    return DjangoPlanActivityRepository()


def get_task_scheduler():
    from planpals.plans.infrastructure.task_scheduler import PlanTaskScheduler
    return PlanTaskScheduler(plan_repo=DjangoPlanRepository())


def get_realtime_publisher():
    from planpals.shared.realtime_publisher import RealtimeEventPublisher
    return RealtimeEventPublisher()
