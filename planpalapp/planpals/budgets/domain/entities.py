from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime
from decimal import Decimal
from enum import Enum
from typing import Any
from uuid import UUID


class BudgetSortField(str, Enum):
    CREATED_AT = 'created_at'
    AMOUNT = 'amount'

    @classmethod
    def values(cls) -> tuple[str, ...]:
        return tuple(item.value for item in cls)


@dataclass(frozen=True)
class Budget:
    id: UUID
    plan_id: UUID
    total_budget: Decimal
    currency: str
    created_at: datetime
    updated_at: datetime | None = None


@dataclass(frozen=True)
class ExpenseUser:
    id: UUID
    username: str
    full_name: str
    first_name: str = ''
    last_name: str = ''
    email: str | None = None
    is_online: bool = False
    online_status: str = 'offline'
    avatar_url: str | None = None
    has_avatar: bool = False
    date_joined: datetime | None = None
    last_seen: datetime | None = None
    initials: str = ''


@dataclass(frozen=True)
class Expense:
    id: UUID
    plan_id: UUID
    user_id: UUID
    user: ExpenseUser | None
    amount: Decimal
    category: str
    description: str
    created_at: datetime
    updated_at: datetime | None = None


@dataclass(frozen=True)
class BudgetBreakdownItem:
    user_id: UUID
    username: str
    full_name: str
    amount: Decimal


@dataclass(frozen=True)
class BudgetTrendPoint:
    metric_date: date
    amount: Decimal


@dataclass(frozen=True)
class ExpenseWarning:
    code: str
    level: str
    message: str
    data: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True)
class BudgetSummary:
    budget: Budget
    total_spent: Decimal
    remaining_budget: Decimal
    breakdown: tuple[BudgetBreakdownItem, ...] = ()
    trend: tuple[BudgetTrendPoint, ...] = ()
    expense_count: int = 0

    @property
    def spent_percentage(self) -> float:
        if self.budget.total_budget <= Decimal('0'):
            return 0.0
        return round(
            float((self.total_spent / self.budget.total_budget) * Decimal('100')),
            2,
        )

    @property
    def is_near_limit(self) -> bool:
        return (
            self.budget.total_budget > Decimal('0')
            and self.total_spent < self.budget.total_budget
            and self.spent_percentage >= 80.0
        )

    @property
    def is_over_budget(self) -> bool:
        return (
            self.budget.total_budget > Decimal('0')
            and self.total_spent > self.budget.total_budget
        )


@dataclass(frozen=True)
class ExpenseCreationResult:
    expense: Expense
    summary: BudgetSummary
    warnings: tuple[ExpenseWarning, ...] = ()
