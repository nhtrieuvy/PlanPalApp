import 'package:planpal_flutter/core/dtos/plan_summary.dart';

class PlansResponse {
  final List<PlanSummary> plans;
  final String? nextCursor;
  final bool hasMore;
  final int count;

  const PlansResponse({
    required this.plans,
    this.nextCursor,
    required this.hasMore,
    required this.count,
  });

  factory PlansResponse.fromJson(Map<String, dynamic> json) {
    return PlansResponse(
      plans: (json['results'] as List<dynamic>? ?? [])
          .map((item) => PlanSummary.fromJson(item as Map<String, dynamic>))
          .toList(),
      nextCursor: json['next'] as String?,
      hasMore: json['has_more'] as bool? ?? false,
      count: json['count'] as int? ?? 0,
    );
  }
}

class GroupsResponse {
  final List<dynamic> groups; // GroupSummary when imported
  final String? nextCursor;
  final bool hasMore;
  final int count;

  const GroupsResponse({
    required this.groups,
    this.nextCursor,
    required this.hasMore,
    required this.count,
  });

  factory GroupsResponse.fromJson(Map<String, dynamic> json) {
    return GroupsResponse(
      groups: json['results'] as List<dynamic>? ?? [],
      nextCursor: json['next'] as String?,
      hasMore: json['has_more'] as bool? ?? false,
      count: json['count'] as int? ?? 0,
    );
  }
}
