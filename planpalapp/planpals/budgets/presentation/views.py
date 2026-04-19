from __future__ import annotations

from urllib.parse import urlencode

from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from planpals.budgets.application.factories import get_budget_service
from planpals.budgets.presentation.serializers import (
    BudgetSummarySerializer,
    BudgetUpsertSerializer,
    ExpenseCreateResponseSerializer,
    ExpenseCreateSerializer,
    ExpenseFilterSerializer,
    ExpenseSerializer,
)


class PlanBudgetView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, plan_id):
        summary = get_budget_service().get_budget_summary(plan_id, request.user)
        return Response(
            BudgetSummarySerializer.from_summary(summary),
            status=status.HTTP_200_OK,
        )

    def post(self, request, plan_id):
        serializer = BudgetUpsertSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        summary = get_budget_service().create_or_update_budget(
            plan_id,
            request.user,
            total_budget=serializer.validated_data['total_budget'],
            currency=serializer.validated_data.get('currency', 'VND'),
        )
        return Response(
            BudgetSummarySerializer.from_summary(summary),
            status=status.HTTP_200_OK,
        )


class PlanExpenseListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, plan_id):
        filter_serializer = ExpenseFilterSerializer(data=request.query_params)
        filters = filter_serializer.to_filters()
        page = get_budget_service().list_expenses(plan_id, request.user, filters)

        return Response(
            {
                'count': page.total_count,
                'total_pages': page.total_pages,
                'current_page': page.page,
                'page_size': page.page_size,
                'next': self._build_next_link(request, page) if page.has_more else None,
                'previous': self._build_previous_link(request, page),
                'results': [
                    ExpenseSerializer.from_entity(item)
                    for item in page.items
                ],
            },
            status=status.HTTP_200_OK,
        )

    def post(self, request, plan_id):
        serializer = ExpenseCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        result = get_budget_service().add_expense(
            plan_id,
            request.user,
            amount=serializer.validated_data['amount'],
            category=serializer.validated_data['category'],
            description=serializer.validated_data.get('description', ''),
        )
        return Response(
            ExpenseCreateResponseSerializer.from_result(result),
            status=status.HTTP_201_CREATED,
        )

    def _build_next_link(self, request, page) -> str | None:
        params = request.query_params.copy()
        params['page'] = page.page + 1
        query_string = urlencode(params, doseq=True)
        return request.build_absolute_uri(f'{request.path}?{query_string}')

    def _build_previous_link(self, request, page) -> str | None:
        if page.page <= 1:
            return None
        params = request.query_params.copy()
        params['page'] = page.page - 1
        query_string = urlencode(params, doseq=True)
        return request.build_absolute_uri(f'{request.path}?{query_string}')
