from __future__ import annotations

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


class SettlementCreateSerializer(serializers.Serializer):
    plan_id = serializers.UUIDField()
    from_user_id = serializers.UUIDField()
    to_user_id = serializers.UUIDField()
    amount = serializers.DecimalField(max_digits=14, decimal_places=2, min_value=0.01)
    currency = serializers.CharField(required=False, allow_blank=False, default='VND', max_length=10)
    status = serializers.ChoiceField(
        choices=[(value, value) for value in SettlementStatus.values()],
        required=False,
        default=SettlementStatus.COMPLETED.value,
    )
    note = serializers.CharField(required=False, allow_blank=True, default='')


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
            'split_strategy': expense.split_strategy,
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
            'settled_at': settlement.settled_at,
            'created_at': settlement.created_at,
            'updated_at': settlement.updated_at,
        }
