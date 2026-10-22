from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from decimal import Decimal
from datetime import datetime
from typing import Any, Optional, Sequence
from uuid import UUID

from planpals.budgets.domain.entities import (
    Budget,
    BudgetBreakdownItem,
    BudgetTrendPoint,
    Expense,
    ExpenseParticipant,
    RecurringExpense,
    Settlement,
)


@dataclass(frozen=True)
class BudgetUpsertData:
    plan_id: UUID
    total_budget: Decimal
    currency: str


@dataclass(frozen=True)
class ExpenseCreateData:
    plan_id: UUID
    user_id: UUID
    paid_by_user_id: UUID
    amount: Decimal
    currency: str
    category: str
    description: str = ''
    payment_note: str = ''
    receipt: Any = None
    copy_receipt_from_expense_id: UUID | None = None
    split_strategy: str = 'equal'
    participants: Sequence['ExpenseParticipantCreateData'] = ()
    payments: Sequence['ExpensePaymentCreateData'] = ()
    entry_type: str = 'original'
    corrects_expense_id: UUID | None = None
    correction_reason: str = ''
    recurrence_id: UUID | None = None
    occurrence_at: datetime | None = None


@dataclass(frozen=True)
class ExpenseParticipantCreateData:
    user_id: UUID
    owed_amount: Decimal
    settled_amount: Decimal = Decimal('0.00')
    balance: Decimal = Decimal('0.00')


@dataclass(frozen=True)
class ExpensePaymentCreateData:
    user_id: UUID
    amount: Decimal


@dataclass(frozen=True)
class SettlementCreateData:
    plan_id: UUID
    from_user_id: UUID
    to_user_id: UUID
    amount: Decimal
    currency: str
    requested_by_user_id: UUID
    status: str = 'pending'
    note: str = ''
    payment_note: str = ''
    receipt: Any = None


@dataclass(frozen=True)
class RecurringExpenseCreateData:
    plan_id: UUID
    created_by_user_id: UUID
    amount: Decimal
    currency: str
    category: str
    description: str
    payment_note: str
    split_strategy: str
    participants: Sequence[dict[str, Any]]
    payments: Sequence[dict[str, Any]]
    frequency: str
    interval: int
    next_run_at: datetime
    end_at: datetime | None = None


@dataclass(frozen=True)
class ExpenseFilters:
    category: Optional[str] = None
    user_id: Optional[UUID] = None
    sort_by: str = 'created_at'
    sort_direction: str = 'desc'
    page: int = 1
    page_size: int = 20


@dataclass(frozen=True)
class ExpensePage:
    items: Sequence[Expense]
    total_count: int
    page: int
    page_size: int
    total_pages: int
    has_more: bool


class BudgetRepository(ABC):
    @abstractmethod
    def get_budget_by_plan(self, plan_id: UUID) -> Budget | None:
        ...

    @abstractmethod
    def ensure_budget(self, plan_id: UUID, currency: str = 'VND') -> Budget:
        ...

    @abstractmethod
    def update_budget(self, data: BudgetUpsertData) -> Budget:
        ...


class ExpenseRepository(ABC):
    @abstractmethod
    def create_expense(self, data: ExpenseCreateData) -> Expense:
        ...

    @abstractmethod
    def list_expenses(self, plan_id: UUID, filters: ExpenseFilters) -> ExpensePage:
        ...

    @abstractmethod
    def get_total_expense(self, plan_id: UUID) -> Decimal:
        ...

    @abstractmethod
    def count_expenses(self, plan_id: UUID) -> int:
        ...

    @abstractmethod
    def get_breakdown(self, plan_id: UUID) -> Sequence[BudgetBreakdownItem]:
        ...

    @abstractmethod
    def get_spending_trend(
        self,
        plan_id: UUID,
        days: int = 30,
    ) -> Sequence[BudgetTrendPoint]:
        ...

    @abstractmethod
    def get_by_id(self, expense_id: UUID) -> Expense | None:
        ...

    @abstractmethod
    def list_expenses_for_balances(self, plan_id: UUID) -> Sequence[Expense]:
        ...

    @abstractmethod
    def get_participant_user_ids(self, expense_id: UUID) -> Sequence[UUID]:
        ...

    @abstractmethod
    def get_effective_expense(self, expense_id: UUID, *, for_update: bool = False) -> Expense | None:
        ...

    @abstractmethod
    def soft_delete(self, expense_id: UUID, *, deleted_by_user_id: UUID) -> None:
        ...

    @abstractmethod
    def get_category_totals(self, plan_id: UUID) -> Sequence[tuple[str, Decimal]]:
        ...


class SettlementRepository(ABC):
    @abstractmethod
    def lock_plan_ledger(self, plan_id: UUID) -> None:
        """Serialize settlement balance checks for one plan transaction."""
        ...

    @abstractmethod
    def create_settlement(self, data: SettlementCreateData) -> Settlement:
        ...

    @abstractmethod
    def list_settlements(self, plan_id: UUID) -> Sequence[Settlement]:
        ...

    @abstractmethod
    def get_by_id(self, settlement_id: UUID, *, for_update: bool = False) -> Settlement | None:
        ...

    @abstractmethod
    def transition(self, settlement_id: UUID, *, status: str, rejection_reason: str = '') -> Settlement:
        ...

    @abstractmethod
    def list_pending_before(self, cutoff: datetime, limit: int = 500) -> Sequence[Settlement]:
        ...


class RecurringExpenseRepository(ABC):
    @abstractmethod
    def create(self, data: RecurringExpenseCreateData) -> RecurringExpense:
        ...

    @abstractmethod
    def list_due(self, now: datetime, limit: int = 100) -> Sequence[RecurringExpense]:
        ...

    @abstractmethod
    def list_for_plan(self, plan_id: UUID) -> Sequence[RecurringExpense]:
        ...

    @abstractmethod
    def get_by_id(self, recurring_id: UUID, *, for_update: bool = False) -> RecurringExpense | None:
        ...

    @abstractmethod
    def advance(self, recurring_id: UUID, *, last_run_at: datetime, next_run_at: datetime, is_active: bool) -> RecurringExpense:
        ...

    @abstractmethod
    def set_active(
        self,
        recurring_id: UUID,
        *,
        is_active: bool,
        next_run_at: datetime | None = None,
    ) -> RecurringExpense:
        ...
