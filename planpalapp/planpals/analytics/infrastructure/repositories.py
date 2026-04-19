"""
Analytics repository implementations.
"""
from __future__ import annotations

from datetime import date, datetime, time, timedelta
from decimal import Decimal, ROUND_HALF_UP
from typing import Sequence

from django.db.models import Count, Sum
from django.utils import timezone

from planpals.analytics.application.repositories import AnalyticsRepository
from planpals.analytics.domain.entities import (
    DailyMetric as DailyMetricEntity,
    MetricWindowAggregate,
    TopEntitiesSnapshot,
    TopEntity,
)
from planpals.analytics.infrastructure.models import DailyMetric
from planpals.audit.domain.entities import AuditAction, AuditResourceType
from planpals.audit.infrastructure.models import AuditLog
from planpals.groups.infrastructure.models import Group
from planpals.notifications.infrastructure.models import Notification
from planpals.plans.infrastructure.models import Plan


class DjangoAnalyticsRepository(AnalyticsRepository):
    def aggregate_day(self, metric_date: date) -> DailyMetricEntity:
        day_start, day_end = self._day_bounds(metric_date)
        mau_start = day_start - timedelta(days=29)
        audit_logs = AuditLog.objects.filter(created_at__gte=day_start, created_at__lt=day_end)

        active_users = audit_logs.exclude(user_id__isnull=True).values('user_id').distinct().count()
        monthly_active_users = (
            AuditLog.objects.filter(created_at__gte=mau_start, created_at__lt=day_end)
            .exclude(user_id__isnull=True)
            .values('user_id')
            .distinct()
            .count()
        )
        plans_created = audit_logs.filter(action=AuditAction.CREATE_PLAN.value).count()
        plans_completed = audit_logs.filter(action=AuditAction.COMPLETE_PLAN.value).count()
        expense_logs = audit_logs.filter(action=AuditAction.CREATE_EXPENSE.value)
        expenses_created = expense_logs.count()
        expense_total_amount = self._sum_expense_amount(expense_logs)
        group_joins = audit_logs.filter(action=AuditAction.JOIN_GROUP.value).count()
        notifications_opened = self._sum_notification_opens(
            audit_logs.filter(action=AuditAction.NOTIFICATION_OPENED.value)
        )
        notifications_sent = Notification.objects.filter(
            created_at__gte=day_start,
            created_at__lt=day_end,
        ).count()

        return DailyMetricEntity(
            metric_date=metric_date,
            active_users=active_users,
            monthly_active_users=monthly_active_users,
            plans_created=plans_created,
            plans_completed=plans_completed,
            expenses_created=expenses_created,
            expense_total_amount=expense_total_amount,
            group_joins=group_joins,
            notifications_sent=notifications_sent,
            notifications_opened=notifications_opened,
            notification_open_rate=self._rate(notifications_opened, notifications_sent),
            plan_creation_rate=self._rate(plans_created, active_users),
            plan_completion_rate=self._rate(plans_completed, active_users),
            group_join_rate=self._rate(group_joins, active_users),
        )

    def upsert_daily_metric(self, metric: DailyMetricEntity) -> DailyMetricEntity:
        row, _ = DailyMetric.objects.update_or_create(
            date=metric.metric_date,
            defaults={
                'active_users': metric.active_users,
                'monthly_active_users': metric.monthly_active_users,
                'plans_created': metric.plans_created,
                'plans_completed': metric.plans_completed,
                'expenses_created': metric.expenses_created,
                'expense_total_amount': self._decimal(metric.expense_total_amount),
                'group_joins': metric.group_joins,
                'notifications_sent': metric.notifications_sent,
                'notifications_opened': metric.notifications_opened,
                'notification_open_rate': self._decimal(metric.notification_open_rate),
                'plan_creation_rate': self._decimal(metric.plan_creation_rate),
                'plan_completion_rate': self._decimal(metric.plan_completion_rate),
                'group_join_rate': self._decimal(metric.group_join_rate),
            },
        )
        return self._to_entity(row)

    def get_daily_metrics(self, date_from: date, date_to: date) -> Sequence[DailyMetricEntity]:
        queryset = DailyMetric.objects.filter(date__gte=date_from, date__lte=date_to).order_by('date')
        return [self._to_entity(item) for item in queryset]

    def get_latest_metric_date(self) -> date | None:
        return DailyMetric.objects.order_by('-date').values_list('date', flat=True).first()

    def get_summary_metrics(self, date_from: date, date_to: date) -> MetricWindowAggregate:
        queryset = DailyMetric.objects.filter(date__gte=date_from, date__lte=date_to)
        latest = queryset.order_by('-date').first()
        sums = queryset.aggregate(
            active_user_total=Sum('active_users'),
            plans_created=Sum('plans_created'),
            plans_completed=Sum('plans_completed'),
            expenses_created=Sum('expenses_created'),
            expense_total_amount=Sum('expense_total_amount'),
            group_joins=Sum('group_joins'),
            notifications_sent=Sum('notifications_sent'),
            notifications_opened=Sum('notifications_opened'),
        )
        return MetricWindowAggregate(
            latest_date=latest.date if latest else None,
            latest_active_users=latest.active_users if latest else 0,
            latest_monthly_active_users=latest.monthly_active_users if latest else 0,
            active_user_total=int(sums.get('active_user_total') or 0),
            plans_created=int(sums.get('plans_created') or 0),
            plans_completed=int(sums.get('plans_completed') or 0),
            expenses_created=int(sums.get('expenses_created') or 0),
            expense_total_amount=float(sums.get('expense_total_amount') or 0),
            group_joins=int(sums.get('group_joins') or 0),
            notifications_sent=int(sums.get('notifications_sent') or 0),
            notifications_opened=int(sums.get('notifications_opened') or 0),
        )

    def get_growth_metrics(
        self,
        current_from: date,
        current_to: date,
        previous_from: date,
        previous_to: date,
    ) -> dict[str, float]:
        current = self.get_summary_metrics(current_from, current_to)
        previous = self.get_summary_metrics(previous_from, previous_to)

        current_plan_completion_rate = self._rate(current.plans_completed, current.active_user_total)
        previous_plan_completion_rate = self._rate(previous.plans_completed, previous.active_user_total)
        current_group_join_rate = self._rate(current.group_joins, current.active_user_total)
        previous_group_join_rate = self._rate(previous.group_joins, previous.active_user_total)
        current_notification_open_rate = self._rate(
            current.notifications_opened,
            current.notifications_sent,
        )
        previous_notification_open_rate = self._rate(
            previous.notifications_opened,
            previous.notifications_sent,
        )

        return {
            'dau': self._percent_change(current.latest_active_users, previous.latest_active_users),
            'mau': self._percent_change(
                current.latest_monthly_active_users,
                previous.latest_monthly_active_users,
            ),
            'plan_creation_rate': self._percent_change(
                self._rate(current.plans_created, current.active_user_total),
                self._rate(previous.plans_created, previous.active_user_total),
            ),
            'plan_completion_rate': self._percent_change(
                current_plan_completion_rate,
                previous_plan_completion_rate,
            ),
            'group_join_rate': self._percent_change(
                current_group_join_rate,
                previous_group_join_rate,
            ),
            'notification_open_rate': self._percent_change(
                current_notification_open_rate,
                previous_notification_open_rate,
            ),
        }

    def get_top_entities(
        self,
        date_from: date,
        date_to: date,
        limit: int = 5,
    ) -> TopEntitiesSnapshot:
        start_dt, _ = self._day_bounds(date_from)
        _, end_exclusive = self._day_bounds(date_to)

        plan_rows = list(
            AuditLog.objects.filter(
                created_at__gte=start_dt,
                created_at__lt=end_exclusive,
                resource_type=AuditResourceType.PLAN.value,
                action__in=[
                    AuditAction.CREATE_PLAN.value,
                    AuditAction.UPDATE_PLAN.value,
                    AuditAction.COMPLETE_PLAN.value,
                    AuditAction.DELETE_PLAN.value,
                ],
                resource_id__isnull=False,
            )
            .values('resource_id')
            .annotate(total=Count('id'))
            .order_by('-total')[:limit]
        )
        group_rows = list(
            AuditLog.objects.filter(
                created_at__gte=start_dt,
                created_at__lt=end_exclusive,
                resource_type=AuditResourceType.GROUP.value,
                action__in=[
                    AuditAction.JOIN_GROUP.value,
                    AuditAction.LEAVE_GROUP.value,
                    AuditAction.CHANGE_ROLE.value,
                    AuditAction.DELETE_GROUP.value,
                ],
                resource_id__isnull=False,
            )
            .values('resource_id')
            .annotate(total=Count('id'))
            .order_by('-total')[:limit]
        )

        return TopEntitiesSnapshot(
            range_key='custom',
            plans=tuple(self._build_top_entities('plan', plan_rows)),
            groups=tuple(self._build_top_entities('group', group_rows)),
        )

    def _build_top_entities(self, resource_type: str, rows: list[dict]) -> list[TopEntity]:
        entity_ids = [row['resource_id'] for row in rows if row.get('resource_id')]
        if resource_type == AuditResourceType.PLAN.value:
            name_map = {
                str(item['id']): item['title']
                for item in Plan.objects.filter(id__in=entity_ids).values('id', 'title')
            }
            fallback_key = 'title'
        else:
            name_map = {
                str(item['id']): item['name']
                for item in Group.objects.filter(id__in=entity_ids).values('id', 'name')
            }
            fallback_key = 'group_name'

        if len(name_map) < len(entity_ids):
            missing_ids = [entity_id for entity_id in entity_ids if str(entity_id) not in name_map]
            for audit_log in (
                AuditLog.objects.filter(resource_id__in=missing_ids)
                .exclude(metadata={})
                .order_by('resource_id', '-created_at')
            ):
                resource_id = str(audit_log.resource_id)
                if resource_id in name_map:
                    continue
                candidate_name = (audit_log.metadata or {}).get(fallback_key)
                if candidate_name:
                    name_map[resource_id] = str(candidate_name)

        return [
            TopEntity(
                id=str(row['resource_id']),
                name=name_map.get(str(row['resource_id']), f'{resource_type.title()} {str(row["resource_id"])[:8]}'),
                resource_type=resource_type,
                metric_label='events',
                value=int(row['total']),
            )
            for row in rows
        ]

    def _sum_notification_opens(self, queryset) -> int:
        total = 0
        for metadata in queryset.values_list('metadata', flat=True):
            raw_count = metadata.get('notification_count', 1) if isinstance(metadata, dict) else 1
            try:
                total += max(int(raw_count), 0)
            except (TypeError, ValueError):
                total += 1
        return total

    @staticmethod
    def _sum_expense_amount(queryset) -> float:
        total = Decimal('0')
        for metadata in queryset.values_list('metadata', flat=True):
            raw_amount = metadata.get('amount', 0) if isinstance(metadata, dict) else 0
            try:
                total += Decimal(str(raw_amount))
            except Exception:
                continue
        return float(total)

    def _to_entity(self, metric: DailyMetric) -> DailyMetricEntity:
        return DailyMetricEntity(
            metric_date=metric.date,
            active_users=metric.active_users,
            monthly_active_users=metric.monthly_active_users,
            plans_created=metric.plans_created,
            plans_completed=metric.plans_completed,
            expenses_created=metric.expenses_created,
            expense_total_amount=float(metric.expense_total_amount),
            group_joins=metric.group_joins,
            notifications_sent=metric.notifications_sent,
            notifications_opened=metric.notifications_opened,
            notification_open_rate=float(metric.notification_open_rate),
            plan_creation_rate=float(metric.plan_creation_rate),
            plan_completion_rate=float(metric.plan_completion_rate),
            group_join_rate=float(metric.group_join_rate),
        )

    @staticmethod
    def _day_bounds(metric_date: date) -> tuple[datetime, datetime]:
        start = timezone.make_aware(datetime.combine(metric_date, time.min))
        end = start + timedelta(days=1)
        return start, end

    @staticmethod
    def _decimal(value: float) -> Decimal:
        return Decimal(str(value)).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)

    @staticmethod
    def _rate(numerator: int, denominator: int) -> float:
        if denominator <= 0:
            return 0.0
        return round((numerator / denominator) * 100.0, 2)

    @staticmethod
    def _percent_change(current: float, previous: float) -> float:
        if previous == 0:
            return 0.0 if current == 0 else 100.0
        return round(((current - previous) / previous) * 100.0, 2)
