from __future__ import annotations

from rest_framework import serializers

from planpals.budgets.application.repositories import ExpenseFilters
from planpals.budgets.domain.entities import BudgetSummary, Expense, ExpenseCreationResult


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
    category = serializers.CharField(max_length=100)
    description = serializers.CharField(required=False, allow_blank=True, default='')


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
    amount = serializers.DecimalField(max_digits=14, decimal_places=2)
    category = serializers.CharField()
    description = serializers.CharField()
    created_at = serializers.DateTimeField()
    updated_at = serializers.DateTimeField(allow_null=True)

    @classmethod
    def from_entity(cls, expense: Expense) -> dict:
        user = expense.user
        return {
            'id': expense.id,
            'plan_id': expense.plan_id,
            'user_id': expense.user_id,
            'user': (
                {
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
                if user is not None
                else None
            ),
            'amount': expense.amount,
            'category': expense.category,
            'description': expense.description,
            'created_at': expense.created_at,
            'updated_at': expense.updated_at,
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
