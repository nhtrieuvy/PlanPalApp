from __future__ import annotations

from decimal import Decimal, InvalidOperation
from typing import Any
from uuid import UUID

from django.db import transaction
from rest_framework.exceptions import PermissionDenied, ValidationError

from planpals.audit.domain.entities import AuditAction, AuditResourceType
from planpals.budgets.application.repositories import (
    BudgetRepository,
    BudgetUpsertData,
    ExpenseCreateData,
    ExpenseFilters,
    ExpenseRepository,
)
from planpals.budgets.domain.entities import (
    Budget,
    BudgetSummary,
    ExpenseCreationResult,
    ExpenseWarning,
)
from planpals.notifications.domain.entities import NotificationType
from planpals.shared.cache import CacheKeys, CacheTTL, CachePort


class BudgetService:
    MAX_PAGE_SIZE = 100
    DEFAULT_CURRENCY = 'VND'
    NEAR_LIMIT_THRESHOLD = Decimal('0.80')
    OVER_BUDGET_THRESHOLD = Decimal('1.00')
    LARGE_EXPENSE_RATIO = Decimal('0.25')
    LARGE_EXPENSE_ABSOLUTE = Decimal('1000000')

    def __init__(
        self,
        budget_repo: BudgetRepository,
        expense_repo: ExpenseRepository,
        plan_repo,
        cache_service: CachePort,
        audit_service=None,
        notification_service=None,
        expense_notification_dispatcher=None,
    ):
        self.budget_repo = budget_repo
        self.expense_repo = expense_repo
        self.plan_repo = plan_repo
        self.cache_service = cache_service
        self.audit_service = audit_service
        self.notification_service = notification_service
        self.expense_notification_dispatcher = expense_notification_dispatcher

    def initialize_plan_budget(self, plan_id, currency: str = DEFAULT_CURRENCY) -> Budget:
        plan_uuid = self._normalize_required_uuid(plan_id, 'plan_id')
        self._require_plan(plan_uuid)
        return self.budget_repo.ensure_budget(
            plan_uuid,
            currency=self._normalize_currency(currency),
        )

    @transaction.atomic
    def create_or_update_budget(
        self,
        plan_id,
        user,
        *,
        total_budget,
        currency: str = DEFAULT_CURRENCY,
    ) -> BudgetSummary:
        plan_uuid = self._normalize_required_uuid(plan_id, 'plan_id')
        actor_id = self._normalize_required_uuid(user, 'user')
        plan = self._require_plan(plan_uuid)

        if not self._can_manage_budget(plan, user):
            raise PermissionDenied('Only the plan owner or a group admin can update the budget.')

        budget_amount = self._normalize_non_negative_amount(total_budget, 'total_budget')
        normalized_currency = self._normalize_currency(currency)
        budget = self.budget_repo.update_budget(
            BudgetUpsertData(
                plan_id=plan_uuid,
                total_budget=budget_amount,
                currency=normalized_currency,
            )
        )
        summary = self._build_summary(plan_uuid, budget)

        if self.audit_service:
            self.audit_service.log_action(
                user=actor_id,
                action=AuditAction.UPDATE_BUDGET.value,
                resource_type=AuditResourceType.BUDGET.value,
                resource_id=budget.id,
                metadata={
                    'plan_id': plan_uuid,
                    'plan_title': getattr(plan, 'title', 'Plan'),
                    'total_budget': budget.total_budget,
                    'currency': budget.currency,
                    'total_spent': summary.total_spent,
                    'remaining_budget': summary.remaining_budget,
                },
            )

        self.invalidate_budget_cache(plan_uuid)
        return summary

    @transaction.atomic
    def add_expense(
        self,
        plan_id,
        user,
        *,
        amount,
        category: str,
        description: str = '',
    ) -> ExpenseCreationResult:
        plan_uuid = self._normalize_required_uuid(plan_id, 'plan_id')
        actor_id = self._normalize_required_uuid(user, 'user')
        plan = self._require_plan(plan_uuid)

        if not self._can_add_expense(plan, user):
            raise PermissionDenied('Only plan participants can add expenses.')

        budget = self.budget_repo.ensure_budget(plan_uuid, currency=self.DEFAULT_CURRENCY)
        expense_amount = self._normalize_positive_amount(amount, 'amount')
        normalized_category = self._normalize_category(category)
        normalized_description = (description or '').strip()

        expense = self.expense_repo.create_expense(
            ExpenseCreateData(
                plan_id=plan_uuid,
                user_id=actor_id,
                amount=expense_amount,
                category=normalized_category,
                description=normalized_description,
            )
        )
        summary = self._build_summary(plan_uuid, budget)
        warnings = self._build_warnings(summary, expense.amount)

        if self.audit_service:
            self.audit_service.log_action(
                user=actor_id,
                action=AuditAction.CREATE_EXPENSE.value,
                resource_type=AuditResourceType.EXPENSE.value,
                resource_id=expense.id,
                metadata={
                    'plan_id': plan_uuid,
                    'plan_title': getattr(plan, 'title', 'Plan'),
                    'amount': expense.amount,
                    'category': expense.category,
                    'description': expense.description,
                    'currency': budget.currency,
                    'total_spent': summary.total_spent,
                    'remaining_budget': summary.remaining_budget,
                },
            )

        self.invalidate_budget_cache(plan_uuid)
        if self.expense_notification_dispatcher:
            transaction.on_commit(
                lambda: self.expense_notification_dispatcher(expense.id)
            )

        return ExpenseCreationResult(
            expense=expense,
            summary=summary,
            warnings=tuple(warnings),
        )

    def get_budget_summary(self, plan_id, viewer) -> BudgetSummary:
        plan_uuid = self._normalize_required_uuid(plan_id, 'plan_id')
        plan = self._require_plan(plan_uuid)
        if not self._can_view_budget(plan, viewer):
            raise PermissionDenied('You do not have permission to view this budget.')

        cache_key = CacheKeys.budget_summary(plan_uuid)

        def compute() -> BudgetSummary:
            budget = self.budget_repo.ensure_budget(plan_uuid, currency=self.DEFAULT_CURRENCY)
            return self._build_summary(plan_uuid, budget)

        return self.cache_service.get_or_set(
            cache_key,
            compute,
            CacheTTL.BUDGET_SUMMARY,
        )

    def list_expenses(self, plan_id, viewer, filters: ExpenseFilters):
        plan_uuid = self._normalize_required_uuid(plan_id, 'plan_id')
        plan = self._require_plan(plan_uuid)
        if not self._can_view_budget(plan, viewer):
            raise PermissionDenied('You do not have permission to view these expenses.')

        normalized_filters = ExpenseFilters(
            category=(filters.category or '').strip() or None,
            user_id=filters.user_id,
            sort_by=self._normalize_sort_by(filters.sort_by),
            sort_direction=self._normalize_sort_direction(filters.sort_direction),
            page=max(filters.page or 1, 1),
            page_size=min(max(filters.page_size or 20, 1), self.MAX_PAGE_SIZE),
        )
        return self.expense_repo.list_expenses(plan_uuid, normalized_filters)

    def process_expense_notifications(self, expense_id) -> dict[str, Any]:
        if not self.notification_service:
            return {'status': 'skipped', 'reason': 'notification_service_unavailable'}

        expense_uuid = self._normalize_required_uuid(expense_id, 'expense_id')
        expense = self.expense_repo.get_by_id(expense_uuid)
        if expense is None:
            return {'status': 'skipped', 'reason': 'expense_not_found'}

        plan = self._require_plan(expense.plan_id)
        budget = self.budget_repo.ensure_budget(expense.plan_id, currency=self.DEFAULT_CURRENCY)
        summary = self._build_summary(expense.plan_id, budget)
        recipients = self._notification_recipients(plan, exclude_user_id=expense.user_id)
        if not recipients:
            return {'status': 'skipped', 'reason': 'no_recipients'}

        notifications_sent = 0
        previous_total = summary.total_spent - expense.amount
        payload_base = {
            'plan_id': str(plan.id),
            'plan_title': getattr(plan, 'title', 'Plan'),
            'actor_name': self._resolve_actor_name(plan, expense.user_id),
            'amount': float(expense.amount),
            'currency': budget.currency,
            'category': expense.category,
            'total_budget': float(budget.total_budget),
            'total_spent': float(summary.total_spent),
            'remaining_budget': float(summary.remaining_budget),
        }

        if self._is_large_expense(expense.amount, budget.total_budget):
            self.notification_service.notify_many(
                user_ids=recipients,
                notification_type=NotificationType.LARGE_EXPENSE.value,
                data=payload_base,
                send_push=True,
                exclude_user_ids=[expense.user_id],
            )
            notifications_sent += len(recipients)

        crossed_threshold = self._crossed_budget_threshold(
            previous_total=previous_total,
            current_total=summary.total_spent,
            total_budget=budget.total_budget,
        )
        if crossed_threshold is not None:
            self.notification_service.notify_many(
                user_ids=recipients,
                notification_type=NotificationType.BUDGET_ALERT.value,
                data={
                    **payload_base,
                    'threshold_pct': crossed_threshold,
                    'spent_percentage': summary.spent_percentage,
                    'over_budget': summary.is_over_budget,
                },
                send_push=True,
                exclude_user_ids=[expense.user_id],
            )
            notifications_sent += len(recipients)

        return {'status': 'processed', 'notifications_sent': notifications_sent}

    def invalidate_budget_cache(self, plan_id) -> None:
        plan_uuid = self._normalize_required_uuid(plan_id, 'plan_id')
        self.cache_service.delete(CacheKeys.budget_summary(plan_uuid))
        self.cache_service.delete(CacheKeys.plan_summary(plan_uuid))

    def _build_summary(self, plan_id: UUID, budget: Budget) -> BudgetSummary:
        total_spent = self.expense_repo.get_total_expense(plan_id)
        breakdown = tuple(self.expense_repo.get_breakdown(plan_id))
        trend = tuple(self.expense_repo.get_spending_trend(plan_id, days=30))
        expense_count = self.expense_repo.count_expenses(plan_id)
        remaining_budget = budget.total_budget - total_spent
        return BudgetSummary(
            budget=budget,
            total_spent=total_spent,
            remaining_budget=remaining_budget,
            breakdown=breakdown,
            trend=trend,
            expense_count=expense_count,
        )

    def _build_warnings(
        self,
        summary: BudgetSummary,
        expense_amount: Decimal,
    ) -> list[ExpenseWarning]:
        warnings: list[ExpenseWarning] = []
        if summary.is_over_budget:
            warnings.append(
                ExpenseWarning(
                    code='OVER_BUDGET',
                    level='warning',
                    message='This expense pushes the plan over its budget.',
                    data={
                        'remaining_budget': float(summary.remaining_budget),
                        'spent_percentage': summary.spent_percentage,
                    },
                )
            )
        elif summary.is_near_limit:
            warnings.append(
                ExpenseWarning(
                    code='NEAR_LIMIT',
                    level='info',
                    message='This plan is close to its budget limit.',
                    data={
                        'remaining_budget': float(summary.remaining_budget),
                        'spent_percentage': summary.spent_percentage,
                    },
                )
            )
        if self._is_large_expense(expense_amount, summary.budget.total_budget):
            warnings.append(
                ExpenseWarning(
                    code='LARGE_EXPENSE',
                    level='info',
                    message='This expense is unusually large for the current budget.',
                    data={'amount': float(expense_amount)},
                )
            )
        return warnings

    def _crossed_budget_threshold(
        self,
        *,
        previous_total: Decimal,
        current_total: Decimal,
        total_budget: Decimal,
    ) -> int | None:
        if total_budget <= Decimal('0'):
            return None

        thresholds = (
            (100, self.OVER_BUDGET_THRESHOLD),
            (80, self.NEAR_LIMIT_THRESHOLD),
        )
        for label, threshold in thresholds:
            threshold_amount = total_budget * threshold
            if previous_total < threshold_amount <= current_total:
                return label
        return None

    def _is_large_expense(self, expense_amount: Decimal, total_budget: Decimal) -> bool:
        threshold = self.LARGE_EXPENSE_ABSOLUTE
        if total_budget > Decimal('0'):
            threshold = max(threshold, total_budget * self.LARGE_EXPENSE_RATIO)
        return expense_amount >= threshold

    def _notification_recipients(self, plan, exclude_user_id: UUID | None = None) -> list[UUID]:
        recipients: set[UUID] = set()
        if getattr(plan, 'creator_id', None):
            recipients.add(UUID(str(plan.creator_id)))
        group = getattr(plan, 'group', None)
        if group is not None:
            recipients.update(
                UUID(str(user_id))
                for user_id in group.get_admins().values_list('id', flat=True)
            )
        if exclude_user_id:
            recipients.discard(UUID(str(exclude_user_id)))
        return list(recipients)

    def _resolve_actor_name(self, plan, user_id: UUID) -> str:
        if str(getattr(plan, 'creator_id', '')) == str(user_id):
            creator = getattr(plan, 'creator', None)
            if creator is not None:
                return creator.get_full_name() or creator.username
        group = getattr(plan, 'group', None)
        if group is not None:
            member = group.members.filter(id=user_id).first()
            if member is not None:
                return member.get_full_name() or member.username
        return 'Someone'

    def _require_plan(self, plan_id: UUID):
        plan = self.plan_repo.get_by_id(plan_id)
        if plan is None:
            raise ValidationError({'plan_id': 'Plan does not exist'})
        return plan

    @staticmethod
    def _can_view_budget(plan, user) -> bool:
        if user is None:
            return False
        if plan.creator == user:
            return True
        group = getattr(plan, 'group', None)
        if group is not None:
            return group.is_member(user)
        return False

    @staticmethod
    def _can_manage_budget(plan, user) -> bool:
        if user is None:
            return False
        if plan.creator == user:
            return True
        group = getattr(plan, 'group', None)
        if group is not None:
            return group.is_admin(user)
        return False

    @staticmethod
    def _can_add_expense(plan, user) -> bool:
        if user is None:
            return False
        if plan.creator == user:
            return True
        group = getattr(plan, 'group', None)
        if group is not None:
            return group.is_member(user)
        return False

    @staticmethod
    def _normalize_required_uuid(value, field_name: str) -> UUID:
        raw_value = getattr(value, 'id', value)
        if raw_value is None:
            raise ValidationError({field_name: f'{field_name} is required'})
        if isinstance(raw_value, UUID):
            return raw_value
        try:
            return UUID(str(raw_value))
        except (TypeError, ValueError) as exc:
            raise ValidationError({field_name: f'Invalid UUID for {field_name}'}) from exc

    @staticmethod
    def _normalize_positive_amount(value, field_name: str) -> Decimal:
        try:
            amount = Decimal(str(value))
        except (InvalidOperation, TypeError, ValueError) as exc:
            raise ValidationError({field_name: f'Invalid decimal for {field_name}'}) from exc
        if amount <= Decimal('0'):
            raise ValidationError({field_name: f'{field_name} must be greater than zero'})
        return amount.quantize(Decimal('0.01'))

    @staticmethod
    def _normalize_non_negative_amount(value, field_name: str) -> Decimal:
        try:
            amount = Decimal(str(value))
        except (InvalidOperation, TypeError, ValueError) as exc:
            raise ValidationError({field_name: f'Invalid decimal for {field_name}'}) from exc
        if amount < Decimal('0'):
            raise ValidationError({field_name: f'{field_name} cannot be negative'})
        return amount.quantize(Decimal('0.01'))

    @staticmethod
    def _normalize_currency(value: str | None) -> str:
        normalized = (value or BudgetService.DEFAULT_CURRENCY).strip().upper()
        if len(normalized) < 3 or len(normalized) > 10:
            raise ValidationError({'currency': 'currency must be between 3 and 10 characters'})
        return normalized

    @staticmethod
    def _normalize_category(value: str | None) -> str:
        normalized = (value or '').strip()
        if not normalized:
            raise ValidationError({'category': 'category is required'})
        if len(normalized) > 100:
            raise ValidationError({'category': 'category must be at most 100 characters'})
        return normalized

    @staticmethod
    def _normalize_sort_by(value: str | None) -> str:
        normalized = (value or 'created_at').strip().lower()
        if normalized not in ('created_at', 'amount'):
            raise ValidationError({'sort_by': 'Unsupported sort field'})
        return normalized

    @staticmethod
    def _normalize_sort_direction(value: str | None) -> str:
        normalized = (value or 'desc').strip().lower()
        if normalized not in ('asc', 'desc'):
            raise ValidationError({'sort_direction': 'sort_direction must be asc or desc'})
        return normalized
