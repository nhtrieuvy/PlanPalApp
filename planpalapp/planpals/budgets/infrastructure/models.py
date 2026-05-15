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
    SPLIT_EQUAL = 'equal'
    SPLIT_PERCENTAGE = 'percentage'
    SPLIT_EXACT = 'exact'
    SPLIT_STRATEGY_CHOICES = [
        (SPLIT_EQUAL, 'Equal'),
        (SPLIT_PERCENTAGE, 'Percentage'),
        (SPLIT_EXACT, 'Exact amount'),
    ]

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
    paid_by_user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='paid_plan_expenses',
        null=True,
        blank=True,
    )
    amount = models.DecimalField(max_digits=14, decimal_places=2)
    currency = models.CharField(max_length=10, default='VND')
    category = models.CharField(max_length=100, db_index=True)
    description = models.TextField(blank=True)
    split_strategy = models.CharField(
        max_length=20,
        choices=SPLIT_STRATEGY_CHOICES,
        default=SPLIT_EQUAL,
        db_index=True,
    )
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_expenses'
        ordering = ['-created_at', '-id']
        indexes = [
            models.Index(fields=['plan', 'created_at'], name='expense_plan_created_idx'),
            models.Index(fields=['user'], name='expense_user_idx'),
            models.Index(fields=['paid_by_user'], name='expense_paid_by_idx'),
            models.Index(fields=['category'], name='expense_category_idx'),
            models.Index(fields=['plan', 'category'], name='expense_plan_category_idx'),
            models.Index(fields=['plan', 'split_strategy'], name='expense_plan_split_idx'),
            models.Index(fields=['created_at', 'id'], name='expense_cursor_idx'),
        ]

    def clean(self) -> None:
        if self.amount is None or self.amount <= 0:
            raise ValidationError('amount must be greater than zero')

    def save(self, *args, **kwargs):
        if self.paid_by_user_id is None:
            self.paid_by_user_id = self.user_id
        self.full_clean()
        return super().save(*args, **kwargs)

    def __str__(self) -> str:
        return f'Expense<{self.plan_id}:{self.amount}>'


class ExpenseParticipant(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid4, editable=False)
    expense = models.ForeignKey(
        Expense,
        on_delete=models.CASCADE,
        related_name='participants',
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='expense_participations',
    )
    owed_amount = models.DecimalField(max_digits=14, decimal_places=2)
    settled_amount = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    balance = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_expense_participants'
        ordering = ['expense_id', 'user_id']
        constraints = [
            models.UniqueConstraint(
                fields=['expense', 'user'],
                name='unique_expense_participant',
            ),
        ]
        indexes = [
            models.Index(fields=['expense', 'user'], name='expense_participant_user_idx'),
            models.Index(fields=['user'], name='expense_part_user_idx'),
            models.Index(fields=['expense'], name='expense_part_expense_idx'),
        ]

    def clean(self) -> None:
        if self.owed_amount is None or self.owed_amount < 0:
            raise ValidationError('owed_amount cannot be negative')
        if self.settled_amount is None or self.settled_amount < 0:
            raise ValidationError('settled_amount cannot be negative')

    def save(self, *args, **kwargs):
        self.full_clean()
        return super().save(*args, **kwargs)


class Settlement(models.Model):
    STATUS_PENDING = 'pending'
    STATUS_COMPLETED = 'completed'
    STATUS_CANCELLED = 'cancelled'
    STATUS_CHOICES = [
        (STATUS_PENDING, 'Pending'),
        (STATUS_COMPLETED, 'Completed'),
        (STATUS_CANCELLED, 'Cancelled'),
    ]

    id = models.UUIDField(primary_key=True, default=uuid4, editable=False)
    plan = models.ForeignKey(
        'planpals.Plan',
        on_delete=models.CASCADE,
        related_name='settlements',
    )
    from_user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='settlements_paid',
    )
    to_user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='settlements_received',
    )
    amount = models.DecimalField(max_digits=14, decimal_places=2)
    currency = models.CharField(max_length=10, default='VND')
    status = models.CharField(
        max_length=20,
        choices=STATUS_CHOICES,
        default=STATUS_COMPLETED,
        db_index=True,
    )
    note = models.TextField(blank=True)
    settled_at = models.DateTimeField(null=True, blank=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_settlements'
        ordering = ['-created_at', '-id']
        indexes = [
            models.Index(fields=['plan', 'status'], name='settlement_plan_status_idx'),
            models.Index(fields=['from_user'], name='settlement_from_user_idx'),
            models.Index(fields=['to_user'], name='settlement_to_user_idx'),
            models.Index(fields=['settled_at'], name='settlement_settled_at_idx'),
        ]

    def clean(self) -> None:
        if self.amount is None or self.amount <= 0:
            raise ValidationError('amount must be greater than zero')
        if self.from_user_id and self.to_user_id and self.from_user_id == self.to_user_id:
            raise ValidationError('from_user and to_user must be different')

    def save(self, *args, **kwargs):
        self.full_clean()
        return super().save(*args, **kwargs)
