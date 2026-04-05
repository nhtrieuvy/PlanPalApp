import 'package:planpal_flutter/core/dtos/plan_summary.dart';

class PlansResponse {
  final List<PlanSummary> plans;
  final String? nextPageUrl;
  final String? previousPageUrl;
  final bool hasMore;
  final int count;

  const PlansResponse({
    required this.plans,
    this.nextPageUrl,
    this.previousPageUrl,
    required this.hasMore,
    required this.count,
  });

  factory PlansResponse.fromJson(Map<String, dynamic> json) {
    final next = json['next'] as String?;
    return PlansResponse(
      plans: (json['results'] as List<dynamic>? ?? [])
          .map((item) => PlanSummary.fromJson(item as Map<String, dynamic>))
          .toList(),
      nextPageUrl: next,
      previousPageUrl: json['previous'] as String?,
      hasMore: next != null,
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
    final next = json['next'] as String?;
    return GroupsResponse(
      groups: json['results'] as List<dynamic>? ?? [],
      nextCursor: next,
      hasMore: json['has_more'] as bool? ?? (next != null),
      count: json['count'] as int? ?? 0,
    );
  }
}
