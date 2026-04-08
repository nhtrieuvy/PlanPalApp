import 'package:equatable/equatable.dart';
import 'package:planpal_flutter/core/utils/server_datetime.dart';

enum AnalyticsRangeOption {
  last7Days,
  last30Days,
  last90Days,
  last180Days,
}

extension AnalyticsRangeOptionX on AnalyticsRangeOption {
  String get apiValue {
    switch (this) {
      case AnalyticsRangeOption.last7Days:
        return '7d';
      case AnalyticsRangeOption.last30Days:
        return '30d';
      case AnalyticsRangeOption.last90Days:
        return '90d';
      case AnalyticsRangeOption.last180Days:
        return '180d';
    }
  }

  String get label {
    switch (this) {
      case AnalyticsRangeOption.last7Days:
        return '7 days';
      case AnalyticsRangeOption.last30Days:
        return '30 days';
      case AnalyticsRangeOption.last90Days:
        return '90 days';
      case AnalyticsRangeOption.last180Days:
        return '180 days';
    }
  }
}

enum AnalyticsMetricKey {
  dau,
  mau,
  planCreationRate,
  planCompletionRate,
  groupJoinRate,
  notificationOpenRate,
}

extension AnalyticsMetricKeyX on AnalyticsMetricKey {
  String get apiValue {
    switch (this) {
      case AnalyticsMetricKey.dau:
        return 'dau';
      case AnalyticsMetricKey.mau:
        return 'mau';
      case AnalyticsMetricKey.planCreationRate:
        return 'plan_creation_rate';
      case AnalyticsMetricKey.planCompletionRate:
        return 'plan_completion_rate';
      case AnalyticsMetricKey.groupJoinRate:
        return 'group_join_rate';
      case AnalyticsMetricKey.notificationOpenRate:
        return 'notification_open_rate';
    }
  }

  String get label {
    switch (this) {
      case AnalyticsMetricKey.dau:
        return 'Daily Active Users';
      case AnalyticsMetricKey.mau:
        return 'Monthly Active Users';
      case AnalyticsMetricKey.planCreationRate:
        return 'Plan Creation Rate';
      case AnalyticsMetricKey.planCompletionRate:
        return 'Plan Completion Rate';
      case AnalyticsMetricKey.groupJoinRate:
        return 'Group Join Rate';
      case AnalyticsMetricKey.notificationOpenRate:
        return 'Notification Open Rate';
    }
  }

  bool get isPercentage {
    return this == AnalyticsMetricKey.planCreationRate ||
        this == AnalyticsMetricKey.planCompletionRate ||
        this == AnalyticsMetricKey.groupJoinRate ||
        this == AnalyticsMetricKey.notificationOpenRate;
  }
}

class AnalyticsKpi extends Equatable {
  final String label;
  final double value;
  final double changePct;

  const AnalyticsKpi({
    required this.label,
    required this.value,
    required this.changePct,
  });

  factory AnalyticsKpi.fromJson(Map<String, dynamic> json) {
    return AnalyticsKpi(
      label: json['label']?.toString() ?? '',
      value: _asDouble(json['value']),
      changePct: _asDouble(json['change_pct']),
    );
  }

  String formatValue({bool percentage = false}) {
    if (percentage) {
      return '${value.toStringAsFixed(1)}%';
    }
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(1);
  }

  String get changeLabel {
    final prefix = changePct > 0 ? '+' : '';
    return '$prefix${changePct.toStringAsFixed(1)}%';
  }

  bool get isPositiveChange => changePct >= 0;

  @override
  List<Object?> get props => [label, value, changePct];
}

class AnalyticsTotals extends Equatable {
  final int plansCreated;
  final int plansCompleted;
  final int groupJoins;
  final int notificationsSent;
  final int notificationsOpened;

  const AnalyticsTotals({
    required this.plansCreated,
    required this.plansCompleted,
    required this.groupJoins,
    required this.notificationsSent,
    required this.notificationsOpened,
  });

  factory AnalyticsTotals.fromJson(Map<String, dynamic> json) {
    return AnalyticsTotals(
      plansCreated: _asInt(json['plans_created']),
      plansCompleted: _asInt(json['plans_completed']),
      groupJoins: _asInt(json['group_joins']),
      notificationsSent: _asInt(json['notifications_sent']),
      notificationsOpened: _asInt(json['notifications_opened']),
    );
  }

  @override
  List<Object?> get props => [
    plansCreated,
    plansCompleted,
    groupJoins,
    notificationsSent,
    notificationsOpened,
  ];
}

