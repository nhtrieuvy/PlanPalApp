"""
Analytics application services.
"""
from __future__ import annotations

from datetime import date, timedelta

from django.utils import timezone
from rest_framework.exceptions import ValidationError

from planpals.analytics.application.repositories import AnalyticsRepository
from planpals.analytics.domain.entities import (
    AnalyticsMetric,
    AnalyticsRange,
    DashboardSummary,
    DashboardTotals,
    DailyMetric,
    SummaryMetric,
    TimeSeriesPoint,
    TopEntitiesSnapshot,
)
from planpals.shared.cache import CacheKeys, CacheTTL, CachePort


class AnalyticsService:
    def __init__(self, analytics_repo: AnalyticsRepository, cache_service: CachePort):
        self.analytics_repo = analytics_repo
        self.cache_service = cache_service

    def aggregate_daily_metrics(self, metric_date: date | None = None) -> DailyMetric:
        target_date = metric_date or (timezone.localdate() - timedelta(days=1))
        snapshot = self.analytics_repo.aggregate_day(target_date)
        stored = self.analytics_repo.upsert_daily_metric(snapshot)
        self.invalidate_dashboard_cache()
        return stored

    def get_dashboard_summary(self, range_key: str = AnalyticsRange.LAST_30_DAYS.value) -> DashboardSummary:
        normalized_range = self._normalize_range(range_key)
        cache_key = CacheKeys.analytics_summary(normalized_range.value)

        def compute() -> DashboardSummary:
            date_from, date_to = self._resolve_dates(normalized_range)
            previous_from = date_from - timedelta(days=normalized_range.days)
            previous_to = date_from - timedelta(days=1)

            summary = self.analytics_repo.get_summary_metrics(date_from, date_to)
            growth = self.analytics_repo.get_growth_metrics(
                date_from,
                date_to,
                previous_from,
                previous_to,
            )

            current_date = summary.latest_date or date_to
            plan_creation_rate = self._rate(summary.plans_created, summary.active_user_total)
            plan_completion_rate = self._rate(summary.plans_completed, summary.active_user_total)
            group_join_rate = self._rate(summary.group_joins, summary.active_user_total)
            notification_open_rate = self._rate(
                summary.notifications_opened,
                summary.notifications_sent,
            )

            return DashboardSummary(
                range_key=normalized_range.value,
                current_date=current_date,
                generated_at=timezone.now(),
                dau=SummaryMetric(
                    label='Daily Active Users',
                    value=float(summary.latest_active_users),
                    change_pct=growth.get('dau', 0.0),
                ),
                mau=SummaryMetric(
                    label='Monthly Active Users',
                    value=float(summary.latest_monthly_active_users),
                    change_pct=growth.get('mau', 0.0),
                ),
                plan_creation_rate=SummaryMetric(
                    label='Plan Creation Rate',
                    value=plan_creation_rate,
                    change_pct=growth.get('plan_creation_rate', 0.0),
                ),
                plan_completion_rate=SummaryMetric(
                    label='Plan Completion Rate',
                    value=plan_completion_rate,
                    change_pct=growth.get('plan_completion_rate', 0.0),
                ),
                group_join_rate=SummaryMetric(
                    label='Group Join Rate',
                    value=group_join_rate,
                    change_pct=growth.get('group_join_rate', 0.0),
                ),
                notification_open_rate=SummaryMetric(
                    label='Notification Open Rate',
                    value=notification_open_rate,
                    change_pct=growth.get('notification_open_rate', 0.0),
                ),
                totals=DashboardTotals(
                    plans_created=summary.plans_created,
                    plans_completed=summary.plans_completed,
                    expenses_created=summary.expenses_created,
                    expense_total_amount=summary.expense_total_amount,
                    group_joins=summary.group_joins,
                    notifications_sent=summary.notifications_sent,
                    notifications_opened=summary.notifications_opened,
                ),
            )

        return self.cache_service.get_or_set(
            cache_key,
            compute,
            CacheTTL.ANALYTICS_SUMMARY,
        )

    def get_time_series(
        self,
        metric: str,
        range_key: str = AnalyticsRange.LAST_30_DAYS.value,
    ) -> list[TimeSeriesPoint]:
        normalized_metric = self._normalize_metric(metric)
        normalized_range = self._normalize_range(range_key)
        cache_key = CacheKeys.analytics_timeseries(normalized_metric.value, normalized_range.value)

        def compute() -> list[TimeSeriesPoint]:
            date_from, date_to = self._resolve_dates(normalized_range)
            rows = {
                item.metric_date: item
                for item in self.analytics_repo.get_daily_metrics(date_from, date_to)
            }

            points: list[TimeSeriesPoint] = []
            cursor = date_from
            while cursor <= date_to:
                metric_row = rows.get(cursor)
                value = self._metric_value(metric_row, normalized_metric) if metric_row else 0.0
                points.append(TimeSeriesPoint(date=cursor, value=value))
                cursor += timedelta(days=1)
            return points

        return self.cache_service.get_or_set(
            cache_key,
            compute,
            CacheTTL.ANALYTICS_TIMESERIES,
        )

    def get_top_entities(
        self,
        range_key: str = AnalyticsRange.LAST_30_DAYS.value,
        limit: int = 5,
    ) -> TopEntitiesSnapshot:
        normalized_range = self._normalize_range(range_key)
        normalized_limit = min(max(limit, 1), 20)
        cache_key = CacheKeys.analytics_top(normalized_range.value, normalized_limit)

        def compute() -> TopEntitiesSnapshot:
            date_from, date_to = self._resolve_dates(normalized_range)
            snapshot = self.analytics_repo.get_top_entities(date_from, date_to, normalized_limit)
            return TopEntitiesSnapshot(
                range_key=normalized_range.value,
                plans=snapshot.plans,
                groups=snapshot.groups,
            )

        return self.cache_service.get_or_set(
            cache_key,
            compute,
            CacheTTL.ANALYTICS_TOP,
        )

    def invalidate_dashboard_cache(self) -> None:
        self.cache_service.delete_pattern(CacheKeys.analytics_pattern())

    @staticmethod
    def _rate(numerator: int, denominator: int) -> float:
        if denominator <= 0:
            return 0.0
        return round((numerator / denominator) * 100.0, 2)

    def _resolve_dates(self, range_key: AnalyticsRange) -> tuple[date, date]:
        date_to = self.analytics_repo.get_latest_metric_date() or timezone.localdate()
        date_from = date_to - timedelta(days=range_key.days - 1)
        return date_from, date_to

    @staticmethod
    def _metric_value(metric: DailyMetric | None, selected_metric: AnalyticsMetric) -> float:
        if metric is None:
            return 0.0
        value = {
            AnalyticsMetric.DAILY_ACTIVE_USERS: metric.active_users,
            AnalyticsMetric.MONTHLY_ACTIVE_USERS: metric.monthly_active_users,
            AnalyticsMetric.PLANS_CREATED: metric.plans_created,
            AnalyticsMetric.PLANS_COMPLETED: metric.plans_completed,
            AnalyticsMetric.EXPENSES_CREATED: metric.expenses_created,
            AnalyticsMetric.EXPENSE_TOTAL_AMOUNT: metric.expense_total_amount,
            AnalyticsMetric.PLAN_CREATION_RATE: metric.plan_creation_rate,
            AnalyticsMetric.PLAN_COMPLETION_RATE: metric.plan_completion_rate,
            AnalyticsMetric.GROUP_JOINS: metric.group_joins,
            AnalyticsMetric.GROUP_JOIN_RATE: metric.group_join_rate,
            AnalyticsMetric.NOTIFICATION_OPEN_RATE: metric.notification_open_rate,
        }[selected_metric]
        return float(value)

    @staticmethod
    def _normalize_metric(metric: str) -> AnalyticsMetric:
        try:
            return AnalyticsMetric(str(metric).strip().lower())
        except ValueError as exc:
            raise ValidationError({'metric': 'Unsupported metric'}) from exc

    @staticmethod
    def _normalize_range(range_key: str) -> AnalyticsRange:
        try:
            return AnalyticsRange(str(range_key).strip().lower())
        except ValueError as exc:
            raise ValidationError({'range': 'Unsupported range'}) from exc
