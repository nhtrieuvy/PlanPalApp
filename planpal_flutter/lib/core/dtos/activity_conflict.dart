import 'package:planpal_flutter/core/dtos/plan_activity.dart';

class ActivityConflict {
  final String message;
  final int serverVersion;
  final int? clientVersion;
  final List<String> conflictingFields;
  final Map<String, dynamic> attemptedChanges;
  final PlanActivity serverActivity;

  const ActivityConflict({
    required this.message,
    required this.serverVersion,
    required this.clientVersion,
    required this.conflictingFields,
    required this.attemptedChanges,
    required this.serverActivity,
  });

  factory ActivityConflict.fromJson(Map<String, dynamic> json) {
    final serverState = Map<String, dynamic>.from(
      (json['server_state'] as Map?) ?? const <String, dynamic>{},
    );
    return ActivityConflict(
      message: json['message']?.toString() ?? 'Activity update conflict',
      serverVersion: (json['server_version'] as num?)?.toInt() ?? 1,
      clientVersion: (json['client_version'] as num?)?.toInt(),
      conflictingFields: ((json['conflicting_fields'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList(),
      attemptedChanges: Map<String, dynamic>.from(
        (json['attempted_changes'] as Map?) ?? const <String, dynamic>{},
      ),
      serverActivity: PlanActivity.fromJson(serverState),
    );
  }
}
