import 'plan_status.dart';

class PlanSummary {
  final String id;
  final String title;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isPublic;
  final String planType; // personal | group
  final PlanStatus status;
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
    required this.groupId,
    required this.activitiesCount,
  });

  factory PlanSummary.fromJson(Map<String, dynamic> j) {
    DateTime? parseDate(String k) {
      final v = j[k];
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }
    return PlanSummary(
      id: j['id']?.toString() ?? '',
      title: j['title']?.toString() ?? '',
      startDate: parseDate('start_date'),
      endDate: parseDate('end_date'),
      isPublic: j['is_public'] == true,
      planType: j['plan_type']?.toString() ?? (j['group_id'] != null ? 'group' : 'personal'),
      status: parsePlanStatus(j['status']?.toString()),
      groupId: j['group_id']?.toString(),
      activitiesCount: j['activities_count'] is int
          ? j['activities_count']
          : int.tryParse('${j['activities_count']}') ?? 0,
    );
  }
}
