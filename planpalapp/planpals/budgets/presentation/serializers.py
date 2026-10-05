from __future__ import annotations

import json

from rest_framework import serializers

from planpals.budgets.application.repositories import ExpenseFilters
from planpals.budgets.domain.entities import (
    BalanceSummary,
    BudgetSummary,
    Expense,
    ExpenseCreationResult,
    Settlement,
    SettlementStatus,
    SplitStrategy,
)


class BudgetUpsertSerializer(serializers.Serializer):
    total_budget = serializers.DecimalField(max_digits=14, decimal_places=2, min_value=0)
    currency = serializers.CharField(
        required=False,
        allow_blank=False,
        default='VND',
        max_length=10,
    )


class ExpenseCreateSerializer(serializers.Serializer):
    amount = serializers.DecimalField(max_digits=14, decimal_places=2, min_value=0.01)
    paid_by_user_id = serializers.UUIDField(required=False)
    currency = serializers.CharField(required=False, allow_blank=False, default='VND', max_length=10)
    category = serializers.CharField(max_length=100)
    description = serializers.CharField(required=False, allow_blank=True, default='')
    payment_note = serializers.CharField(required=False, allow_blank=True, default='', max_length=2000)
    receipt = serializers.FileField(required=False, allow_null=True, write_only=True)
    split_strategy = serializers.ChoiceField(
        choices=[(value, value) for value in SplitStrategy.values()],
        required=False,
        default=SplitStrategy.EQUAL.value,
    )
    participants = serializers.ListField(
        child=serializers.DictField(),
        required=False,
        allow_empty=False,
    )
    payments = serializers.ListField(
        child=serializers.DictField(),
        required=False,
        allow_empty=False,
    )
    recurrence = serializers.DictField(required=False, allow_null=True)

    def to_internal_value(self, data):
        mutable = data.copy() if hasattr(data, 'copy') else dict(data)
        for key in ('participants', 'payments', 'recurrence'):
            value = mutable.get(key)
            if isinstance(value, str):
                try:
                    mutable[key] = json.loads(value)
                except json.JSONDecodeError as exc:
                    raise serializers.ValidationError({key: 'Invalid JSON value'}) from exc
        return super().to_internal_value(mutable)

    def validate_receipt(self, value):
        return _validate_finance_attachment(value)

    def validate_recurrence(self, value):
        if value is None:
            return None
        frequency = str(value.get('frequency', '')).lower()
        if frequency not in {'weekly', 'monthly'}:
            raise serializers.ValidationError('Frequency must be weekly or monthly')
        try:
            interval = int(value.get('interval', 1))
        except (TypeError, ValueError) as exc:
            raise serializers.ValidationError('Interval must be an integer') from exc
        if interval < 1 or interval > 52:
            raise serializers.ValidationError('Interval must be between 1 and 52')
        next_run = serializers.DateTimeField().run_validation(value.get('next_run_at'))
        end_at = value.get('end_at')
        if end_at:
            end_at = serializers.DateTimeField().run_validation(end_at)
        return {
            'frequency': frequency,
            'interval': interval,
            'next_run_at': next_run,
            'end_at': end_at,
        }


class SettlementCreateSerializer(serializers.Serializer):
    plan_id = serializers.UUIDField()
    from_user_id = serializers.UUIDField()
    to_user_id = serializers.UUIDField()
    amount = serializers.DecimalField(max_digits=14, decimal_places=2, min_value=0.01)
    currency = serializers.CharField(required=False, allow_blank=False, default='VND', max_length=10)
    note = serializers.CharField(required=False, allow_blank=True, default='')
    payment_note = serializers.CharField(required=False, allow_blank=True, default='', max_length=2000)
    receipt = serializers.FileField(required=False, allow_null=True, write_only=True)

    def validate_receipt(self, value):
        return _validate_finance_attachment(value)


class SettlementActionSerializer(serializers.Serializer):
    rejection_reason = serializers.CharField(required=False, allow_blank=True, default='', max_length=1000)


