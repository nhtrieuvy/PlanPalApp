"""
Analytics repository contracts.
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from datetime import date
from typing import Sequence

from planpals.analytics.domain.entities import (
    DailyMetric,
    MetricWindowAggregate,
    TopEntitiesSnapshot,
)


class AnalyticsRepository(ABC):
    @abstractmethod
    def aggregate_day(self, metric_date: date) -> DailyMetric:
        ...

    @abstractmethod
    def upsert_daily_metric(self, metric: DailyMetric) -> DailyMetric:
        ...

    @abstractmethod
    def get_daily_metrics(self, date_from: date, date_to: date) -> Sequence[DailyMetric]:
        ...

    @abstractmethod
    def get_latest_metric_date(self) -> date | None:
        ...

    @abstractmethod
    def get_summary_metrics(self, date_from: date, date_to: date) -> MetricWindowAggregate:
        ...

    @abstractmethod
    def get_growth_metrics(
        self,
        current_from: date,
        current_to: date,
        previous_from: date,
        previous_to: date,
    ) -> dict[str, float]:
        ...

    @abstractmethod
    def get_top_entities(
        self,
        date_from: date,
        date_to: date,
        limit: int = 5,
    ) -> TopEntitiesSnapshot:
        ...
