from __future__ import annotations

from datetime import datetime, timedelta
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
    ExpenseParticipantCreateData,
    ExpenseRepository,
    RecurringExpenseCreateData,
    RecurringExpenseRepository,
    SettlementCreateData,
    SettlementRepository,
)
from planpals.budgets.domain.entities import (
    Budget as BudgetEntity,
    BudgetBreakdownItem,
    BudgetTrendPoint,
    Expense as ExpenseEntity,
    ExpenseParticipant as ExpenseParticipantEntity,
    ExpensePayment as ExpensePaymentEntity,
    ExpenseUser,
    RecurringExpense as RecurringExpenseEntity,
    Settlement as SettlementEntity,
)
from planpals.budgets.infrastructure.models import (
    Budget,
    Expense,
    ExpenseParticipant,
    ExpensePayment,
    RecurringExpense,
    Settlement,
)


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

    @staticmethod
    def _effective_queryset():
        # A correction is a complete replacement entry. Only leaf entries affect
        # totals; ancestors remain immutable for audit and rollback inspection.
        return Expense.objects.filter(
            corrections__isnull=True,
            deleted_at__isnull=True,
        )

    def create_expense(self, data: ExpenseCreateData) -> ExpenseEntity:
        receipt = data.receipt
        if receipt is None and data.copy_receipt_from_expense_id is not None:
            receipt = (
                Expense.objects
                .filter(id=data.copy_receipt_from_expense_id)
                .values_list('receipt', flat=True)
                .first()
            )
        row = Expense.objects.create(
            plan_id=data.plan_id,
            user_id=data.user_id,
            paid_by_user_id=data.paid_by_user_id,
            amount=data.amount,
            currency=data.currency,
            category=data.category,
            description=data.description,
            payment_note=data.payment_note,
            receipt=receipt,
            split_strategy=data.split_strategy,
            entry_type=data.entry_type,
            corrects_expense_id=data.corrects_expense_id,
            correction_reason=data.correction_reason,
            recurrence_id=data.recurrence_id,
            occurrence_at=data.occurrence_at,
        )
        if data.participants:
            ExpenseParticipant.objects.bulk_create(
                [
                    ExpenseParticipant(
                        expense=row,
                        user_id=participant.user_id,
                        owed_amount=participant.owed_amount,
                        settled_amount=participant.settled_amount,
                        balance=participant.balance,
                    )
                    for participant in data.participants
                ],
                batch_size=500,
            )
        if data.payments:
            ExpensePayment.objects.bulk_create(
                [
                    ExpensePayment(
                        expense=row,
                        user_id=payment.user_id,
                        amount=payment.amount,
                    )
                    for payment in data.payments
                ],
                batch_size=500,
            )
        row = (
            self._effective_queryset()
            .select_related('user', 'paid_by_user')
            .prefetch_related('participants__user', 'payments__user')
            .get(id=row.id)
        )
        return self._to_entity(row)

    def list_expenses(self, plan_id: UUID, filters: ExpenseFilters) -> ExpensePage:
        queryset = (
            self._effective_queryset()
            .filter(plan_id=plan_id)
            .select_related('user', 'paid_by_user')
            .prefetch_related('participants__user', 'payments__user')
        )
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
        return self._effective_queryset().filter(plan_id=plan_id).aggregate(
            total=Coalesce(
                Sum('amount'),
                Value(Decimal('0.00')),
                output_field=self.AMOUNT_FIELD,
            )
        )['total']

    def count_expenses(self, plan_id: UUID) -> int:
        return self._effective_queryset().filter(plan_id=plan_id).count()

    def get_breakdown(self, plan_id: UUID) -> Sequence[BudgetBreakdownItem]:
        rows = (
            ExpensePayment.objects.filter(
                expense__plan_id=plan_id,
                expense__corrections__isnull=True,
                expense__deleted_at__isnull=True,
            )
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
            self._effective_queryset().filter(
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
        row = (
            self._effective_queryset()
            .select_related('user', 'paid_by_user', 'plan')
            .prefetch_related('participants__user', 'payments__user')
            .filter(id=expense_id)
            .first()
        )
        return self._to_entity(row) if row else None

    def list_expenses_for_balances(self, plan_id: UUID) -> Sequence[ExpenseEntity]:
        rows = (
            self._effective_queryset()
            .filter(plan_id=plan_id)
            .select_related('user', 'paid_by_user')
            .prefetch_related('participants__user', 'payments__user')
            .order_by('created_at', 'id')
        )
        return [self._to_entity(row) for row in rows]

    def get_participant_user_ids(self, expense_id: UUID) -> Sequence[UUID]:
        return list(
            ExpenseParticipant.objects.filter(expense_id=expense_id)
            .values_list('user_id', flat=True)
        )

    def get_effective_expense(
        self,
        expense_id: UUID,
        *,
        for_update: bool = False,
    ) -> ExpenseEntity | None:
        queryset = self._effective_queryset()
        if for_update:
            queryset = queryset.select_for_update()
        row = (
            queryset.select_related('user', 'paid_by_user')
            .prefetch_related('participants__user', 'payments__user')
            .filter(id=expense_id)
            .first()
        )
        return self._to_entity(row) if row else None

    def soft_delete(self, expense_id: UUID, *, deleted_by_user_id: UUID) -> None:
        self._effective_queryset().filter(id=expense_id).update(
            deleted_at=timezone.now(),
            deleted_by_id=deleted_by_user_id,
        )

    def get_category_totals(self, plan_id: UUID) -> Sequence[tuple[str, Decimal]]:
        rows = (
            self._effective_queryset()
            .filter(plan_id=plan_id)
            .values('category')
            .annotate(
                total=Coalesce(
                    Sum('amount'),
                    Value(Decimal('0.00')),
                    output_field=self.AMOUNT_FIELD,
                )
            )
            .order_by('-total', 'category')
        )
        return [(row['category'], row['total']) for row in rows]

    @staticmethod
    def _to_entity(row: Expense) -> ExpenseEntity:
        user = getattr(row, 'user', None)
        paid_by_user = getattr(row, 'paid_by_user', None) or user
        participants = tuple(
            DjangoExpenseRepository._participant_to_entity(participant)
            for participant in getattr(row, 'participants', []).all()
        )
        payments = tuple(
            DjangoExpenseRepository._payment_to_entity(payment)
            for payment in getattr(row, 'payments', []).all()
        )
        return ExpenseEntity(
            id=row.id,
            plan_id=row.plan_id,
            user_id=row.user_id,
            user=DjangoExpenseRepository._to_user_entity(user) if user is not None else None,
            paid_by_user_id=row.paid_by_user_id or row.user_id,
            paid_by_user=(
                DjangoExpenseRepository._to_user_entity(paid_by_user)
                if paid_by_user is not None
                else None
            ),
            amount=row.amount,
            currency=row.currency,
            category=row.category,
            description=row.description,
            payment_note=row.payment_note,
            split_strategy=row.split_strategy,
            receipt_url=row.receipt_url,
            entry_type=row.entry_type,
            corrects_expense_id=row.corrects_expense_id,
            correction_reason=row.correction_reason,
            recurrence_id=row.recurrence_id,
            occurrence_at=row.occurrence_at,
            created_at=row.created_at,
            updated_at=row.updated_at,
            participants=participants,
            payments=payments,
        )

    @staticmethod
    def _participant_to_entity(row: ExpenseParticipant) -> ExpenseParticipantEntity:
        user = getattr(row, 'user', None)
        return ExpenseParticipantEntity(
            id=row.id,
            expense_id=row.expense_id,
            user_id=row.user_id,
            user=DjangoExpenseRepository._to_user_entity(user) if user is not None else None,
            owed_amount=row.owed_amount,
            settled_amount=row.settled_amount,
            balance=row.balance,
            created_at=row.created_at,
            updated_at=row.updated_at,
        )

    @staticmethod
    def _payment_to_entity(row: ExpensePayment) -> ExpensePaymentEntity:
        user = getattr(row, 'user', None)
        return ExpensePaymentEntity(
            id=row.id,
            expense_id=row.expense_id,
            user_id=row.user_id,
            user=DjangoExpenseRepository._to_user_entity(user) if user is not None else None,
            amount=row.amount,
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


class DjangoSettlementRepository(SettlementRepository):
    def lock_plan_ledger(self, plan_id: UUID) -> None:
        # Every plan has one budget row, making it a stable mutex for all
        # settlement checks without coupling the application layer to ORM.
        Budget.objects.select_for_update().get(plan_id=plan_id)

    def create_settlement(self, data: SettlementCreateData) -> SettlementEntity:
        row = Settlement.objects.create(
            plan_id=data.plan_id,
            from_user_id=data.from_user_id,
            to_user_id=data.to_user_id,
            amount=data.amount,
            currency=data.currency,
            status=data.status,
            note=data.note,
            payment_note=data.payment_note,
            receipt=data.receipt,
            requested_by_id=data.requested_by_user_id,
            settled_at=timezone.now() if data.status == Settlement.STATUS_COMPLETED else None,
        )
        row = (
            Settlement.objects
            .select_related('from_user', 'to_user')
            .get(id=row.id)
        )
        return self._to_entity(row)

    def list_settlements(self, plan_id: UUID) -> Sequence[SettlementEntity]:
        rows = (
            Settlement.objects
            .filter(plan_id=plan_id)
            .select_related('from_user', 'to_user')
            .order_by('created_at', 'id')
        )
        return [self._to_entity(row) for row in rows]

    def get_by_id(
        self,
        settlement_id: UUID,
        *,
        for_update: bool = False,
    ) -> SettlementEntity | None:
        queryset = Settlement.objects
        if for_update:
            queryset = queryset.select_for_update()
        row = (
            queryset.select_related('from_user', 'to_user')
            .filter(id=settlement_id)
            .first()
        )
        return self._to_entity(row) if row else None

    def transition(
        self,
        settlement_id: UUID,
        *,
        status: str,
        rejection_reason: str = '',
    ) -> SettlementEntity:
        now = timezone.now()
        updates = {
            'status': status,
            'responded_at': now,
            'rejection_reason': rejection_reason,
            'settled_at': now if status == Settlement.STATUS_COMPLETED else None,
        }
        Settlement.objects.filter(id=settlement_id).update(**updates)
        return self.get_by_id(settlement_id)

    def list_pending_before(
        self,
        cutoff: datetime,
        limit: int = 500,
    ) -> Sequence[SettlementEntity]:
        rows = (
            Settlement.objects.filter(
                status=Settlement.STATUS_PENDING,
                created_at__lte=cutoff,
            )
            .select_related('from_user', 'to_user')
            .order_by('created_at', 'id')[:limit]
        )
        return [self._to_entity(row) for row in rows]

    @staticmethod
    def _to_entity(row: Settlement) -> SettlementEntity:
        return SettlementEntity(
            id=row.id,
            plan_id=row.plan_id,
            from_user_id=row.from_user_id,
            from_user=(
                DjangoExpenseRepository._to_user_entity(row.from_user)
                if row.from_user is not None
                else None
            ),
            to_user_id=row.to_user_id,
            to_user=(
                DjangoExpenseRepository._to_user_entity(row.to_user)
                if row.to_user is not None
                else None
            ),
            amount=row.amount,
            currency=row.currency,
            status=row.status,
            note=row.note,
            payment_note=row.payment_note,
            receipt_url=row.receipt_url,
            requested_by_user_id=row.requested_by_id,
            rejection_reason=row.rejection_reason,
            settled_at=row.settled_at,
            responded_at=row.responded_at,
            created_at=row.created_at,
            updated_at=row.updated_at,
        )


class DjangoRecurringExpenseRepository(RecurringExpenseRepository):
    def create(self, data: RecurringExpenseCreateData) -> RecurringExpenseEntity:
        row = RecurringExpense.objects.create(
            plan_id=data.plan_id,
            created_by_id=data.created_by_user_id,
            amount=data.amount,
            currency=data.currency,
            category=data.category,
            description=data.description,
            payment_note=data.payment_note,
            split_strategy=data.split_strategy,
            participants=list(data.participants),
            payments=list(data.payments),
            frequency=data.frequency,
            interval=data.interval,
            next_run_at=data.next_run_at,
            end_at=data.end_at,
        )
        return self._to_entity(row)

    def list_due(self, now: datetime, limit: int = 100) -> Sequence[RecurringExpenseEntity]:
        rows = (
            RecurringExpense.objects.select_for_update(skip_locked=True)
            .filter(is_active=True, next_run_at__lte=now)
            .order_by('next_run_at', 'id')[:limit]
        )
        return [self._to_entity(row) for row in rows]

    def list_for_plan(self, plan_id: UUID) -> Sequence[RecurringExpenseEntity]:
        rows = RecurringExpense.objects.filter(plan_id=plan_id).order_by(
            '-is_active', 'next_run_at', 'id'
        )
        return [self._to_entity(row) for row in rows]

    def get_by_id(
        self,
        recurring_id: UUID,
        *,
        for_update: bool = False,
    ) -> RecurringExpenseEntity | None:
        queryset = RecurringExpense.objects
        if for_update:
            queryset = queryset.select_for_update()
        row = queryset.filter(id=recurring_id).first()
        return self._to_entity(row) if row else None

    def advance(
        self,
        recurring_id: UUID,
        *,
        last_run_at: datetime,
        next_run_at: datetime,
        is_active: bool,
    ) -> RecurringExpenseEntity:
        RecurringExpense.objects.filter(id=recurring_id).update(
            last_run_at=last_run_at,
            next_run_at=next_run_at,
            is_active=is_active,
        )
        return self._to_entity(RecurringExpense.objects.get(id=recurring_id))

    def set_active(
        self,
        recurring_id: UUID,
        *,
        is_active: bool,
        next_run_at: datetime | None = None,
    ) -> RecurringExpenseEntity:
        updates = {'is_active': is_active}
        if next_run_at is not None:
            updates['next_run_at'] = next_run_at
        RecurringExpense.objects.filter(id=recurring_id).update(**updates)
        return self._to_entity(RecurringExpense.objects.get(id=recurring_id))

    @staticmethod
    def _to_entity(row: RecurringExpense) -> RecurringExpenseEntity:
        return RecurringExpenseEntity(
            id=row.id,
            plan_id=row.plan_id,
            created_by_user_id=row.created_by_id,
            amount=row.amount,
            currency=row.currency,
            category=row.category,
            description=row.description,
            payment_note=row.payment_note,
            split_strategy=row.split_strategy,
            participants=tuple(row.participants or ()),
            payments=tuple(row.payments or ()),
            frequency=row.frequency,
            interval=row.interval,
            next_run_at=row.next_run_at,
            end_at=row.end_at,
            last_run_at=row.last_run_at,
            is_active=row.is_active,
            created_at=row.created_at,
            updated_at=row.updated_at,
        )