class RecurringExpenseStatusSerializer(serializers.Serializer):
    is_active = serializers.BooleanField()


class ExpenseCorrectionSerializer(serializers.Serializer):
    amount = serializers.DecimalField(max_digits=14, decimal_places=2, min_value=0.01)
    category = serializers.CharField(max_length=100)
    description = serializers.CharField(required=False, allow_blank=True, default='')
    payment_note = serializers.CharField(required=False, allow_blank=True, default='', max_length=2000)
    reason = serializers.CharField(max_length=1000, allow_blank=False)
    receipt = serializers.FileField(required=False, allow_null=True, write_only=True)

    def validate_receipt(self, value):
        return _validate_finance_attachment(value)


def _validate_finance_attachment(value):
    if value is None:
        return value
    if getattr(value, 'size', 0) > 10 * 1024 * 1024:
        raise serializers.ValidationError('Receipt must be 10 MB or smaller')
    content_type = str(getattr(value, 'content_type', '')).lower()
    allowed = {'image/jpeg', 'image/png', 'image/webp', 'application/pdf'}
    if content_type and content_type not in allowed:
        raise serializers.ValidationError('Receipt must be a JPG, PNG, WEBP, or PDF file')
    return value


class ExpenseFilterSerializer(serializers.Serializer):
    category = serializers.CharField(required=False, allow_blank=False)
    user_id = serializers.UUIDField(required=False)
    sort_by = serializers.ChoiceField(
        choices=[('created_at', 'created_at'), ('amount', 'amount')],
        required=False,
        default='created_at',
    )
    sort_direction = serializers.ChoiceField(
        choices=[('asc', 'asc'), ('desc', 'desc')],
        required=False,
        default='desc',
    )
    page = serializers.IntegerField(required=False, min_value=1, default=1)
    page_size = serializers.IntegerField(required=False, min_value=1, max_value=100, default=20)

    def to_filters(self) -> ExpenseFilters:
        self.is_valid(raise_exception=True)
        return ExpenseFilters(**self.validated_data)


class ExpenseUserSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    username = serializers.CharField()
    first_name = serializers.CharField(allow_blank=True)
    last_name = serializers.CharField(allow_blank=True)
    email = serializers.CharField(allow_null=True, allow_blank=True, required=False)
    is_online = serializers.BooleanField()
    online_status = serializers.CharField()
    avatar_url = serializers.CharField(allow_null=True, allow_blank=True, required=False)
    has_avatar = serializers.BooleanField()
    date_joined = serializers.DateTimeField(allow_null=True, required=False)
    last_seen = serializers.DateTimeField(allow_null=True, required=False)
    full_name = serializers.CharField()
    initials = serializers.CharField()


class ExpenseSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    plan_id = serializers.UUIDField()
    user_id = serializers.UUIDField()
    user = ExpenseUserSerializer(allow_null=True)
    paid_by_user_id = serializers.UUIDField()
    paid_by_user = ExpenseUserSerializer(allow_null=True)
    amount = serializers.DecimalField(max_digits=14, decimal_places=2)
    currency = serializers.CharField()
    category = serializers.CharField()
    description = serializers.CharField()
    split_strategy = serializers.CharField()
    participants = serializers.ListField()
    payments = serializers.ListField()
    created_at = serializers.DateTimeField()
    updated_at = serializers.DateTimeField(allow_null=True)

    @classmethod
    def from_entity(cls, expense: Expense) -> dict:
        user = expense.user
        return {
            'id': expense.id,
            'plan_id': expense.plan_id,
            'user_id': expense.user_id,
            'user': cls._user_to_dict(user),
            'paid_by_user_id': expense.paid_by_user_id,
            'paid_by_user': cls._user_to_dict(expense.paid_by_user),
            'amount': expense.amount,
            'currency': expense.currency,
            'category': expense.category,
            'description': expense.description,
            'payment_note': expense.payment_note,
            'receipt_url': expense.receipt_url,
            'split_strategy': expense.split_strategy,
            'entry_type': expense.entry_type,
            'corrects_expense_id': expense.corrects_expense_id,
            'correction_reason': expense.correction_reason,
            'recurrence_id': expense.recurrence_id,
            'occurrence_at': expense.occurrence_at,
            'participants': [
                {
                    'id': participant.id,
                    'expense_id': participant.expense_id,
                    'user_id': participant.user_id,
                    'user': cls._user_to_dict(participant.user),
                    'owed_amount': participant.owed_amount,
                    'settled_amount': participant.settled_amount,
                    'balance': participant.balance,
                }
                for participant in expense.participants
            ],
            'payments': [
                {
                    'id': payment.id,
                    'expense_id': payment.expense_id,
                    'user_id': payment.user_id,
                    'user': cls._user_to_dict(payment.user),
                    'amount': payment.amount,
                    'created_at': payment.created_at,
                    'updated_at': payment.updated_at,
                }
                for payment in expense.payments
            ],
            'created_at': expense.created_at,
            'updated_at': expense.updated_at,
        }

    @staticmethod
    def _user_to_dict(user) -> dict | None:
        if user is None:
            return None
        return {
            'id': user.id,
            'username': user.username,
            'first_name': user.first_name,
            'last_name': user.last_name,
            'email': user.email,
            'is_online': user.is_online,
            'online_status': user.online_status,
            'avatar_url': user.avatar_url,
            'has_avatar': user.has_avatar,
            'date_joined': user.date_joined,
            'last_seen': user.last_seen,
            'full_name': user.full_name,
            'initials': user.initials,
        }


class BudgetBreakdownItemSerializer(serializers.Serializer):
    user = serializers.DictField()
    amount = serializers.DecimalField(max_digits=14, decimal_places=2)


class BudgetTrendPointSerializer(serializers.Serializer):
    date = serializers.DateField()
    amount = serializers.DecimalField(max_digits=14, decimal_places=2)


class ExpenseWarningSerializer(serializers.Serializer):
    code = serializers.CharField()
    level = serializers.CharField()
    message = serializers.CharField()
    data = serializers.DictField(required=False)


class BudgetSummarySerializer(serializers.Serializer):
    budget_id = serializers.UUIDField()
    plan_id = serializers.UUIDField()
    currency = serializers.CharField()
    total_budget = serializers.DecimalField(max_digits=14, decimal_places=2)
    total_spent = serializers.DecimalField(max_digits=14, decimal_places=2)
    remaining_budget = serializers.DecimalField(max_digits=14, decimal_places=2)
    spent_percentage = serializers.FloatField()
    near_limit = serializers.BooleanField()
    over_budget = serializers.BooleanField()
    expense_count = serializers.IntegerField()
    breakdown = BudgetBreakdownItemSerializer(many=True)
    trend = BudgetTrendPointSerializer(many=True)

    @classmethod
    def from_summary(cls, summary: BudgetSummary) -> dict:
        return {
            'budget_id': summary.budget.id,
            'plan_id': summary.budget.plan_id,
            'currency': summary.budget.currency,
            'total_budget': summary.budget.total_budget,
            'total_spent': summary.total_spent,
            'remaining_budget': summary.remaining_budget,
            'spent_percentage': summary.spent_percentage,
            'near_limit': summary.is_near_limit,
            'over_budget': summary.is_over_budget,
            'expense_count': summary.expense_count,
            'breakdown': [
                {
                    'user': {
                        'id': item.user_id,
                        'username': item.username,
                        'full_name': item.full_name,
                    },
                    'amount': item.amount,
                }
                for item in summary.breakdown
            ],
            'trend': [
                {
                    'date': point.metric_date,
                    'amount': point.amount,
                }
                for point in summary.trend
            ],
        }


class ExpenseCreateResponseSerializer(serializers.Serializer):
    expense = serializers.DictField()
    summary = serializers.DictField()
    warnings = ExpenseWarningSerializer(many=True)

    @classmethod
    def from_result(cls, result: ExpenseCreationResult) -> dict:
        return {
            'expense': ExpenseSerializer.from_entity(result.expense),
            'summary': BudgetSummarySerializer.from_summary(result.summary),
            'warnings': [
                {
                    'code': warning.code,
                    'level': warning.level,
                    'message': warning.message,
                    'data': warning.data,
                }
                for warning in result.warnings
            ],
        }


