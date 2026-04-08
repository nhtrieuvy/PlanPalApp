from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAdminUser
from rest_framework.response import Response

from planpals.analytics.application.factories import get_analytics_service
from planpals.analytics.presentation.serializers import (
    AnalyticsSummaryQuerySerializer,
    AnalyticsTimeSeriesQuerySerializer,
    AnalyticsTopQuerySerializer,
    DashboardSummarySerializer,
    TimeSeriesPointSerializer,
    TopEntitiesSerializer,
)


class AnalyticsViewSet(viewsets.ViewSet):
    permission_classes = [IsAdminUser]

    @action(detail=False, methods=['get'], url_path='summary')
    def summary(self, request):
        serializer = AnalyticsSummaryQuerySerializer(data=request.query_params)
        serializer.is_valid(raise_exception=True)

        summary = get_analytics_service().get_dashboard_summary(
            range_key=serializer.validated_data['range'],
        )
        return Response(
            DashboardSummarySerializer(summary).data,
            status=status.HTTP_200_OK,
        )

    @action(detail=False, methods=['get'], url_path='timeseries')
    def timeseries(self, request):
        serializer = AnalyticsTimeSeriesQuerySerializer(data=request.query_params)
        serializer.is_valid(raise_exception=True)

        metric = serializer.validated_data['metric']
        range_key = serializer.validated_data['range']
        points = get_analytics_service().get_time_series(metric=metric, range_key=range_key)

        return Response(
            {
                'metric': metric,
                'range': range_key,
                'points': TimeSeriesPointSerializer(points, many=True).data,
            },
            status=status.HTTP_200_OK,
        )

    @action(detail=False, methods=['get'], url_path='top')
    def top(self, request):
        serializer = AnalyticsTopQuerySerializer(data=request.query_params)
        serializer.is_valid(raise_exception=True)

        snapshot = get_analytics_service().get_top_entities(
            range_key=serializer.validated_data['range'],
            limit=serializer.validated_data['limit'],
        )
        return Response(
            TopEntitiesSerializer(snapshot).data,
            status=status.HTTP_200_OK,
        )
