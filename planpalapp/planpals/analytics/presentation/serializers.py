from rest_framework import serializers

from planpals.analytics.domain.entities import AnalyticsMetric, AnalyticsRange


class AnalyticsSummaryQuerySerializer(serializers.Serializer):
    range = serializers.ChoiceField(
        choices=[(value, value) for value in AnalyticsRange.values()],
        required=False,
        default=AnalyticsRange.LAST_30_DAYS.value,
    )


class AnalyticsTimeSeriesQuerySerializer(serializers.Serializer):
    metric = serializers.ChoiceField(
        choices=[(value, value) for value in AnalyticsMetric.values()],
    )
    range = serializers.ChoiceField(
        choices=[(value, value) for value in AnalyticsRange.values()],
        required=False,
        default=AnalyticsRange.LAST_30_DAYS.value,
    )


class AnalyticsTopQuerySerializer(serializers.Serializer):
    range = serializers.ChoiceField(
        choices=[(value, value) for value in AnalyticsRange.values()],
        required=False,
        default=AnalyticsRange.LAST_30_DAYS.value,
    )
    limit = serializers.IntegerField(required=False, min_value=1, max_value=20, default=5)


class SummaryMetricSerializer(serializers.Serializer):
    label = serializers.CharField()
    value = serializers.FloatField()
    change_pct = serializers.FloatField()


class DashboardTotalsSerializer(serializers.Serializer):
    plans_created = serializers.IntegerField()
    plans_completed = serializers.IntegerField()
    group_joins = serializers.IntegerField()
    notifications_sent = serializers.IntegerField()
    notifications_opened = serializers.IntegerField()


class DashboardSummarySerializer(serializers.Serializer):
    range = serializers.CharField(source='range_key')
    current_date = serializers.DateField()
    generated_at = serializers.DateTimeField()
    dau = SummaryMetricSerializer()
    mau = SummaryMetricSerializer()
    plan_creation_rate = SummaryMetricSerializer()
    plan_completion_rate = SummaryMetricSerializer()
    group_join_rate = SummaryMetricSerializer()
    notification_open_rate = SummaryMetricSerializer()
    totals = DashboardTotalsSerializer()


class TimeSeriesPointSerializer(serializers.Serializer):
    date = serializers.DateField()
    value = serializers.FloatField()


class TopEntitySerializer(serializers.Serializer):
    id = serializers.CharField()
    name = serializers.CharField()
    resource_type = serializers.CharField()
    metric_label = serializers.CharField()
    value = serializers.IntegerField()


class TopEntitiesSerializer(serializers.Serializer):
    range = serializers.CharField(source='range_key')
    plans = TopEntitySerializer(many=True)
    groups = TopEntitySerializer(many=True)
