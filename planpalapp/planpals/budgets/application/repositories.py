from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from decimal import Decimal
from typing import Optional, Sequence
from uuid import UUID

from planpals.budgets.domain.entities import (
    Budget,
    BudgetBreakdownItem,
    BudgetTrendPoint,
    Expense,
    ExpenseParticipant,
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
    split_strategy: str = 'equal'
    participants: Sequence['ExpenseParticipantCreateData'] = ()


@dataclass(frozen=True)
class ExpenseParticipantCreateData:
    user_id: UUID
    owed_amount: Decimal
    settled_amount: Decimal = Decimal('0.00')
    balance: Decimal = Decimal('0.00')


@dataclass(frozen=True)
class SettlementCreateData:
    plan_id: UUID
    from_user_id: UUID
    to_user_id: UUID
    amount: Decimal
    currency: str
    status: str = 'completed'
    note: str = ''


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


class SettlementRepository(ABC):
    @abstractmethod
    def create_settlement(self, data: SettlementCreateData) -> Settlement:
        ...

    @abstractmethod
    def list_settlements(self, plan_id: UUID) -> Sequence[Settlement]:
        ...
