from __future__ import annotations

import calendar
from datetime import datetime, timedelta
from decimal import Decimal, InvalidOperation
from typing import Any, Iterable
from uuid import UUID

from django.db import transaction
from django.utils import timezone
from rest_framework.exceptions import PermissionDenied, ValidationError

from planpals.audit.domain.entities import AuditAction, AuditResourceType
from planpals.budgets.application.repositories import (
    BudgetRepository,
    BudgetUpsertData,
    ExpenseCreateData,
    ExpenseFilters,
    ExpensePaymentCreateData,
    ExpenseParticipantCreateData,
    ExpenseRepository,
    RecurringExpenseCreateData,
    RecurringExpenseRepository,
    SettlementCreateData,
    SettlementRepository,
)
from planpals.budgets.domain.entities import (
    BalanceSummary,
    BudgetForecast,
    Budget,
    BudgetSummary,
    DebtSuggestion,
    ExpenseCreationResult,
    ExpenseWarning,
    FinanceInsights,
    CategorySpending,
    Settlement,
    SettlementStatus,
    SplitStrategy,
    UserBalance,
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
        settlement_repo: SettlementRepository,
        plan_repo,
        cache_service: CachePort,
        audit_service=None,
        notification_service=None,
        expense_notification_dispatcher=None,
        recurring_expense_repo: RecurringExpenseRepository | None = None,
        settlement_notification_dispatcher=None,
    ):
        self.budget_repo = budget_repo
        self.expense_repo = expense_repo
        self.settlement_repo = settlement_repo
        self.plan_repo = plan_repo
        self.cache_service = cache_service
        self.audit_service = audit_service
        self.notification_service = notification_service
        self.expense_notification_dispatcher = expense_notification_dispatcher
        self.recurring_expense_repo = recurring_expense_repo
        self.settlement_notification_dispatcher = settlement_notification_dispatcher

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
        currency: str | None = None,
    ) -> BudgetSummary:
        plan_uuid = self._normalize_required_uuid(plan_id, 'plan_id')
        actor_id = self._normalize_required_uuid(user, 'user')
        plan = self._require_plan(plan_uuid)

        if not self._can_manage_budget(plan, user):
            raise PermissionDenied('Only the plan owner or a group admin can update the budget.')

        budget_amount = self._normalize_non_negative_amount(total_budget, 'total_budget')
        current_budget = self.budget_repo.get_budget_by_plan(plan_uuid)
        normalized_currency = self._normalize_currency(
            currency or (current_budget.currency if current_budget else self.DEFAULT_CURRENCY)
        )
        if current_budget and normalized_currency != current_budget.currency:
            if self.expense_repo.count_expenses(plan_uuid) or self.settlement_repo.list_settlements(plan_uuid):
                raise ValidationError({
                    'currency': 'Currency cannot change after expenses or settlements exist.'
                })
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
                resource_type=AuditResourceType.PLAN.value,
                resource_id=plan_uuid,
                metadata={
                    'entity_type': AuditResourceType.BUDGET.value,
                    'budget_id': budget.id,
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
        paid_by_user_id=None,
        currency: str | None = None,
        split_strategy: str = SplitStrategy.EQUAL.value,
        participants: Iterable[dict[str, Any]] | None = None,
        payments: Iterable[dict[str, Any]] | None = None,
        payment_note: str = '',
        receipt=None,
        recurrence: dict[str, Any] | None = None,
        recurrence_id=None,
        occurrence_at: datetime | None = None,
    ) -> ExpenseCreationResult:
        plan_uuid = self._normalize_required_uuid(plan_id, 'plan_id')
        actor_id = self._normalize_required_uuid(user, 'user')
        plan = self._require_plan(plan_uuid)
        permission_user = self._resolve_plan_user(plan, user, actor_id)

        if not self._can_add_expense(plan, permission_user):
            raise PermissionDenied('Only plan participants can add expenses.')

        budget = self.budget_repo.ensure_budget(plan_uuid, currency=self.DEFAULT_CURRENCY)
        expense_amount = self._normalize_positive_amount(amount, 'amount')
        normalized_currency = self._normalize_currency(currency or budget.currency)
        if normalized_currency != budget.currency:
            raise ValidationError({'currency': 'Expense currency must match the plan budget.'})
        normalized_category = self._normalize_category(category)
        normalized_description = (description or '').strip()
        payment_items, paid_by_id = self._calculate_payments(
            plan=plan,
            amount=expense_amount,
            paid_by_user_id=paid_by_user_id or actor_id,
            raw_payments=list(payments or []),
        )
        normalized_strategy = self._normalize_split_strategy(split_strategy)
        participant_items = self._calculate_participants(
            plan=plan,
            payment_amounts={item.user_id: item.amount for item in payment_items},
            amount=expense_amount,
            split_strategy=normalized_strategy,
            raw_participants=list(participants or []),
        )

        recurring_rule = None
        if recurrence:
            recurring_rule = self._create_recurring_rule(
                plan_uuid=plan_uuid,
                actor_id=actor_id,
                amount=expense_amount,
                currency=normalized_currency,
                category=normalized_category,
                description=normalized_description,
                payment_note=(payment_note or '').strip(),
                split_strategy=normalized_strategy,
                participant_items=participant_items,
                payment_items=payment_items,
                recurrence=recurrence,
            )

        expense = self.expense_repo.create_expense(
            ExpenseCreateData(
                plan_id=plan_uuid,
                user_id=actor_id,
                paid_by_user_id=paid_by_id,
                amount=expense_amount,
                currency=normalized_currency,
                category=normalized_category,
                description=normalized_description,
                payment_note=(payment_note or '').strip(),
                receipt=receipt,
                split_strategy=normalized_strategy,
                participants=participant_items,
                payments=payment_items,
                recurrence_id=(
                    recurring_rule.id if recurring_rule else (
                        self._normalize_required_uuid(recurrence_id, 'recurrence_id')
                        if recurrence_id else None
                    )
                ),
                occurrence_at=occurrence_at,
            )
        )
        summary = self._build_summary(plan_uuid, budget)
        warnings = self._build_warnings(summary, expense.amount)

        if self.audit_service:
            self.audit_service.log_action(
                user=actor_id,
                action=AuditAction.CREATE_EXPENSE.value,
                resource_type=AuditResourceType.PLAN.value,
                resource_id=plan_uuid,
                metadata={
                    'entity_type': AuditResourceType.EXPENSE.value,
                    'expense_id': expense.id,
                    'plan_id': plan_uuid,
                    'plan_title': getattr(plan, 'title', 'Plan'),
                    'paid_by_user_id': paid_by_id,
                    'payments': [
                        {'user_id': item.user_id, 'amount': item.amount}
                        for item in payment_items
                    ],
                    'amount': expense.amount,
                    'currency': normalized_currency,
                    'category': expense.category,
                    'description': expense.description,
                    'split_strategy': normalized_strategy,
                    'participant_ids': [item.user_id for item in participant_items],
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

    @transaction.atomic
    def correct_expense(
        self,
        plan_id,
        expense_id,
        actor,
        *,
        amount,
        category: str,
        description: str = '',
        payment_note: str = '',
        reason: str,
        receipt=None,
        paid_by_user_id=None,
        payments: list[dict[str, Any]] | None = None,
        split_strategy: str | None = None,
        participants: list[dict[str, Any]] | None = None,
    ) -> ExpenseCreationResult:
        plan_uuid = self._normalize_required_uuid(plan_id, 'plan_id')
        expense_uuid = self._normalize_required_uuid(expense_id, 'expense_id')
        actor_id = self._normalize_required_uuid(actor, 'actor')
        plan = self._require_plan(plan_uuid)
        current = self.expense_repo.get_effective_expense(expense_uuid, for_update=True)
        if current is None or current.plan_id != plan_uuid:
            raise ValidationError({'expense_id': 'Expense is missing or has already been corrected'})
        if actor_id != current.user_id and not self._can_manage_budget(plan, actor):
            raise PermissionDenied('Only the expense creator or a plan admin can correct it.')

        normalized_reason = (reason or '').strip()
        if not normalized_reason:
            raise ValidationError({'reason': 'A correction reason is required'})
        corrected_amount = self._normalize_positive_amount(amount, 'amount')
        if paid_by_user_id is not None and payments is not None:
            raise ValidationError({'payments': 'Provide either one payer or payment contributions'})
        current_payments = current.payments or (
            ExpensePaymentCreateData(user_id=current.paid_by_user_id, amount=current.amount),
        )
        current_participants = current.participants or (
            ExpenseParticipantCreateData(user_id=current.paid_by_user_id, owed_amount=current.amount),
        )
        if paid_by_user_id is not None or payments is not None:
            corrected_payments, corrected_payer_id = self._calculate_payments(
                plan=plan,
                amount=corrected_amount,
                paid_by_user_id=paid_by_user_id or current.paid_by_user_id,
                raw_payments=payments or [],
            )
        else:
            payment_amounts = self._rescale_amounts(
                [item.amount for item in current_payments],
                current.amount,
                corrected_amount,
            )
            corrected_payments = tuple(
                ExpensePaymentCreateData(user_id=item.user_id, amount=value)
                for item, value in zip(current_payments, payment_amounts)
            )
            corrected_payer_id = current.paid_by_user_id
        payment_map = {item.user_id: item.amount for item in corrected_payments}
        normalized_strategy = split_strategy or current.split_strategy
        if participants is None:
            owed_amounts = self._rescale_amounts(
                [item.owed_amount for item in current_participants],
                current.amount,
                corrected_amount,
            )
            participant_items = tuple(
                ExpenseParticipantCreateData(
                    user_id=item.user_id,
                    owed_amount=value,
                    balance=(payment_map.get(item.user_id, Decimal('0.00')) - value).quantize(Decimal('0.01')),
                )
                for item, value in zip(current_participants, owed_amounts)
            )
        else:
            participant_items = self._calculate_participants(
                plan=plan,
                payment_amounts=payment_map,
                amount=corrected_amount,
                split_strategy=normalized_strategy,
                raw_participants=participants,
            )
        corrected = self.expense_repo.create_expense(
            ExpenseCreateData(
                plan_id=plan_uuid,
                user_id=current.user_id,
                paid_by_user_id=corrected_payer_id,
                amount=corrected_amount,
                currency=current.currency,
                category=self._normalize_category(category),
                description=(description or '').strip(),
                payment_note=(payment_note or '').strip(),
                receipt=receipt,
                copy_receipt_from_expense_id=current.id,
                split_strategy=normalized_strategy,
                participants=participant_items,
                payments=corrected_payments,
                entry_type='correction',
                corrects_expense_id=current.id,
                correction_reason=normalized_reason,
                recurrence_id=current.recurrence_id,
            )
        )
        budget = self.budget_repo.ensure_budget(plan_uuid, currency=current.currency)
        summary = self._build_summary(plan_uuid, budget)
        if self.audit_service:
            self.audit_service.log_action(
                user=actor_id,
                action=AuditAction.UPDATE_EXPENSE.value,
                resource_type=AuditResourceType.PLAN.value,
                resource_id=plan_uuid,
                metadata={
                    'plan_id': plan_uuid,
                    'plan_title': getattr(plan, 'title', 'Plan'),
                    'expense_id': corrected.id,
                    'corrects_expense_id': current.id,
                    'previous_amount': current.amount,
                    'amount': corrected.amount,
                    'currency': corrected.currency,
                    'category': corrected.category,
                    'previous_paid_by_user_id': current.paid_by_user_id,
                    'paid_by_user_id': corrected_payer_id,
                    'reason': normalized_reason,
                },
            )
        self.invalidate_budget_cache(plan_uuid)
        return ExpenseCreationResult(
            expense=corrected,
            summary=summary,
            warnings=tuple(self._build_warnings(summary, corrected.amount)),
        )

    @transaction.atomic
    def delete_expense(self, plan_id, expense_id, actor) -> None:
        plan_uuid = self._normalize_required_uuid(plan_id, 'plan_id')
        expense_uuid = self._normalize_required_uuid(expense_id, 'expense_id')
        actor_id = self._normalize_required_uuid(actor, 'actor')
        plan = self._require_plan(plan_uuid)
        expense = self.expense_repo.get_effective_expense(expense_uuid, for_update=True)
        if expense is None or expense.plan_id != plan_uuid:
            raise ValidationError({'expense_id': 'Expense is missing or has already been deleted'})
        if actor_id != expense.user_id and not self._can_manage_budget(plan, actor):
            raise PermissionDenied('Only the expense creator or a plan admin can delete it.')

        self.expense_repo.soft_delete(expense_uuid, deleted_by_user_id=actor_id)
        if self.audit_service:
            self.audit_service.log_action(
                user=actor_id,
                action=AuditAction.DELETE_EXPENSE.value,
                resource_type=AuditResourceType.PLAN.value,
                resource_id=plan_uuid,
                metadata={
                    'plan_id': plan_uuid,
                    'plan_title': getattr(plan, 'title', 'Plan'),
                    'expense_id': expense.id,
                    'amount': expense.amount,
                    'currency': expense.currency,
                    'category': expense.category,
                },
            )
        self.invalidate_budget_cache(plan_uuid)

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

    def get_balances(self, plan_id, viewer) -> BalanceSummary:
        plan_uuid = self._normalize_required_uuid(plan_id, 'plan_id')
        plan = self._require_plan(plan_uuid)
        if not self._can_view_budget(plan, viewer):
            raise PermissionDenied('You do not have permission to view these balances.')

        budget = self.budget_repo.ensure_budget(plan_uuid, currency=self.DEFAULT_CURRENCY)
        expenses = self.expense_repo.list_expenses_for_balances(plan_uuid)
        settlements = self.settlement_repo.list_settlements(plan_uuid)
        member_profiles = self._plan_member_profiles(plan)

        totals: dict[UUID, dict[str, Decimal]] = {
            user_id: {
                'paid': Decimal('0.00'),
                'owed': Decimal('0.00'),
                'settlement_paid': Decimal('0.00'),
                'settlement_received': Decimal('0.00'),
            }
            for user_id in member_profiles
        }

        total_expenses = Decimal('0.00')
        for expense in expenses:
            payments = expense.payments or ()
            if not payments:
                totals.setdefault(expense.paid_by_user_id, self._empty_balance_totals())
                totals[expense.paid_by_user_id]['paid'] += expense.amount
            for payment in payments:
                totals.setdefault(payment.user_id, self._empty_balance_totals())
                totals[payment.user_id]['paid'] += payment.amount
            total_expenses += expense.amount
            for participant in expense.participants:
                totals.setdefault(participant.user_id, self._empty_balance_totals())
                totals[participant.user_id]['owed'] += participant.owed_amount

        for settlement in settlements:
            if settlement.status != SettlementStatus.COMPLETED.value:
                continue
            totals.setdefault(settlement.from_user_id, self._empty_balance_totals())
            totals.setdefault(settlement.to_user_id, self._empty_balance_totals())
            totals[settlement.from_user_id]['settlement_paid'] += settlement.amount
            totals[settlement.to_user_id]['settlement_received'] += settlement.amount

        balances: list[UserBalance] = []
        for user_id, values in totals.items():
            profile = member_profiles.get(user_id, {})
            net_balance = (
                values['paid']
                - values['owed']
                + values['settlement_paid']
                - values['settlement_received']
            ).quantize(Decimal('0.01'))
            balances.append(
                UserBalance(
                    user_id=user_id,
                    username=profile.get('username', ''),
                    full_name=profile.get('full_name', profile.get('username', '')),
                    total_paid=values['paid'].quantize(Decimal('0.01')),
                    total_owed=values['owed'].quantize(Decimal('0.01')),
                    settlement_paid=values['settlement_paid'].quantize(Decimal('0.01')),
                    settlement_received=values['settlement_received'].quantize(Decimal('0.01')),
                    net_balance=net_balance,
                )
            )

        balances.sort(key=lambda item: (item.full_name or item.username).lower())
        suggestions = self._build_debt_suggestions(balances)
        return BalanceSummary(
            plan_id=plan_uuid,
            currency=budget.currency,
            total_expenses=total_expenses.quantize(Decimal('0.01')),
            balances=tuple(balances),
            settlement_suggestions=tuple(suggestions),
        )

    @transaction.atomic
    def create_settlement(
        self,
        *,
        plan_id,
        actor,
        from_user_id,
        to_user_id,
        amount,
        currency: str | None = None,
        status: str = SettlementStatus.PENDING.value,
        note: str = '',
        payment_note: str = '',
        receipt=None,
    ) -> Settlement:
        plan_uuid = self._normalize_required_uuid(plan_id, 'plan_id')
        actor_id = self._normalize_required_uuid(actor, 'actor')
        plan = self._require_plan(plan_uuid)
        if not self._can_view_budget(plan, actor):
            raise PermissionDenied('You do not have permission to settle this plan.')

        payer_id = self._normalize_required_uuid(from_user_id, 'from_user_id')
        receiver_id = self._normalize_required_uuid(to_user_id, 'to_user_id')
        if payer_id == receiver_id:
            raise ValidationError({'to_user_id': 'from_user_id and to_user_id must be different'})
        self._validate_plan_member_ids(plan, [payer_id, receiver_id], field_name='participants')
        if actor_id != payer_id and not self._can_manage_budget(plan, actor):
            raise PermissionDenied('Only the payer or a plan admin can record this settlement.')

        normalized_status = self._normalize_settlement_status(status)
        if normalized_status != SettlementStatus.PENDING.value:
            raise ValidationError({'status': 'New settlements must start in pending status'})
        requested_amount = self._normalize_positive_amount(amount, 'amount')
        budget = self.budget_repo.ensure_budget(plan_uuid, currency=self.DEFAULT_CURRENCY)
        normalized_currency = self._normalize_currency(currency or budget.currency)
        if normalized_currency != budget.currency:
            raise ValidationError({'currency': 'Settlement currency must match the plan budget.'})
        self.settlement_repo.lock_plan_ledger(plan_uuid)
        available = self._available_debt(plan_uuid, actor, payer_id, receiver_id)
        pending_amount = sum(
            (
                item.amount for item in self.settlement_repo.list_settlements(plan_uuid)
                if item.status == SettlementStatus.PENDING.value
                and item.from_user_id == payer_id
                and item.to_user_id == receiver_id
            ),
            Decimal('0.00'),
        )
        if requested_amount > available - pending_amount:
            raise ValidationError({'amount': 'Settlement exceeds the outstanding balance'})
        settlement = self.settlement_repo.create_settlement(
            SettlementCreateData(
                plan_id=plan_uuid,
                from_user_id=payer_id,
                to_user_id=receiver_id,
                amount=requested_amount,
                currency=normalized_currency,
                requested_by_user_id=actor_id,
                status=normalized_status,
                note=(note or '').strip(),
                payment_note=(payment_note or '').strip(),
                receipt=receipt,
            )
        )

        if self.audit_service:
            self.audit_service.log_action(
                user=actor_id,
                action=AuditAction.SETTLEMENT_REQUESTED.value,
                resource_type=AuditResourceType.PLAN.value,
                resource_id=plan_uuid,
                metadata={
                    'plan_id': plan_uuid,
                    'plan_title': getattr(plan, 'title', 'Plan'),
                    'from_user_id': payer_id,
                    'to_user_id': receiver_id,
                    'amount': settlement.amount,
                    'currency': settlement.currency,
                    'settlement_id': settlement.id,
                },
            )

        if self.settlement_notification_dispatcher:
            transaction.on_commit(
                lambda: self.settlement_notification_dispatcher(settlement.id, 'requested')
            )

        self.invalidate_budget_cache(plan_uuid)
        return settlement

    def list_settlements(self, plan_id, viewer) -> tuple[Settlement, ...]:
        plan_uuid = self._normalize_required_uuid(plan_id, 'plan_id')
        plan = self._require_plan(plan_uuid)
        if not self._can_view_budget(plan, viewer):
            raise PermissionDenied('You do not have permission to view settlements.')
        return tuple(self.settlement_repo.list_settlements(plan_uuid))

    @transaction.atomic
    def respond_to_settlement(
        self,
        settlement_id,
        actor,
        *,
        action: str,
        rejection_reason: str = '',
    ) -> Settlement:
        settlement_uuid = self._normalize_required_uuid(settlement_id, 'settlement_id')
        actor_id = self._normalize_required_uuid(actor, 'actor')
        current = self.settlement_repo.get_by_id(settlement_uuid, for_update=True)
        if current is None:
            raise ValidationError({'settlement_id': 'Settlement not found'})
        if current.status != SettlementStatus.PENDING.value:
            raise ValidationError({'status': 'Only pending settlements can be processed'})
        plan = self._require_plan(current.plan_id)
        if actor_id != current.to_user_id and not self._can_manage_budget(plan, actor):
            raise PermissionDenied('Only the receiver or a plan admin can process this request.')
        if action not in {'complete', 'reject'}:
            raise ValidationError({'action': 'Unsupported settlement action'})
        if action == 'complete':
            self.budget_repo.ensure_budget(current.plan_id, currency=self.DEFAULT_CURRENCY)
            self.settlement_repo.lock_plan_ledger(current.plan_id)
            available = self._available_debt(
                current.plan_id,
                actor,
                current.from_user_id,
                current.to_user_id,
            )
            if current.amount > available:
                raise ValidationError({'amount': 'Outstanding balance changed; this request can no longer be completed'})
            target_status = SettlementStatus.COMPLETED.value
            reason = ''
        else:
            target_status = SettlementStatus.REJECTED.value
            reason = (rejection_reason or '').strip()

        updated = self.settlement_repo.transition(
            settlement_uuid,
            status=target_status,
            rejection_reason=reason,
        )
        if self.audit_service:
            action_name = (
                AuditAction.SETTLEMENT_COMPLETED.value
                if target_status == SettlementStatus.COMPLETED.value
                else AuditAction.SETTLEMENT_REJECTED.value
            )
            self.audit_service.log_action(
                user=actor_id,
                action=action_name,
                resource_type=AuditResourceType.PLAN.value,
                resource_id=current.plan_id,
                metadata={
                    'plan_id': current.plan_id,
                    'plan_title': getattr(plan, 'title', 'Plan'),
                    'settlement_id': current.id,
                    'from_user_id': current.from_user_id,
                    'to_user_id': current.to_user_id,
                    'amount': current.amount,
                    'currency': current.currency,
                    'rejection_reason': reason,
                },
            )
        self.invalidate_budget_cache(current.plan_id)
        if self.settlement_notification_dispatcher:
            transaction.on_commit(
                lambda: self.settlement_notification_dispatcher(updated.id, target_status)
            )
        return updated

    def get_finance_insights(self, plan_id, viewer) -> FinanceInsights:
        plan_uuid = self._normalize_required_uuid(plan_id, 'plan_id')
        plan = self._require_plan(plan_uuid)
        if not self._can_view_budget(plan, viewer):
            raise PermissionDenied('You do not have permission to view finance insights.')
        budget = self.budget_repo.ensure_budget(plan_uuid, currency=self.DEFAULT_CURRENCY)
        total = self.expense_repo.get_total_expense(plan_uuid).quantize(Decimal('0.01'))
        categories = tuple(
            CategorySpending(
                category=category,
                amount=value.quantize(Decimal('0.01')),
                percentage=round(float(value / total * Decimal('100')), 2) if total else 0.0,
            )
            for category, value in self.expense_repo.get_category_totals(plan_uuid)
        )
        today = timezone.localdate()
        start = getattr(plan, 'start_date', None) or today
        end = getattr(plan, 'end_date', None) or (today + timedelta(days=30))
        if hasattr(start, 'date'):
            start = start.date()
        if hasattr(end, 'date'):
            end = end.date()
        elapsed_days = max((today - min(start, today)).days + 1, 1)
        remaining_days = max((end - today).days, 0)
        daily_average = (total / Decimal(elapsed_days)).quantize(Decimal('0.01'))
        projected_total = (total + daily_average * remaining_days).quantize(Decimal('0.01'))
        pending = [
            item for item in self.settlement_repo.list_settlements(plan_uuid)
            if item.status == SettlementStatus.PENDING.value
        ]
        return FinanceInsights(
            plan_id=plan_uuid,
            currency=budget.currency,
            total_spent=total,
            categories=categories,
            forecast=BudgetForecast(
                daily_average=daily_average,
                projected_total=projected_total,
                projected_remaining=(budget.total_budget - projected_total).quantize(Decimal('0.01')),
                projected_over_budget=budget.total_budget > 0 and projected_total > budget.total_budget,
                forecast_date=end,
            ),
            pending_settlement_count=len(pending),
            pending_settlement_amount=sum((item.amount for item in pending), Decimal('0.00')).quantize(Decimal('0.01')),
        )

    def list_recurring_expenses(self, plan_id, viewer):
        plan_uuid = self._normalize_required_uuid(plan_id, 'plan_id')
        plan = self._require_plan(plan_uuid)
        if not self._can_view_budget(plan, viewer):
            raise PermissionDenied('You do not have permission to view recurring expenses.')
        if self.recurring_expense_repo is None:
            return ()
        return tuple(self.recurring_expense_repo.list_for_plan(plan_uuid))

    @transaction.atomic
    def set_recurring_expense_active(
        self,
        plan_id,
        recurring_id,
        actor,
        *,
        is_active: bool,
    ):
        if self.recurring_expense_repo is None:
            raise ValidationError({'recurring_id': 'Recurring expenses are unavailable'})
        plan_uuid = self._normalize_required_uuid(plan_id, 'plan_id')
        recurring_uuid = self._normalize_required_uuid(recurring_id, 'recurring_id')
        actor_id = self._normalize_required_uuid(actor, 'actor')
        plan = self._require_plan(plan_uuid)
        rule = self.recurring_expense_repo.get_by_id(recurring_uuid, for_update=True)
        if rule is None or rule.plan_id != plan_uuid:
            raise ValidationError({'recurring_id': 'Recurring expense not found'})
        if actor_id != rule.created_by_user_id and not self._can_manage_budget(plan, actor):
            raise PermissionDenied('Only the creator or a plan admin can manage this schedule.')

        next_run = rule.next_run_at
        if is_active and next_run <= timezone.now():
            next_run = self._next_recurrence_at(
                timezone.now(),
                rule.frequency,
                rule.interval,
            )
        updated = self.recurring_expense_repo.set_active(
            recurring_uuid,
            is_active=bool(is_active),
            next_run_at=next_run,
        )
        if self.audit_service:
            self.audit_service.log_action(
                user=actor_id,
                action=AuditAction.UPDATE_EXPENSE.value,
                resource_type=AuditResourceType.PLAN.value,
                resource_id=plan_uuid,
                metadata={
                    'plan_id': plan_uuid,
                    'plan_title': getattr(plan, 'title', 'Plan'),
                    'recurring_expense_id': recurring_uuid,
                    'category': rule.category,
                    'schedule_status': 'active' if is_active else 'paused',
                },
            )
        return updated

    @transaction.atomic
    def generate_due_recurring_expenses(self, now=None, limit: int = 100) -> dict[str, int]:
        if self.recurring_expense_repo is None:
            return {'created': 0, 'disabled': 0}
        current_time = now or timezone.now()
        created = 0
        disabled = 0
        for rule in self.recurring_expense_repo.list_due(current_time, limit=limit):
            is_expired = rule.end_at is not None and rule.next_run_at > rule.end_at
            if is_expired:
                self.recurring_expense_repo.advance(
                    rule.id,
                    last_run_at=rule.last_run_at or current_time,
                    next_run_at=rule.next_run_at,
                    is_active=False,
                )
                disabled += 1
                continue
            self.add_expense(
                rule.plan_id,
                rule.created_by_user_id,
                amount=rule.amount,
                category=rule.category,
                description=rule.description,
                currency=rule.currency,
                split_strategy=rule.split_strategy,
                participants=rule.participants,
                payments=rule.payments,
                payment_note=rule.payment_note,
                recurrence_id=rule.id,
                occurrence_at=rule.next_run_at,
            )
            next_run = self._next_recurrence_at(rule.next_run_at, rule.frequency, rule.interval)
            active = rule.end_at is None or next_run <= rule.end_at
            self.recurring_expense_repo.advance(
                rule.id,
                last_run_at=rule.next_run_at,
                next_run_at=next_run,
                is_active=active,
            )
            created += 1
        return {'created': created, 'disabled': disabled}

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
        participant_recipients = [
            user_id
            for user_id in self.expense_repo.get_participant_user_ids(expense.id)
            if str(user_id) != str(expense.user_id)
        ]
        if not recipients:
            recipients = []

        notifications_sent = 0
        previous_total = summary.total_spent - expense.amount
        payload_base = {
            'plan_id': str(plan.id),
            'plan_title': getattr(plan, 'title', 'Plan'),
            'actor_name': self._resolve_actor_name(plan, expense.user_id),
            'amount': float(expense.amount),
            'currency': expense.currency or budget.currency,
            'category': expense.category,
            'total_budget': float(budget.total_budget),
            'total_spent': float(summary.total_spent),
            'remaining_budget': float(summary.remaining_budget),
        }

        if participant_recipients:
            self.notification_service.notify_many(
                user_ids=participant_recipients,
                notification_type=NotificationType.EXPENSE_ADDED.value,
                data=payload_base,
                send_push=True,
                exclude_user_ids=[expense.user_id],
            )
            notifications_sent += len(participant_recipients)

        if recipients and self._is_large_expense(expense.amount, budget.total_budget):
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
        if recipients and crossed_threshold is not None:
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

        if notifications_sent == 0:
            return {'status': 'skipped', 'reason': 'no_recipients'}
        return {'status': 'processed', 'notifications_sent': notifications_sent}

    def process_settlement_notification(self, settlement_id, event: str) -> dict[str, Any]:
        if not self.notification_service:
            return {'status': 'skipped', 'reason': 'notification_service_unavailable'}
        settlement_uuid = self._normalize_required_uuid(settlement_id, 'settlement_id')
        settlement = self.settlement_repo.get_by_id(settlement_uuid)
        if settlement is None:
            return {'status': 'skipped', 'reason': 'settlement_not_found'}
        plan = self._require_plan(settlement.plan_id)
        event_types = {
            'requested': NotificationType.SETTLEMENT_REQUESTED.value,
            SettlementStatus.COMPLETED.value: NotificationType.SETTLEMENT_COMPLETED.value,
            SettlementStatus.REJECTED.value: NotificationType.SETTLEMENT_REJECTED.value,
            'reminder': NotificationType.SETTLEMENT_REMINDER.value,
        }
        notification_type = event_types.get(event)
        if notification_type is None:
            return {'status': 'skipped', 'reason': 'unsupported_event'}
        recipient_id = (
            settlement.to_user_id
            if event in {'requested', 'reminder'}
            else settlement.from_user_id
        )
        actor_id = (
            settlement.from_user_id
            if event in {'requested', 'reminder'}
            else settlement.to_user_id
        )
        self.notification_service.notify(
            user_id=recipient_id,
            notification_type=notification_type,
            data={
                'settlement_id': str(settlement.id),
                'plan_id': str(settlement.plan_id),
                'plan_title': getattr(plan, 'title', 'Plan'),
                'actor_name': self._resolve_actor_name(plan, actor_id),
                'amount': float(settlement.amount),
                'currency': settlement.currency,
                'status': settlement.status,
            },
            send_push=True,
        )
        return {'status': 'processed', 'recipient_id': str(recipient_id)}

    def dispatch_pending_settlement_reminders(self, minimum_age_hours: int = 24) -> dict[str, int]:
        cutoff = timezone.now() - timedelta(hours=max(minimum_age_hours, 1))
        pending = self.settlement_repo.list_pending_before(cutoff)
        if self.settlement_notification_dispatcher:
            for settlement in pending:
                self.settlement_notification_dispatcher(settlement.id, 'reminder')
        return {'queued': len(pending)}

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

    def _calculate_participants(
        self,
        *,
        plan,
        payment_amounts: dict[UUID, Decimal],
        amount: Decimal,
        split_strategy: str,
        raw_participants: list[dict[str, Any]],
    ) -> tuple[ExpenseParticipantCreateData, ...]:
        if not raw_participants:
            member_ids = list(self._plan_member_profiles(plan).keys())
            raw_participants = [{'user_id': user_id} for user_id in member_ids]

        participant_ids: list[UUID] = []
        for item in raw_participants:
            participant_ids.append(self._normalize_required_uuid(item.get('user_id'), 'participants.user_id'))

        if not participant_ids:
            raise ValidationError({'participants': 'At least one participant is required'})
        if len(participant_ids) != len(set(participant_ids)):
            raise ValidationError({'participants': 'Participants must be unique'})
        self._validate_plan_member_ids(plan, participant_ids, field_name='participants')

        if split_strategy == SplitStrategy.EQUAL.value:
            owed_amounts = self._split_equal(amount, len(participant_ids))
        elif split_strategy == SplitStrategy.PERCENTAGE.value:
            percentages = [
                self._normalize_non_negative_amount(
                    item.get('percentage', item.get('percent')),
                    'participants.percentage',
                )
                for item in raw_participants
            ]
            if sum(percentages, Decimal('0.00')) != Decimal('100.00'):
                raise ValidationError({'participants': 'Percentage split must total 100'})
            owed_amounts = self._split_percentage(amount, percentages)
        elif split_strategy == SplitStrategy.EXACT.value:
            owed_amounts = [
                self._normalize_non_negative_amount(
                    item.get('amount', item.get('owed_amount')),
                    'participants.amount',
                )
                for item in raw_participants
            ]
            if sum(owed_amounts, Decimal('0.00')) != amount:
                raise ValidationError({'participants': 'Exact split amounts must equal the expense amount'})
        else:
            raise ValidationError({'split_strategy': 'Unsupported split strategy'})

        return tuple(
            ExpenseParticipantCreateData(
                user_id=user_id,
                owed_amount=owed,
                settled_amount=Decimal('0.00'),
                balance=(payment_amounts.get(user_id, Decimal('0.00')) - owed).quantize(Decimal('0.01')),
            )
            for user_id, owed in zip(participant_ids, owed_amounts)
        )

    def _calculate_payments(
        self,
        *,
        plan,
        amount: Decimal,
        paid_by_user_id,
        raw_payments: list[dict[str, Any]],
    ) -> tuple[tuple[ExpensePaymentCreateData, ...], UUID]:
        """Validate cash contributions and retain one primary payer for legacy clients."""
        if not raw_payments:
            payer_id = self._normalize_required_uuid(paid_by_user_id, 'paid_by_user_id')
            self._validate_plan_member_ids(plan, [payer_id], field_name='paid_by_user_id')
            return (ExpensePaymentCreateData(user_id=payer_id, amount=amount),), payer_id

        normalized: list[ExpensePaymentCreateData] = []
        payer_ids: list[UUID] = []
        for item in raw_payments:
            payer_id = self._normalize_required_uuid(item.get('user_id'), 'payments.user_id')
            payer_ids.append(payer_id)
            normalized.append(
                ExpensePaymentCreateData(
                    user_id=payer_id,
                    amount=self._normalize_positive_amount(item.get('amount'), 'payments.amount'),
                )
            )

        if len(payer_ids) != len(set(payer_ids)):
            raise ValidationError({'payments': 'Each payer can only have one contribution'})
        self._validate_plan_member_ids(plan, payer_ids, field_name='payments')
        if sum((item.amount for item in normalized), Decimal('0.00')) != amount:
            raise ValidationError({'payments': 'Payment contributions must equal the expense amount'})

        # The legacy payer field remains populated for older clients. The largest
        # contribution is stable and gives an intuitive primary payer.
        primary = max(normalized, key=lambda item: (item.amount, str(item.user_id)))
        return tuple(normalized), primary.user_id

    @staticmethod
    def _split_equal(amount: Decimal, count: int) -> list[Decimal]:
        base = (amount / Decimal(count)).quantize(Decimal('0.01'))
        amounts = [base for _ in range(count)]
        diff = amount - sum(amounts, Decimal('0.00'))
        cents = int((diff * Decimal('100')).to_integral_value())
        step = Decimal('0.01') if cents >= 0 else Decimal('-0.01')
        for index in range(abs(cents)):
            amounts[index % count] += step
        return [item.quantize(Decimal('0.01')) for item in amounts]

    @staticmethod
    def _split_percentage(amount: Decimal, percentages: list[Decimal]) -> list[Decimal]:
        amounts = [
            ((amount * percentage) / Decimal('100')).quantize(Decimal('0.01'))
            for percentage in percentages
        ]
        diff = amount - sum(amounts, Decimal('0.00'))
        if amounts:
            amounts[-1] = (amounts[-1] + diff).quantize(Decimal('0.01'))
        return amounts

    def _build_debt_suggestions(self, balances: list[UserBalance]) -> list[DebtSuggestion]:
        debtors = [
            {'balance': -item.net_balance, 'user': item}
            for item in balances
            if item.net_balance < Decimal('-0.00')
        ]
        creditors = [
            {'balance': item.net_balance, 'user': item}
            for item in balances
            if item.net_balance > Decimal('0.00')
        ]
        debtors.sort(key=lambda row: row['balance'], reverse=True)
        creditors.sort(key=lambda row: row['balance'], reverse=True)

        suggestions: list[DebtSuggestion] = []
        debtor_index = 0
        creditor_index = 0
        while debtor_index < len(debtors) and creditor_index < len(creditors):
            debtor = debtors[debtor_index]
            creditor = creditors[creditor_index]
            amount = min(debtor['balance'], creditor['balance']).quantize(Decimal('0.01'))
            if amount > Decimal('0.00'):
                from_user = debtor['user']
                to_user = creditor['user']
                suggestions.append(
                    DebtSuggestion(
                        from_user_id=from_user.user_id,
                        from_username=from_user.username,
                        from_full_name=from_user.full_name,
                        to_user_id=to_user.user_id,
                        to_username=to_user.username,
                        to_full_name=to_user.full_name,
                        amount=amount,
                    )
                )
            debtor['balance'] = (debtor['balance'] - amount).quantize(Decimal('0.01'))
            creditor['balance'] = (creditor['balance'] - amount).quantize(Decimal('0.01'))
            if debtor['balance'] <= Decimal('0.00'):
                debtor_index += 1
            if creditor['balance'] <= Decimal('0.00'):
                creditor_index += 1
        return suggestions

    def _available_debt(
        self,
        plan_id: UUID,
        viewer,
        from_user_id: UUID,
        to_user_id: UUID,
    ) -> Decimal:
        summary = self.get_balances(plan_id, viewer)
        for item in summary.settlement_suggestions:
            if item.from_user_id == from_user_id and item.to_user_id == to_user_id:
                return item.amount
        return Decimal('0.00')

    def _create_recurring_rule(
        self,
        *,
        plan_uuid: UUID,
        actor_id: UUID,
        amount: Decimal,
        currency: str,
        category: str,
        description: str,
        payment_note: str,
        split_strategy: str,
        participant_items,
        payment_items,
        recurrence: dict[str, Any],
    ):
        if self.recurring_expense_repo is None:
            raise ValidationError({'recurrence': 'Recurring expenses are unavailable'})
        frequency = str(recurrence.get('frequency', '')).strip().lower()
        if frequency not in {'weekly', 'monthly'}:
            raise ValidationError({'recurrence.frequency': 'Frequency must be weekly or monthly'})
        try:
            interval = int(recurrence.get('interval', 1))
        except (TypeError, ValueError) as exc:
            raise ValidationError({'recurrence.interval': 'Interval must be an integer'}) from exc
        if interval < 1 or interval > 52:
            raise ValidationError({'recurrence.interval': 'Interval must be between 1 and 52'})
        next_run_at = recurrence.get('next_run_at')
        if not isinstance(next_run_at, datetime):
            raise ValidationError({'recurrence.next_run_at': 'A valid next run time is required'})
        if timezone.is_naive(next_run_at):
            next_run_at = timezone.make_aware(next_run_at)
        if next_run_at <= timezone.now():
            raise ValidationError({'recurrence.next_run_at': 'Next run time must be in the future'})
        end_at = recurrence.get('end_at')
        if end_at is not None and timezone.is_naive(end_at):
            end_at = timezone.make_aware(end_at)
        if end_at is not None and end_at < next_run_at:
            raise ValidationError({'recurrence.end_at': 'End time cannot be before the next run'})
        return self.recurring_expense_repo.create(
            RecurringExpenseCreateData(
                plan_id=plan_uuid,
                created_by_user_id=actor_id,
                amount=amount,
                currency=currency,
                category=category,
                description=description,
                payment_note=payment_note,
                # Store resolved exact shares so future occurrences are stable
                # even when the source used a percentage split.
                split_strategy=SplitStrategy.EXACT.value,
                participants=tuple(
                    {
                        'user_id': str(item.user_id),
                        'amount': str(item.owed_amount),
                    }
                    for item in participant_items
                ),
                payments=tuple(
                    {'user_id': str(item.user_id), 'amount': str(item.amount)}
                    for item in payment_items
                ),
                frequency=frequency,
                interval=interval,
                next_run_at=next_run_at,
                end_at=end_at,
            )
        )

    @staticmethod
    def _next_recurrence_at(value: datetime, frequency: str, interval: int) -> datetime:
        if frequency == 'weekly':
            return value + timedelta(weeks=interval)
        month_index = value.month - 1 + interval
        year = value.year + month_index // 12
        month = month_index % 12 + 1
        day = min(value.day, calendar.monthrange(year, month)[1])
        return value.replace(year=year, month=month, day=day)

    @staticmethod
    def _rescale_amounts(
        values: list[Decimal],
        old_total: Decimal,
        new_total: Decimal,
    ) -> list[Decimal]:
        if not values:
            return []
        if old_total <= 0:
            return BudgetService._split_equal(new_total, len(values))
        scaled = [
            (value * new_total / old_total).quantize(Decimal('0.01'))
            for value in values
        ]
        scaled[-1] = (scaled[-1] + new_total - sum(scaled, Decimal('0.00'))).quantize(Decimal('0.01'))
        return scaled

    @staticmethod
    def _empty_balance_totals() -> dict[str, Decimal]:
        return {
            'paid': Decimal('0.00'),
            'owed': Decimal('0.00'),
            'settlement_paid': Decimal('0.00'),
            'settlement_received': Decimal('0.00'),
        }

    def _plan_member_profiles(self, plan) -> dict[UUID, dict[str, str]]:
        return {
            UUID(str(user.id)): {
                'username': user.username,
                'full_name': user.get_full_name() or user.username,
            }
            for user in plan.get_members()
        }

    def _validate_plan_member_ids(
        self,
        plan,
        user_ids: Iterable[UUID],
        *,
        field_name: str,
    ) -> None:
        member_ids = set(self._plan_member_profiles(plan).keys())
        invalid_ids = [str(user_id) for user_id in user_ids if user_id not in member_ids]
        if invalid_ids:
            raise ValidationError({field_name: f'Users are not plan participants: {", ".join(invalid_ids)}'})

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
    def _resolve_plan_user(plan, user, user_id: UUID):
        if hasattr(user, 'id'):
            return user
        if str(getattr(plan, 'creator_id', '')) == str(user_id):
            return plan.creator
        return next(
            (member for member in plan.get_members() if str(member.id) == str(user_id)),
            user,
        )

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
    def _normalize_split_strategy(value: str | None) -> str:
        normalized = (value or SplitStrategy.EQUAL.value).strip().lower()
        if normalized not in SplitStrategy.values():
            raise ValidationError({'split_strategy': 'Unsupported split strategy'})
        return normalized

    @staticmethod
    def _normalize_settlement_status(value: str | None) -> str:
        normalized = (value or SettlementStatus.PENDING.value).strip().lower()
        if normalized not in SettlementStatus.values():
            raise ValidationError({'status': 'Unsupported settlement status'})
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
