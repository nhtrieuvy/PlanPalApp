class PlanSummary {
  final String id;
  final String title;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isPublic;
  final String planType; // personal | group
  final String status;

  final String statusDisplay;
  final String? groupId;
  final int activitiesCount;

  const PlanSummary({
    required this.id,
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.isPublic,
    required this.planType,
    required this.status,
    required this.statusDisplay,
    required this.groupId,
    required this.activitiesCount,
  });

  factory PlanSummary.fromJson(Map<String, dynamic> ps) {
    DateTime? parseDate(String k) {
      final v = ps[k];
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    return PlanSummary(
      id: ps['id']?.toString() ?? '',
      title: ps['title']?.toString() ?? '',
      startDate: parseDate('start_date'),
      endDate: parseDate('end_date'),
      isPublic: ps['is_public'] == true,
      planType:
          ps['plan_type']?.toString() ??
          (ps['group_id'] != null ? 'group' : 'personal'),
      status: ps['status']?.toString() ?? 'unknown',
      statusDisplay: ps['status_display']?.toString() ?? '',
      groupId: ps['group_id']?.toString(),
      activitiesCount: ps['activities_count'] is int
          ? ps['activities_count']
          : int.tryParse('${ps['activities_count']}') ?? 0,
    );
  }
}
