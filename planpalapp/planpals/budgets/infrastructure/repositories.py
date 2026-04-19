from __future__ import annotations

from datetime import timedelta
from math import ceil
from decimal import Decimal
from typing import Sequence
from uuid import UUID

from django.db.models import DecimalField, F, Sum, Value
from django.db.models.functions import Coalesce, Concat
from django.utils import timezone

from planpals.budgets.application.repositories import (
    BudgetRepository,
    BudgetUpsertData,
    ExpenseCreateData,
    ExpenseFilters,
    ExpensePage,
    ExpenseRepository,
)
from planpals.budgets.domain.entities import (
    Budget as BudgetEntity,
    BudgetBreakdownItem,
    BudgetTrendPoint,
    Expense as ExpenseEntity,
    ExpenseUser,
)
from planpals.budgets.infrastructure.models import Budget, Expense


class DjangoBudgetRepository(BudgetRepository):
    def get_budget_by_plan(self, plan_id: UUID) -> BudgetEntity | None:
        row = Budget.objects.filter(plan_id=plan_id).first()
        return self._to_entity(row) if row else None

    def ensure_budget(self, plan_id: UUID, currency: str = 'VND') -> BudgetEntity:
        row, _ = Budget.objects.get_or_create(
            plan_id=plan_id,
            defaults={'currency': currency, 'total_budget': 0},
        )
        return self._to_entity(row)

    def update_budget(self, data: BudgetUpsertData) -> BudgetEntity:
        row, _ = Budget.objects.update_or_create(
            plan_id=data.plan_id,
            defaults={
                'total_budget': data.total_budget,
                'currency': data.currency,
            },
        )
        return self._to_entity(row)

    @staticmethod
    def _to_entity(row: Budget) -> BudgetEntity:
        return BudgetEntity(
            id=row.id,
            plan_id=row.plan_id,
            total_budget=row.total_budget,
            currency=row.currency,
            created_at=row.created_at,
            updated_at=row.updated_at,
        )


class DjangoExpenseRepository(ExpenseRepository):
    AMOUNT_FIELD = DecimalField(max_digits=14, decimal_places=2)

    def create_expense(self, data: ExpenseCreateData) -> ExpenseEntity:
        row = Expense.objects.create(
            plan_id=data.plan_id,
            user_id=data.user_id,
            amount=data.amount,
            category=data.category,
            description=data.description,
        )
        return self._to_entity(row)

    def list_expenses(self, plan_id: UUID, filters: ExpenseFilters) -> ExpensePage:
        queryset = Expense.objects.filter(plan_id=plan_id).select_related('user')
        if filters.category:
            queryset = queryset.filter(category__iexact=filters.category)
        if filters.user_id:
            queryset = queryset.filter(user_id=filters.user_id)

        order_prefix = '' if filters.sort_direction == 'asc' else '-'
        order_field = 'amount' if filters.sort_by == 'amount' else 'created_at'
        queryset = queryset.order_by(f'{order_prefix}{order_field}', f'{order_prefix}id')

        total_count = queryset.count()
        page = max(filters.page, 1)
        page_size = max(filters.page_size, 1)
        start = (page - 1) * page_size
        end = start + page_size
        items = [self._to_entity(item) for item in queryset[start:end]]
        total_pages = ceil(total_count / page_size) if total_count else 0

        return ExpensePage(
            items=items,
            total_count=total_count,
            page=page,
            page_size=page_size,
            total_pages=total_pages,
            has_more=end < total_count,
        )

    def get_total_expense(self, plan_id: UUID):
        return Expense.objects.filter(plan_id=plan_id).aggregate(
            total=Coalesce(
                Sum('amount'),
                Value(Decimal('0.00')),
                output_field=self.AMOUNT_FIELD,
            )
        )['total']

    def count_expenses(self, plan_id: UUID) -> int:
        return Expense.objects.filter(plan_id=plan_id).count()

    def get_breakdown(self, plan_id: UUID) -> Sequence[BudgetBreakdownItem]:
        rows = (
            Expense.objects.filter(plan_id=plan_id)
            .values('user_id', 'user__username')
            .annotate(
                amount=Coalesce(
                    Sum('amount'),
                    Value(Decimal('0.00')),
                    output_field=self.AMOUNT_FIELD,
                ),
                full_name=Concat(
                    Coalesce(F('user__first_name'), Value('')),
                    Value(' '),
                    Coalesce(F('user__last_name'), Value('')),
                ),
            )
            .order_by('-amount', 'user__username')
        )
        return [
            BudgetBreakdownItem(
                user_id=row['user_id'],
                username=row['user__username'],
                full_name=str(row['full_name']).strip() or row['user__username'],
                amount=row['amount'],
            )
            for row in rows
        ]

    def get_spending_trend(
        self,
        plan_id: UUID,
        days: int = 30,
    ) -> Sequence[BudgetTrendPoint]:
        start_date = timezone.localdate() - timedelta(days=max(days - 1, 0))
        rows = (
            Expense.objects.filter(
                plan_id=plan_id,
                created_at__date__gte=start_date,
            )
            .values('created_at__date')
            .annotate(
                amount=Coalesce(
                    Sum('amount'),
                    Value(Decimal('0.00')),
                    output_field=self.AMOUNT_FIELD,
                )
            )
            .order_by('created_at__date')
        )
        return [
            BudgetTrendPoint(
                metric_date=row['created_at__date'],
                amount=row['amount'],
            )
            for row in rows
        ]

    def get_by_id(self, expense_id: UUID) -> ExpenseEntity | None:
        row = Expense.objects.select_related('user', 'plan').filter(id=expense_id).first()
        return self._to_entity(row) if row else None

    @staticmethod
    def _to_entity(row: Expense) -> ExpenseEntity:
        user = getattr(row, 'user', None)
        return ExpenseEntity(
            id=row.id,
            plan_id=row.plan_id,
            user_id=row.user_id,
            user=DjangoExpenseRepository._to_user_entity(user) if user is not None else None,
            amount=row.amount,
            category=row.category,
            description=row.description,
            created_at=row.created_at,
            updated_at=row.updated_at,
        )

    @staticmethod
    def _to_user_entity(user) -> ExpenseUser:
        full_name = user.get_full_name() or user.username
        initials = ''
        if user.first_name and user.last_name:
            initials = f'{user.first_name[0]}{user.last_name[0]}'.upper()
        elif user.first_name:
            initials = user.first_name[0].upper()
        elif user.username:
            initials = user.username[0].upper()
        return ExpenseUser(
            id=user.id,
            username=user.username,
            full_name=full_name,
            first_name=user.first_name or '',
            last_name=user.last_name or '',
            email=user.email or None,
            is_online=bool(getattr(user, 'is_online', False)),
            online_status=getattr(user, 'online_status', 'offline'),
            avatar_url=getattr(user, 'avatar_url', None),
            has_avatar=bool(getattr(user, 'has_avatar', False)),
            date_joined=getattr(user, 'date_joined', None),
            last_seen=getattr(user, 'last_seen', None),
            initials=initials,
        )