class BalanceSummarySerializer(serializers.Serializer):
    @classmethod
    def from_summary(cls, summary: BalanceSummary) -> dict:
        return {
            'plan_id': summary.plan_id,
            'currency': summary.currency,
            'total_expenses': summary.total_expenses,
            'balances': [
                {
                    'user': {
                        'id': item.user_id,
                        'username': item.username,
                        'full_name': item.full_name,
                    },
                    'total_paid': item.total_paid,
                    'total_owed': item.total_owed,
                    'settlement_paid': item.settlement_paid,
                    'settlement_received': item.settlement_received,
                    'net_balance': item.net_balance,
                }
                for item in summary.balances
            ],
            'settlement_suggestions': [
                {
                    'from_user': {
                        'id': item.from_user_id,
                        'username': item.from_username,
                        'full_name': item.from_full_name,
                    },
                    'to_user': {
                        'id': item.to_user_id,
                        'username': item.to_username,
                        'full_name': item.to_full_name,
                    },
                    'amount': item.amount,
                }
                for item in summary.settlement_suggestions
            ],
        }


class SettlementSerializer(serializers.Serializer):
    @classmethod
    def from_entity(cls, settlement: Settlement) -> dict:
        return {
            'id': settlement.id,
            'plan_id': settlement.plan_id,
            'from_user_id': settlement.from_user_id,
            'from_user': ExpenseSerializer._user_to_dict(settlement.from_user),
            'to_user_id': settlement.to_user_id,
            'to_user': ExpenseSerializer._user_to_dict(settlement.to_user),
            'amount': settlement.amount,
            'currency': settlement.currency,
            'status': settlement.status,
            'note': settlement.note,
            'payment_note': settlement.payment_note,
            'receipt_url': settlement.receipt_url,
            'requested_by_user_id': settlement.requested_by_user_id,
            'rejection_reason': settlement.rejection_reason,
            'settled_at': settlement.settled_at,
            'responded_at': settlement.responded_at,
            'created_at': settlement.created_at,
            'updated_at': settlement.updated_at,
        }


class FinanceInsightsSerializer(serializers.Serializer):
    @classmethod
    def from_entity(cls, insights) -> dict:
        return {
            'plan_id': insights.plan_id,
            'currency': insights.currency,
            'total_spent': insights.total_spent,
            'categories': [
                {
                    'category': item.category,
                    'amount': item.amount,
                    'percentage': item.percentage,
                }
                for item in insights.categories
            ],
            'forecast': {
                'daily_average': insights.forecast.daily_average,
                'projected_total': insights.forecast.projected_total,
                'projected_remaining': insights.forecast.projected_remaining,
                'projected_over_budget': insights.forecast.projected_over_budget,
                'forecast_date': insights.forecast.forecast_date,
            },
            'pending_settlement_count': insights.pending_settlement_count,
            'pending_settlement_amount': insights.pending_settlement_amount,
        }


class RecurringExpenseSerializer(serializers.Serializer):
    @classmethod
    def from_entity(cls, recurring) -> dict:
        return {
            'id': recurring.id,
            'plan_id': recurring.plan_id,
            'created_by_user_id': recurring.created_by_user_id,
            'amount': recurring.amount,
            'currency': recurring.currency,
            'category': recurring.category,
            'description': recurring.description,
            'payment_note': recurring.payment_note,
            'split_strategy': recurring.split_strategy,
            'frequency': recurring.frequency,
            'interval': recurring.interval,
            'next_run_at': recurring.next_run_at,
            'end_at': recurring.end_at,
            'last_run_at': recurring.last_run_at,
            'is_active': recurring.is_active,
            'created_at': recurring.created_at,
            'updated_at': recurring.updated_at,
        }
