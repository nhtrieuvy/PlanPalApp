import 'plan_summary.dart';
// plan_status not needed in this file
import 'user_summary.dart';

class PlanDetail extends PlanSummary {
  final String description;
  final List<ActivityItem> activities;
  final String? groupName;
  final String? durationDisplay;
  final num? totalEstimatedCost;
  final UserSummary? creator; // typed creator summary

  const PlanDetail({
    required super.id,
    required super.title,
    required super.startDate,
    required super.endDate,
    required super.isPublic,
    required super.planType,
    required super.status,
    required super.statusDisplay,
    required super.groupId,
    required super.activitiesCount,
    required this.description,
    required this.activities,
    this.groupName,
    this.durationDisplay,
    this.totalEstimatedCost,
    this.creator,
  });

  factory PlanDetail.fromJson(Map<String, dynamic> pd) {
    final summary = PlanSummary.fromJson(pd);
    final acts = (pd['activities'] is List)
        ? (pd['activities'] as List)
              .whereType<Map>()
              .map((m) => ActivityItem.fromJson(Map<String, dynamic>.from(m)))
              .toList(growable: false)
        : <ActivityItem>[];
    num? parseNum(dynamic v) {
      if (v == null) return null;
      if (v is num) return v;
      return num.tryParse(v.toString());
    }

    return PlanDetail(
      id: summary.id,
      title: summary.title,
      startDate: summary.startDate,
      endDate: summary.endDate,
      isPublic: summary.isPublic,
      planType: summary.planType,
      status: summary.status,
      statusDisplay: summary.statusDisplay,
      groupId: summary.groupId,
      activitiesCount: summary.activitiesCount,
      description: pd['description']?.toString() ?? '',
      activities: acts,
      groupName:
          pd['group_name']?.toString() ?? pd['group']?['name']?.toString(),
      durationDisplay: pd['duration_display']?.toString(),
      totalEstimatedCost: parseNum(pd['total_estimated_cost']),
      creator: pd['creator'] is Map
          ? UserSummary.fromJson(
              Map<String, dynamic>.from(pd['creator'] as Map),
            )
          : null,
    );
  }
}

class ActivityItem {
  final String id;
  final String title;
  final DateTime? startTime;
  final DateTime? endTime;
  final String type;

  const ActivityItem({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.type,
  });

  factory ActivityItem.fromJson(Map<String, dynamic> j) {
    DateTime? parseDT(String k) {
      final v = j[k];
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    return ActivityItem(
      id: j['id']?.toString() ?? '',
      title: j['title']?.toString() ?? j['name']?.toString() ?? '',
      startTime: parseDT('start_time'),
      endTime: parseDT('end_time'),
      type: j['activity_type']?.toString() ?? '',
    );
  }
}
