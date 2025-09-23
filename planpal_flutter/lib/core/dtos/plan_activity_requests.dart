class CreatePlanActivityRequest {
  final String planId;
  final String title;
  final String description;
  final String activityType;
  final DateTime startTime;
  final DateTime endTime;
  final double? latitude;
  final double? longitude;
  final String? locationName;
  final String? locationAddress;
  final String? goongPlaceId;
  final double? estimatedCost;
  final String? notes;

  CreatePlanActivityRequest({
    required this.planId,
    required this.title,
    required this.description,
    required this.activityType,
    required this.startTime,
    required this.endTime,
    this.latitude,
    this.longitude,
    this.locationName,
    this.locationAddress,
    this.goongPlaceId,
    this.estimatedCost,
    this.notes,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'plan_id': planId,
      'title': title,
      'description': description,
      'activity_type': activityType,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
    };

    if (latitude != null) {
      data['latitude'] = double.parse(latitude!.toStringAsFixed(6));
    }
    if (longitude != null) {
      data['longitude'] = double.parse(longitude!.toStringAsFixed(6));
    }
    if (locationName != null) {
      data['location_name'] = locationName;
    }
    if (locationAddress != null) {
      data['location_address'] = locationAddress;
    }
    if (goongPlaceId != null) {
      data['goong_place_id'] = goongPlaceId;
    }
    if (estimatedCost != null) {
      data['estimated_cost'] = estimatedCost;
    }
    if (notes != null) {
      data['notes'] = notes;
    }

    return data;
  }
}

class UpdatePlanActivityRequest {
  final String? title;
  final String? description;
  final String? activityType;
  final DateTime? startTime;
  final DateTime? endTime;
  final double? latitude;
  final double? longitude;
  final String? notes;

  UpdatePlanActivityRequest({
    this.title,
    this.description,
    this.activityType,
    this.startTime,
    this.endTime,
    this.latitude,
    this.longitude,
    this.notes,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};

    if (title != null) {
      data['title'] = title;
    }
    if (description != null) {
      data['description'] = description;
    }
    if (activityType != null) {
      data['activity_type'] = activityType;
    }
    if (startTime != null) {
      data['start_time'] = startTime!.toIso8601String();
    }
    if (endTime != null) {
      data['end_time'] = endTime!.toIso8601String();
    }
    if (latitude != null) {
      data['latitude'] = double.parse(latitude!.toStringAsFixed(6));
    }
    if (longitude != null) {
      data['longitude'] = double.parse(longitude!.toStringAsFixed(6));
    }
    if (notes != null) {
      data['notes'] = notes;
    }

    return data;
  }
}

class ActivityTypeChoices {
  static const String eating = 'eating';
  static const String resting = 'resting';
  static const String moving = 'moving';
  static const String sightseeing = 'sightseeing';
  static const String shopping = 'shopping';
  static const String entertainment = 'entertainment';
  static const String event = 'event';
  static const String sport = 'sport';
  static const String study = 'study';
  static const String work = 'work';
  static const String other = 'other';

  static const List<String> values = [
    eating,
    resting,
    moving,
    sightseeing,
    shopping,
    entertainment,
    event,
    sport,
    study,
    work,
    other,
  ];

  static const Map<String, String> labels = {
    eating: 'Ăn uống',
    resting: 'Nghỉ ngơi',
    moving: 'Di chuyển',
    sightseeing: 'Tham quan',
    shopping: 'Mua sắm',
    entertainment: 'Giải trí',
    event: 'Sự kiện',
    sport: 'Thể thao',
    study: 'Học tập',
    work: 'Công việc',
    other: 'Khác',
  };
}
