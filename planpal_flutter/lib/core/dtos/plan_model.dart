import 'package:equatable/equatable.dart';
import 'user_summary.dart';
import 'group_summary.dart';
import 'plan_activity.dart';

double _parseDoubleSafe(dynamic v, {double defaultValue = 0.0}) {
  if (v == null) return defaultValue;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? defaultValue;
}

/// PlanModel model matching backend PlanSerializer
/// Full plan details with activities and permissions
class PlanModel extends Equatable {
  final String id;
  final String title;
  final String? description;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isPublic;
  final String status;
  final String planType;
  final UserSummary creator;
  final GroupSummary? group;
  final String? groupName;
  final List<PlanActivity> activities;
  final int durationDays;
  final int activitiesCount;
  final double totalEstimatedCost;
  final bool canView;
  final bool canEdit;
  final List<UserSummary> collaborators;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String durationDisplay;
  final String statusDisplay;

  const PlanModel({
    required this.id,
    required this.title,
    this.description,
    this.startDate,
    this.endDate,
    required this.isPublic,
    required this.status,
    required this.planType,
    required this.creator,
    this.group,
    this.groupName,
    required this.activities,
    required this.durationDays,
    required this.activitiesCount,
    required this.totalEstimatedCost,
    required this.canView,
    required this.canEdit,
    required this.collaborators,
    required this.createdAt,
    required this.updatedAt,
    required this.durationDisplay,
    required this.statusDisplay,
  });

  factory PlanModel.fromJson(Map<String, dynamic> json) {
    final activitiesList = json['activities'] as List<dynamic>? ?? [];
    final activities = activitiesList
        .map((activityJson) => PlanActivity.fromJson(activityJson))
        .toList();

    final collaboratorsList = json['collaborators'] as List<dynamic>? ?? [];
    final collaborators = collaboratorsList
        .map((collaboratorJson) => UserSummary.fromJson(collaboratorJson))
        .toList();

    return PlanModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
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
      group: json['group'] != null
          ? GroupSummary.fromJson(json['group'])
          : null,
      groupName: json['group_name']?.toString(),
      activities: activities,
      durationDays: json['duration_days']?.toInt() ?? 0,
      activitiesCount: json['activities_count']?.toInt() ?? 0,
      totalEstimatedCost: _parseDoubleSafe(json['total_estimated_cost']),
      canView: json['can_view'] == true,
      canEdit: json['can_edit'] == true,
      collaborators: collaborators,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'].toString())
          : DateTime.now(),
      durationDisplay: json['duration_display']?.toString() ?? '',
      statusDisplay: json['status_display']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'start_date': startDate?.toIso8601String(),
      'end_date': endDate?.toIso8601String(),
      'is_public': isPublic,
      'status': status,
      'plan_type': planType,
      'creator': creator.toJson(),
      'group': group?.toJson(),
      'group_name': groupName,
      'activities': activities.map((a) => a.toJson()).toList(),
      'duration_days': durationDays,
      'activities_count': activitiesCount,
      'total_estimated_cost': totalEstimatedCost,
      'can_view': canView,
      'can_edit': canEdit,
      'collaborators': collaborators.map((c) => c.toJson()).toList(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'duration_display': durationDisplay,
      'status_display': statusDisplay,
    };
  }

  PlanModel copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? startDate,
    DateTime? endDate,
    bool? isPublic,
    String? status,
    String? planType,
    UserSummary? creator,
    GroupSummary? group,
    String? groupName,
    List<PlanActivity>? activities,
    int? durationDays,
    int? activitiesCount,
    double? totalEstimatedCost,
    bool? canView,
    bool? canEdit,
    List<UserSummary>? collaborators,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? durationDisplay,
    String? statusDisplay,
  }) {
    return PlanModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isPublic: isPublic ?? this.isPublic,
      status: status ?? this.status,
      planType: planType ?? this.planType,
      creator: creator ?? this.creator,
      group: group ?? this.group,
      groupName: groupName ?? this.groupName,
      activities: activities ?? this.activities,
      durationDays: durationDays ?? this.durationDays,
      activitiesCount: activitiesCount ?? this.activitiesCount,
      totalEstimatedCost: totalEstimatedCost ?? this.totalEstimatedCost,
      canView: canView ?? this.canView,
      canEdit: canEdit ?? this.canEdit,
      collaborators: collaborators ?? this.collaborators,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      durationDisplay: durationDisplay ?? this.durationDisplay,
      statusDisplay: statusDisplay ?? this.statusDisplay,
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

  String get costDisplay {
    if (totalEstimatedCost > 0) {
      return '${totalEstimatedCost.toStringAsFixed(0)} VND';
    }
    return 'Free';
  }

  String get planTypeDisplay => isGroupPlan ? 'Group Plan' : 'Personal Plan';
  String get visibilityDisplay => isPublic ? 'Public' : 'Private';

  @override
  List<Object?> get props => [
    id,
    title,
    description,
    startDate,
    endDate,
    isPublic,
    status,
    planType,
    creator,
    group,
    groupName,
    activities,
    durationDays,
    activitiesCount,
    totalEstimatedCost,
    canView,
    canEdit,
    collaborators,
    createdAt,
    updatedAt,
    durationDisplay,
    statusDisplay,
  ];

  @override
  String toString() => 'PlanModel(id: $id, title: $title, status: $status)';
}
