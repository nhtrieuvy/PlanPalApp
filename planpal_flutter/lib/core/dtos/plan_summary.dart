import 'package:equatable/equatable.dart';
import 'user_summary.dart';


class PlanSummary extends Equatable {
  final String id;
  final String title;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isPublic;
  final String status;
  final String planType;
  final UserSummary creator;
  final String? groupName;
  final int durationDays;
  final int activitiesCount;
  final DateTime createdAt;
  final String statusDisplay;
  final String durationDisplay;

  const PlanSummary({
    required this.id,
    required this.title,
    this.startDate,
    this.endDate,
    required this.isPublic,
    required this.status,
    required this.planType,
    required this.creator,
    this.groupName,
    required this.durationDays,
    required this.activitiesCount,
    required this.createdAt,
    required this.statusDisplay,
    required this.durationDisplay,
  });

  factory PlanSummary.fromJson(Map<String, dynamic> json) {
    return PlanSummary(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      startDate: json['start_date'] != null
          ? DateTime.tryParse(json['start_date'].toString())
          : null,
      endDate: json['end_date'] != null
          ? DateTime.tryParse(json['end_date'].toString())
          : null,
      isPublic: json['is_public'] == true,
      status: json['status']?.toString() ?? 'upcoming',
      planType: json['plan_type']?.toString() ?? 'personal',
      creator: UserSummary.fromJson(json['creator'] ?? {}),
      groupName: json['group_name']?.toString(),
      durationDays: json['duration_days']?.toInt() ?? 0,
      activitiesCount: json['activities_count']?.toInt() ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : DateTime.now(),
      statusDisplay: json['status_display']?.toString() ?? '',
      durationDisplay: json['duration_display']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'start_date': startDate?.toIso8601String(),
      'end_date': endDate?.toIso8601String(),
      'is_public': isPublic,
      'status': status,
      'plan_type': planType,
      'creator': creator.toJson(),
      'group_name': groupName,
      'duration_days': durationDays,
      'activities_count': activitiesCount,
      'created_at': createdAt.toIso8601String(),
      'status_display': statusDisplay,
      'duration_display': durationDisplay,
    };
  }

  PlanSummary copyWith({
    String? id,
    String? title,
    DateTime? startDate,
    DateTime? endDate,
    bool? isPublic,
    String? status,
    String? planType,
    UserSummary? creator,
    String? groupName,
    int? durationDays,
    int? activitiesCount,
    DateTime? createdAt,
    String? statusDisplay,
    String? durationDisplay,
  }) {
    return PlanSummary(
      id: id ?? this.id,
      title: title ?? this.title,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isPublic: isPublic ?? this.isPublic,
      status: status ?? this.status,
      planType: planType ?? this.planType,
      creator: creator ?? this.creator,
      groupName: groupName ?? this.groupName,
      durationDays: durationDays ?? this.durationDays,
      activitiesCount: activitiesCount ?? this.activitiesCount,
      createdAt: createdAt ?? this.createdAt,
      statusDisplay: statusDisplay ?? this.statusDisplay,
      durationDisplay: durationDisplay ?? this.durationDisplay,
    );
  }

  /// Helper getters for UI display
  bool get isPersonalPlan => planType == 'personal';
  bool get isGroupPlan => planType == 'group';
  bool get isUpcoming => status == 'upcoming';
  bool get isOngoing => status == 'ongoing';
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';

  String get dateRange {
    if (startDate != null && endDate != null) {
      final start = '${startDate!.day}/${startDate!.month}/${startDate!.year}';
      final end = '${endDate!.day}/${endDate!.month}/${endDate!.year}';
      return '$start - $end';
    } else if (startDate != null) {
      return '${startDate!.day}/${startDate!.month}/${startDate!.year}';
    }
    return 'No date set';
  }

  String get planTypeDisplay => isGroupPlan ? 'Group Plan' : 'Personal Plan';
  String get visibilityDisplay => isPublic ? 'Public' : 'Private';
  String get activitiesCountText =>
      '$activitiesCount ${activitiesCount == 1 ? 'activity' : 'activities'}';

  @override
  List<Object?> get props => [
    id,
    title,
    startDate,
    endDate,
    isPublic,
    status,
    planType,
    creator,
    groupName,
    durationDays,
    activitiesCount,
    createdAt,
    statusDisplay,
    durationDisplay,
  ];

  @override
  String toString() => 'PlanSummary(id: $id, title: $title, status: $status)';
}
