import 'package:equatable/equatable.dart';

/// PlanActivity model matching backend PlanActivitySerializer
/// Represents individual activities within a plan

double? _parseNullableDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

class PlanActivity extends Equatable {
  final String id;
  final String plan;
  final String title;
  final String? description;
  final String activityType;
  final DateTime? startTime;
  final DateTime? endTime;
  final int? durationMinutes; // From API: duration_minutes
  final String? locationName;
  final String? locationAddress;
  final double? latitude;
  final double? longitude;
  final String? goongPlaceId;
  final double? estimatedCost;
  final String? notes;
  final int order;
  final bool isCompleted;
  final double durationHours;
  final bool hasLocation;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String durationDisplay;
  final String activityTypeDisplay;
  final String mapsUrl;

  const PlanActivity({
    required this.id,
    required this.plan,
    required this.title,
    this.description,
    required this.activityType,
    this.startTime,
    this.endTime,
    this.durationMinutes,
    this.locationName,
    this.locationAddress,
    this.latitude,
    this.longitude,
    this.goongPlaceId,
    this.estimatedCost,
    this.notes,
    required this.order,
    required this.isCompleted,
    required this.durationHours,
    required this.hasLocation,
    required this.createdAt,
    required this.updatedAt,
    required this.durationDisplay,
    required this.activityTypeDisplay,
    required this.mapsUrl,
  });

  factory PlanActivity.fromJson(Map<String, dynamic> json) {
    return PlanActivity(
      id: json['id']?.toString() ?? '',
      plan: json['plan']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      activityType: json['activity_type']?.toString() ?? '',
      startTime: json['start_time'] != null
          ? DateTime.tryParse(json['start_time'].toString())
          : null,
      endTime: json['end_time'] != null
          ? DateTime.tryParse(json['end_time'].toString())
          : null,
      durationMinutes: json['duration_minutes']?.toInt(),
      locationName: json['location_name']?.toString(),
      locationAddress: json['location_address']?.toString(),
      latitude: _parseNullableDouble(json['latitude']),
      longitude: _parseNullableDouble(json['longitude']),
      goongPlaceId: json['goong_place_id']?.toString(),
      estimatedCost: _parseNullableDouble(json['estimated_cost']),
      notes: json['notes']?.toString(),
      order: json['order']?.toInt() ?? 0,
      isCompleted: json['is_completed'] == true,
      durationHours:
          _parseNullableDouble(json['duration_hours']) ??
          (json['duration_minutes'] != null
              ? json['duration_minutes'] / 60.0
              : 0.0),
      hasLocation:
          json['has_location'] == true ||
          (json['latitude'] != null && json['longitude'] != null),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'].toString())
          : DateTime.now(),
      durationDisplay:
          json['duration_display']?.toString() ??
          _formatDuration(json['duration_minutes']?.toInt()),
      activityTypeDisplay:
          json['activity_type_display']?.toString() ??
          _getActivityTypeName(json['activity_type']?.toString() ?? ''),
      mapsUrl: json['maps_url']?.toString() ?? '',
    );
  }

  static String _formatDuration(int? minutes) {
    if (minutes == null || minutes == 0) return '';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0 && mins > 0) {
      return '${hours}h ${mins}m';
    } else if (hours > 0) {
      return '${hours}h';
    } else {
      return '${mins}m';
    }
  }

  static String _getActivityTypeName(String activityType) {
    switch (activityType) {
      case 'eating':
        return 'Ăn uống';
      case 'resting':
        return 'Nghỉ ngơi';
      case 'moving':
        return 'Di chuyển';
      case 'sightseeing':
        return 'Tham quan';
      case 'shopping':
        return 'Mua sắm';
      case 'entertainment':
        return 'Giải trí';
      case 'event':
        return 'Sự kiện';
      case 'sport':
        return 'Thể thao';
      case 'study':
        return 'Học tập';
      case 'work':
        return 'Công việc';
      default:
        return 'Khác';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'plan': plan,
      'title': title,
      'description': description,
      'activity_type': activityType,
      'start_time': startTime?.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'duration_minutes': durationMinutes,
      'location_name': locationName,
      'location_address': locationAddress,
      'latitude': latitude,
      'longitude': longitude,
      'goong_place_id': goongPlaceId,
      'estimated_cost': estimatedCost,
      'notes': notes,
      'order': order,
      'is_completed': isCompleted,
      'duration_hours': durationHours,
      'has_location': hasLocation,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'duration_display': durationDisplay,
      'activity_type_display': activityTypeDisplay,
      'maps_url': mapsUrl,
    };
  }

  PlanActivity copyWith({
    String? id,
    String? plan,
    String? title,
    String? description,
    String? activityType,
    DateTime? startTime,
    DateTime? endTime,
    int? durationMinutes,
    String? locationName,
    String? locationAddress,
    double? latitude,
    double? longitude,
    String? goongPlaceId,
    double? estimatedCost,
    String? notes,
    int? order,
    bool? isCompleted,
    double? durationHours,
    bool? hasLocation,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? durationDisplay,
    String? activityTypeDisplay,
    String? mapsUrl,
  }) {
    return PlanActivity(
      id: id ?? this.id,
      plan: plan ?? this.plan,
      title: title ?? this.title,
      description: description ?? this.description,
      activityType: activityType ?? this.activityType,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      locationName: locationName ?? this.locationName,
      locationAddress: locationAddress ?? this.locationAddress,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      goongPlaceId: goongPlaceId ?? this.goongPlaceId,
      estimatedCost: estimatedCost ?? this.estimatedCost,
      notes: notes ?? this.notes,
      order: order ?? this.order,
      isCompleted: isCompleted ?? this.isCompleted,
      durationHours: durationHours ?? this.durationHours,
      hasLocation: hasLocation ?? this.hasLocation,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      durationDisplay: durationDisplay ?? this.durationDisplay,
      activityTypeDisplay: activityTypeDisplay ?? this.activityTypeDisplay,
      mapsUrl: mapsUrl ?? this.mapsUrl,
    );
  }

  /// Helper getters for UI display
  String get timeRange {
    if (startTime != null && endTime != null) {
      return '${_formatTime(startTime!)} - ${_formatTime(endTime!)}';
    } else if (startTime != null) {
      return 'From ${_formatTime(startTime!)}';
    }
    return 'No time set';
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String get costDisplay {
    if (estimatedCost != null && estimatedCost! > 0) {
      return '${estimatedCost!.toStringAsFixed(0)} VND';
    }
    return 'Free';
  }

  @override
  List<Object?> get props => [
    id,
    plan,
    title,
    description,
    activityType,
    startTime,
    endTime,
    durationMinutes,
    locationName,
    locationAddress,
    latitude,
    longitude,
    goongPlaceId,
    estimatedCost,
    notes,
    order,
    isCompleted,
    durationHours,
    hasLocation,
    createdAt,
    updatedAt,
    durationDisplay,
    activityTypeDisplay,
    mapsUrl,
  ];

  @override
  String toString() => 'PlanActivity(id: $id, title: $title, order: $order)';
}
