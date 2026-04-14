"""
Analytics ORM models.
"""
from __future__ import annotations

from django.db import models


class DailyMetric(models.Model):
    date = models.DateField(unique=True, db_index=True)
    active_users = models.PositiveIntegerField(default=0)
    monthly_active_users = models.PositiveIntegerField(default=0)
    plans_created = models.PositiveIntegerField(default=0)
    plans_completed = models.PositiveIntegerField(default=0)
    expenses_created = models.PositiveIntegerField(default=0)
    expense_total_amount = models.DecimalField(max_digits=16, decimal_places=2, default=0)
    group_joins = models.PositiveIntegerField(default=0)
    notifications_sent = models.PositiveIntegerField(default=0)
    notifications_opened = models.PositiveIntegerField(default=0)
    notification_open_rate = models.DecimalField(max_digits=7, decimal_places=2, default=0)
    plan_creation_rate = models.DecimalField(max_digits=7, decimal_places=2, default=0)
    plan_completion_rate = models.DecimalField(max_digits=7, decimal_places=2, default=0)
    group_join_rate = models.DecimalField(max_digits=7, decimal_places=2, default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_daily_metrics'
        ordering = ['date']
        indexes = [
            models.Index(fields=['date'], name='analytics_metric_date_idx'),
        ]

    def __str__(self) -> str:
        return f'DailyMetric<{self.date}>'
