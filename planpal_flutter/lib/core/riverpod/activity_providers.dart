import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/auth/auth_session.dart';
import 'package:planpal_flutter/core/dtos/plan_activity.dart';
import 'package:planpal_flutter/core/riverpod/auth_notifier.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/repositories/plan_repository.dart';
import 'package:planpal_flutter/core/services/activity_websocket_service.dart';

class ActivityRealtimeHighlight {
  final List<String> updatedFields;
  final String? updatedBy;
  final DateTime updatedAt;
  final int version;

  const ActivityRealtimeHighlight({
    required this.updatedFields,
    required this.updatedBy,
    required this.updatedAt,
    required this.version,
  });
}

class PlanActivitiesState {
  final Map<String, List<PlanActivity>> scheduleByDate;
  final Map<String, dynamic>? statistics;
  final Map<String, dynamic>? permissions;
  final bool isLoading;
  final String? error;
  final ActivitySocketConnectionState connectionState;
  final bool isPollingFallback;
  final Map<String, ActivityRealtimeHighlight> highlights;

  const PlanActivitiesState({
    this.scheduleByDate = const {},
    this.statistics,
    this.permissions,
    this.isLoading = false,
    this.error,
    this.connectionState = ActivitySocketConnectionState.disconnected,
    this.isPollingFallback = false,
    this.highlights = const {},
  });

  List<String> get orderedDates => scheduleByDate.keys.toList()..sort();

  PlanActivitiesState copyWith({
    Map<String, List<PlanActivity>>? scheduleByDate,
    Map<String, dynamic>? statistics,
    bool replaceStatistics = false,
    Map<String, dynamic>? permissions,
    bool replacePermissions = false,
    bool? isLoading,
    String? error,
    bool clearError = false,
    ActivitySocketConnectionState? connectionState,
    bool? isPollingFallback,
    Map<String, ActivityRealtimeHighlight>? highlights,
  }) {
    return PlanActivitiesState(
      scheduleByDate: scheduleByDate ?? this.scheduleByDate,
      statistics: replaceStatistics ? statistics : (statistics ?? this.statistics),
      permissions: replacePermissions ? permissions : (permissions ?? this.permissions),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      connectionState: connectionState ?? this.connectionState,
      isPollingFallback: isPollingFallback ?? this.isPollingFallback,
      highlights: highlights ?? this.highlights,
    );
  }
}

class ActivityRealtimeState {
  final ActivitySocketConnectionState connectionState;
  final bool isPollingFallback;
  final Map<String, ActivityRealtimeHighlight> highlights;

  const ActivityRealtimeState({
    required this.connectionState,
    required this.isPollingFallback,
    required this.highlights,
  });
}

