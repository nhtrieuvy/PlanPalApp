from __future__ import annotations

from planpals.budgets.application.services import BudgetService
from planpals.budgets.infrastructure.repositories import (
    DjangoBudgetRepository,
    DjangoExpenseRepository,
)


def get_budget_repo() -> DjangoBudgetRepository:
    return DjangoBudgetRepository()


def get_expense_repo() -> DjangoExpenseRepository:
    return DjangoExpenseRepository()


def get_budget_service() -> BudgetService:
    from planpals.audit.application.factories import get_audit_log_service
    from planpals.notifications.application.factories import get_notification_service
    from planpals.plans.application.factories import get_plan_repo
    from planpals.shared.cache_infrastructure import DjangoCacheService

    return BudgetService(
        budget_repo=get_budget_repo(),
        expense_repo=get_expense_repo(),
        plan_repo=get_plan_repo(),
        cache_service=DjangoCacheService(),
        audit_service=get_audit_log_service(),
        notification_service=get_notification_service(),
        expense_notification_dispatcher=get_expense_notification_dispatcher(),
    )


def get_budget_initializer():
    def initialize(plan) -> None:
        get_budget_service().initialize_plan_budget(plan.id)

    return initialize


def get_expense_notification_dispatcher():
    from planpals.budgets.infrastructure.tasks import process_expense_notifications_task

    def dispatch(expense_id) -> None:
        process_expense_notifications_task.delay(str(expense_id))

    return dispatch
