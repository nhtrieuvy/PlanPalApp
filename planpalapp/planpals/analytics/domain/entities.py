"""
Analytics domain entities.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime
from enum import Enum


class AnalyticsMetric(str, Enum):
    DAILY_ACTIVE_USERS = 'dau'
    MONTHLY_ACTIVE_USERS = 'mau'
    PLANS_CREATED = 'plans_created'
    PLANS_COMPLETED = 'plans_completed'
    EXPENSES_CREATED = 'expenses_created'
    EXPENSE_TOTAL_AMOUNT = 'expense_total_amount'
    PLAN_CREATION_RATE = 'plan_creation_rate'
    PLAN_COMPLETION_RATE = 'plan_completion_rate'
    GROUP_JOINS = 'group_joins'
    GROUP_JOIN_RATE = 'group_join_rate'
    NOTIFICATION_OPEN_RATE = 'notification_open_rate'

    @classmethod
    def values(cls) -> tuple[str, ...]:
        return tuple(metric.value for metric in cls)

    @classmethod
    def choices(cls) -> list[tuple[str, str]]:
        return [(metric.value, metric.value.replace('_', ' ').title()) for metric in cls]


class AnalyticsRange(str, Enum):
    LAST_7_DAYS = '7d'
    LAST_30_DAYS = '30d'
    LAST_90_DAYS = '90d'
    LAST_180_DAYS = '180d'

    @property
    def days(self) -> int:
        return {
            AnalyticsRange.LAST_7_DAYS: 7,
            AnalyticsRange.LAST_30_DAYS: 30,
            AnalyticsRange.LAST_90_DAYS: 90,
            AnalyticsRange.LAST_180_DAYS: 180,
        }[self]

    @classmethod
    def values(cls) -> tuple[str, ...]:
        return tuple(item.value for item in cls)


@dataclass(frozen=True)
class DailyMetric:
    metric_date: date
    active_users: int = 0
    monthly_active_users: int = 0
    plans_created: int = 0
    plans_completed: int = 0
    expenses_created: int = 0
    expense_total_amount: float = 0.0
    group_joins: int = 0
    notifications_sent: int = 0
    notifications_opened: int = 0
    notification_open_rate: float = 0.0
    plan_creation_rate: float = 0.0
    plan_completion_rate: float = 0.0
    group_join_rate: float = 0.0


@dataclass(frozen=True)
class MetricWindowAggregate:
    latest_date: date | None = None
    latest_active_users: int = 0
    latest_monthly_active_users: int = 0
    active_user_total: int = 0
    plans_created: int = 0
    plans_completed: int = 0
    expenses_created: int = 0
    expense_total_amount: float = 0.0
    group_joins: int = 0
    notifications_sent: int = 0
    notifications_opened: int = 0


@dataclass(frozen=True)
class SummaryMetric:
    label: str
    value: float
    change_pct: float


@dataclass(frozen=True)
class DashboardTotals:
    plans_created: int = 0
    plans_completed: int = 0
    expenses_created: int = 0
    expense_total_amount: float = 0.0
    group_joins: int = 0
    notifications_sent: int = 0
    notifications_opened: int = 0


@dataclass(frozen=True)
class DashboardSummary:
    range_key: str
    current_date: date
    generated_at: datetime
    dau: SummaryMetric
    mau: SummaryMetric
    plan_creation_rate: SummaryMetric
    plan_completion_rate: SummaryMetric
    group_join_rate: SummaryMetric
    notification_open_rate: SummaryMetric
    totals: DashboardTotals = field(default_factory=DashboardTotals)


@dataclass(frozen=True)
class TimeSeriesPoint:
    date: date
    value: float


@dataclass(frozen=True)
class TopEntity:
    id: str
    name: str
    resource_type: str
    metric_label: str
    value: int


@dataclass(frozen=True)
class TopEntitiesSnapshot:
    range_key: str
    plans: tuple[TopEntity, ...] = ()
    groups: tuple[TopEntity, ...] = ()