class AnalyticsSummary extends Equatable {
  final String range;
  final DateTime currentDate;
  final DateTime generatedAt;
  final AnalyticsKpi dau;
  final AnalyticsKpi mau;
  final AnalyticsKpi planCreationRate;
  final AnalyticsKpi planCompletionRate;
  final AnalyticsKpi groupJoinRate;
  final AnalyticsKpi notificationOpenRate;
  final AnalyticsTotals totals;

  const AnalyticsSummary({
    required this.range,
    required this.currentDate,
    required this.generatedAt,
    required this.dau,
    required this.mau,
    required this.planCreationRate,
    required this.planCompletionRate,
    required this.groupJoinRate,
    required this.notificationOpenRate,
    required this.totals,
  });

  factory AnalyticsSummary.fromJson(Map<String, dynamic> json) {
    return AnalyticsSummary(
      range: json['range']?.toString() ?? '30d',
      currentDate: parseServerDateTime(json['current_date']) ?? DateTime.now(),
      generatedAt: parseServerDateTime(json['generated_at']) ?? DateTime.now(),
      dau: AnalyticsKpi.fromJson(Map<String, dynamic>.from(json['dau'] as Map)),
      mau: AnalyticsKpi.fromJson(Map<String, dynamic>.from(json['mau'] as Map)),
      planCreationRate: AnalyticsKpi.fromJson(
        Map<String, dynamic>.from(json['plan_creation_rate'] as Map),
      ),
      planCompletionRate: AnalyticsKpi.fromJson(
        Map<String, dynamic>.from(json['plan_completion_rate'] as Map),
      ),
      groupJoinRate: AnalyticsKpi.fromJson(
        Map<String, dynamic>.from(json['group_join_rate'] as Map),
      ),
      notificationOpenRate: AnalyticsKpi.fromJson(
        Map<String, dynamic>.from(json['notification_open_rate'] as Map),
      ),
      totals: AnalyticsTotals.fromJson(
        Map<String, dynamic>.from(json['totals'] as Map),
      ),
    );
  }

  @override
  List<Object?> get props => [
    range,
    currentDate,
    generatedAt,
    dau,
    mau,
    planCreationRate,
    planCompletionRate,
    groupJoinRate,
    notificationOpenRate,
    totals,
  ];
}

class TimeSeriesPoint extends Equatable {
  final DateTime date;
  final double value;

  const TimeSeriesPoint({required this.date, required this.value});

  factory TimeSeriesPoint.fromJson(Map<String, dynamic> json) {
    return TimeSeriesPoint(
      date: parseServerDateTime(json['date']) ?? DateTime.now(),
      value: _asDouble(json['value']),
    );
  }

  @override
  List<Object?> get props => [date, value];
}

class AnalyticsTimeSeries extends Equatable {
  final String metric;
  final String range;
  final List<TimeSeriesPoint> points;

  const AnalyticsTimeSeries({
    required this.metric,
    required this.range,
    required this.points,
  });

  factory AnalyticsTimeSeries.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['points'] as List<dynamic>? ?? const <dynamic>[];
    return AnalyticsTimeSeries(
      metric: json['metric']?.toString() ?? '',
      range: json['range']?.toString() ?? '30d',
      points: rawPoints
          .whereType<Map>()
          .map((item) => TimeSeriesPoint.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }

  @override
  List<Object?> get props => [metric, range, points];
}

class TopAnalyticsEntity extends Equatable {
  final String id;
  final String name;
  final String resourceType;
  final String metricLabel;
  final int value;

  const TopAnalyticsEntity({
    required this.id,
    required this.name,
    required this.resourceType,
    required this.metricLabel,
    required this.value,
  });

  factory TopAnalyticsEntity.fromJson(Map<String, dynamic> json) {
    return TopAnalyticsEntity(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      resourceType: json['resource_type']?.toString() ?? '',
      metricLabel: json['metric_label']?.toString() ?? '',
      value: _asInt(json['value']),
    );
  }

  @override
  List<Object?> get props => [id, name, resourceType, metricLabel, value];
}

class AnalyticsTopEntities extends Equatable {
  final String range;
  final List<TopAnalyticsEntity> plans;
  final List<TopAnalyticsEntity> groups;

  const AnalyticsTopEntities({
    required this.range,
    required this.plans,
    required this.groups,
  });

  factory AnalyticsTopEntities.fromJson(Map<String, dynamic> json) {
    final rawPlans = json['plans'] as List<dynamic>? ?? const <dynamic>[];
    final rawGroups = json['groups'] as List<dynamic>? ?? const <dynamic>[];
    return AnalyticsTopEntities(
      range: json['range']?.toString() ?? '30d',
      plans: rawPlans
          .whereType<Map>()
          .map(
            (item) => TopAnalyticsEntity.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      groups: rawGroups
          .whereType<Map>()
          .map(
            (item) => TopAnalyticsEntity.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }

  @override
  List<Object?> get props => [range, plans, groups];
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
