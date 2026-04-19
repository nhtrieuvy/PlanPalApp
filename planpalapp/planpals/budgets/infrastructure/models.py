from __future__ import annotations

from uuid import uuid4

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models


class Budget(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid4, editable=False)
    plan = models.OneToOneField(
        'planpals.Plan',
        on_delete=models.CASCADE,
        related_name='budget_record',
    )
    total_budget = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    currency = models.CharField(max_length=10, default='VND')
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_budgets'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['plan'], name='budget_plan_idx'),
            models.Index(fields=['created_at'], name='budget_created_idx'),
        ]

    def clean(self) -> None:
        if self.total_budget is not None and self.total_budget < 0:
            raise ValidationError('total_budget cannot be negative')

    def save(self, *args, **kwargs):
        self.full_clean()
        return super().save(*args, **kwargs)

    def __str__(self) -> str:
        return f'Budget<{self.plan_id}>'


class Expense(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid4, editable=False)
    plan = models.ForeignKey(
        'planpals.Plan',
        on_delete=models.CASCADE,
        related_name='expenses',
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='plan_expenses',
    )
    amount = models.DecimalField(max_digits=14, decimal_places=2)
    category = models.CharField(max_length=100, db_index=True)
    description = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_expenses'
        ordering = ['-created_at', '-id']
        indexes = [
            models.Index(fields=['plan', 'created_at'], name='expense_plan_created_idx'),
            models.Index(fields=['user'], name='expense_user_idx'),
            models.Index(fields=['category'], name='expense_category_idx'),
            models.Index(fields=['plan', 'category'], name='expense_plan_category_idx'),
            models.Index(fields=['created_at', 'id'], name='expense_cursor_idx'),
        ]

    def clean(self) -> None:
        if self.amount is None or self.amount <= 0:
            raise ValidationError('amount must be greater than zero')

    def save(self, *args, **kwargs):
        self.full_clean()
        return super().save(*args, **kwargs)

    def __str__(self) -> str:
        return f'Expense<{self.plan_id}:{self.amount}>'