class PlanActivitiesNotifier
    extends AutoDisposeFamilyAsyncNotifier<PlanActivitiesState, String> {
  late final PlanRepository _repo;
  late final AuthProvider _auth;
  ActivityWebSocketService? _socket;
  StreamSubscription<ActivitySocketEvent>? _eventSubscription;
  StreamSubscription<ActivitySocketConnectionState>? _connectionSubscription;
  Timer? _pollingTimer;
  final Map<String, Timer> _highlightTimers = <String, Timer>{};
  String? _planId;

  static const Duration _pollingInterval = Duration(seconds: 15);
  static const Duration _highlightTtl = Duration(seconds: 6);

  @override
  Future<PlanActivitiesState> build(String arg) async {
    _planId = arg;
    _repo = ref.watch(planRepositoryProvider);
    _auth = ref.watch(authNotifierProvider);

    ref.onDispose(() {
      _pollingTimer?.cancel();
      _eventSubscription?.cancel();
      _connectionSubscription?.cancel();
      for (final timer in _highlightTimers.values) {
        timer.cancel();
      }
      _socket?.dispose();
    });

    final initial = await _fetchState();
    _configureRealtime();
    return initial;
  }

  Future<void> refresh() async {
    final current = state.valueOrNull ?? const PlanActivitiesState();
    state = AsyncData(current.copyWith(isLoading: true, clearError: true));
    state = await AsyncValue.guard(_fetchState);
  }

  void _configureRealtime() {
    final token = _auth.token;
    if (token == null || _planId == null) {
      _ensurePollingFallback(true);
      return;
    }

    _socket ??= ActivityWebSocketService(_planId!);
    _eventSubscription ??= _socket!.eventStream.listen(_handleRealtimeEvent);
    _connectionSubscription ??=
        _socket!.connectionStream.listen(_handleConnectionState);
    unawaited(_socket!.connect(token));
  }

  void _handleConnectionState(ActivitySocketConnectionState connectionState) {
    final current = state.valueOrNull;
    if (current == null) return;

    final usePolling =
        connectionState != ActivitySocketConnectionState.connected;
    _ensurePollingFallback(usePolling);

    state = AsyncData(
      current.copyWith(
        connectionState: connectionState,
        isPollingFallback: usePolling,
      ),
    );
  }

  void _ensurePollingFallback(bool enabled) {
    if (!enabled) {
      _pollingTimer?.cancel();
      _pollingTimer = null;
      return;
    }
    if (_pollingTimer != null) return;
    _pollingTimer = Timer.periodic(_pollingInterval, (_) {
      unawaited(_silentRefresh());
    });
  }

  Future<void> _silentRefresh() async {
    try {
      final fresh = await _fetchState();
      final current = state.valueOrNull ?? const PlanActivitiesState();
      state = AsyncData(
        fresh.copyWith(
          connectionState: current.connectionState,
          isPollingFallback: current.isPollingFallback,
          highlights: current.highlights,
        ),
      );
    } catch (_) {
      // Keep the last good state while polling fallback continues.
    }
  }

  Future<PlanActivitiesState> _fetchState() async {
    final data = await _repo.getPlanSchedule(_planId!);
    final rawScheduleByDate =
        data['schedule_by_date'] as Map<String, dynamic>? ?? {};
    final parsedSchedule = <String, List<PlanActivity>>{};

    for (final entry in rawScheduleByDate.entries) {
      final dateKey = entry.key;
      final dateData = entry.value as Map<String, dynamic>? ?? {};
      final activitiesList = dateData['activities'] as List<dynamic>? ?? [];
      parsedSchedule[dateKey] = activitiesList
          .whereType<Map<String, dynamic>>()
          .map((item) => PlanActivity.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    }

    final current = state.valueOrNull;
    return PlanActivitiesState(
      scheduleByDate: parsedSchedule,
      statistics: Map<String, dynamic>.from(
        (data['statistics'] as Map?) ?? const <String, dynamic>{},
      ),
      permissions: Map<String, dynamic>.from(
        (data['permissions'] as Map?) ?? const <String, dynamic>{},
      ),
      connectionState:
          current?.connectionState ?? ActivitySocketConnectionState.disconnected,
      isPollingFallback: current?.isPollingFallback ?? false,
      highlights: current?.highlights ?? const {},
    );
  }

  void _handleRealtimeEvent(ActivitySocketEvent event) {
    switch (event.type) {
      case ActivitySocketEventType.activityCreated:
      case ActivitySocketEventType.activityUpdated:
      case ActivitySocketEventType.activityCompleted:
        final activityJson = event.data['activity'];
        if (activityJson is! Map) {
          unawaited(_silentRefresh());
          return;
        }
        final activity = PlanActivity.fromJson(
          Map<String, dynamic>.from(activityJson),
        );
        _upsertActivity(
          activity,
          updatedFields: ((event.data['updated_fields'] as List?) ?? const [])
              .map((item) => item.toString())
              .toList(),
          updatedBy:
              event.data['updated_by_name']?.toString() ??
              event.data['completed_by_name']?.toString() ??
              event.data['completed_by']?.toString() ??
              event.data['updated_by']?.toString(),
        );
        break;
      case ActivitySocketEventType.activityDeleted:
        final activityId = event.data['activity_id']?.toString();
        if (activityId == null || activityId.isEmpty) {
          unawaited(_silentRefresh());
          return;
        }
        _removeActivity(activityId);
        break;
      case ActivitySocketEventType.planUpdated:
      case ActivitySocketEventType.planStatusChanged:
      case ActivitySocketEventType.unknown:
        break;
    }
  }

  void _upsertActivity(
    PlanActivity activity, {
    required List<String> updatedFields,
    String? updatedBy,
  }) {
    final current = state.valueOrNull;
    if (current == null) return;

    final schedule = <String, List<PlanActivity>>{};
    String? existingDateKey;

    for (final entry in current.scheduleByDate.entries) {
      final remaining = entry.value
          .where((item) => item.id != activity.id)
          .toList(growable: true);
      if (remaining.length != entry.value.length) {
        existingDateKey = entry.key;
      }
      if (remaining.isNotEmpty) {
        schedule[entry.key] = remaining;
      }
    }

    final targetDateKey = _dateKeyFor(activity);
    final targetList = <PlanActivity>[
      ...(schedule[targetDateKey] ?? const <PlanActivity>[]),
      activity,
    ]..sort(_compareActivities);
    schedule[targetDateKey] = targetList;

    final highlights = Map<String, ActivityRealtimeHighlight>.from(
      current.highlights,
    );
    if (updatedFields.isNotEmpty || updatedBy != null) {
      highlights[activity.id] = ActivityRealtimeHighlight(
        updatedFields: updatedFields,
        updatedBy: updatedBy,
        updatedAt: DateTime.now(),
        version: activity.version,
      );
      _highlightTimers[activity.id]?.cancel();
      _highlightTimers[activity.id] = Timer(_highlightTtl, () {
        final currentState = state.valueOrNull;
        if (currentState == null) return;
        final nextHighlights = Map<String, ActivityRealtimeHighlight>.from(
          currentState.highlights,
        )..remove(activity.id);
        state = AsyncData(currentState.copyWith(highlights: nextHighlights));
      });
    }

    state = AsyncData(
      current.copyWith(
        scheduleByDate: schedule,
        statistics: _rebuildStatistics(schedule),
        highlights: highlights,
        clearError: true,
      ),
    );

    if (existingDateKey != null && existingDateKey != targetDateKey) {
      // Stats and tabs already rebuilt above; no-op, but keeps intent explicit.
    }
  }

  void _removeActivity(String activityId) {
    final current = state.valueOrNull;
    if (current == null) return;

    final schedule = <String, List<PlanActivity>>{};
    for (final entry in current.scheduleByDate.entries) {
      final remaining = entry.value
          .where((item) => item.id != activityId)
          .toList(growable: false);
      if (remaining.isNotEmpty) {
        schedule[entry.key] = remaining;
      }
    }

    final highlights = Map<String, ActivityRealtimeHighlight>.from(
      current.highlights,
    )..remove(activityId);
    _highlightTimers.remove(activityId)?.cancel();

    state = AsyncData(
      current.copyWith(
        scheduleByDate: schedule,
        statistics: _rebuildStatistics(schedule),
        highlights: highlights,
      ),
    );
  }

  Map<String, dynamic> _rebuildStatistics(
    Map<String, List<PlanActivity>> schedule,
  ) {
    final activities = schedule.values.expand((items) => items).toList();
    final totalActivities = activities.length;
    final completedActivities = activities.where((item) => item.isCompleted).length;
    final completionRate = totalActivities == 0
        ? 0.0
        : (completedActivities / totalActivities) * 100;

    int totalMinutes = 0;
    for (final activity in activities) {
      if (activity.durationMinutes != null) {
        totalMinutes += activity.durationMinutes!;
      } else if (activity.startTime != null && activity.endTime != null) {
        totalMinutes +=
            activity.endTime!.difference(activity.startTime!).inMinutes;
      }
    }

    return <String, dynamic>{
      'total_activities': totalActivities,
      'completed_activities': completedActivities,
      'completion_rate': completionRate,
      'total_duration_display': _formatDuration(totalMinutes),
    };
  }

  String _dateKeyFor(PlanActivity activity) {
    final start = activity.startTime;
    if (start == null) {
      return 'unscheduled';
    }
    final local = start.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  int _compareActivities(PlanActivity a, PlanActivity b) {
    final startComparison = (a.startTime ?? DateTime.fromMillisecondsSinceEpoch(0))
        .compareTo(b.startTime ?? DateTime.fromMillisecondsSinceEpoch(0));
    if (startComparison != 0) return startComparison;
    return a.createdAt.compareTo(b.createdAt);
  }

  String _formatDuration(int minutes) {
    if (minutes <= 0) return '0m';
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (hours == 0) return '${remainingMinutes}m';
    if (remainingMinutes == 0) return '${hours}h';
    return '${hours}h ${remainingMinutes}m';
  }
}

final activityProvider = AsyncNotifierProvider.autoDispose.family<
  PlanActivitiesNotifier,
  PlanActivitiesState,
  String
>(PlanActivitiesNotifier.new);

final realtimeActivityProvider = Provider.family<ActivityRealtimeState, String>((
  ref,
  planId,
) {
  final state = ref.watch(activityProvider(planId)).valueOrNull;
  return ActivityRealtimeState(
    connectionState:
        state?.connectionState ?? ActivitySocketConnectionState.disconnected,
    isPollingFallback: state?.isPollingFallback ?? false,
    highlights: state?.highlights ?? const {},
  );
});
