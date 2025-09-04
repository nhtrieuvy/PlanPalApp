class CreatePlanRequest {
  final String title;
  final String description;
  final String startDate;
  final String endDate;
  final bool isPublic;
  final String planType;

  CreatePlanRequest({
    required this.title,
    required this.description,
    required this.startDate,
    required this.endDate,
    required this.isPublic,
    required this.planType,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'start_date': startDate,
    'end_date': endDate,
    'is_public': isPublic,
    'plan_type': planType,
  };
}

class CreateActivityRequest {
  final String planId;
  final String title;
  final String description;
  final String? locationName;
  final String? locationAddress;
  final String startTime;
  final String endTime;
  final String activityType;
  final double? estimatedCost;
  final String? notes;

  CreateActivityRequest({
    required this.planId,
    required this.title,
    required this.description,
    this.locationName,
    this.locationAddress,
    required this.startTime,
    required this.endTime,
    required this.activityType,
    this.estimatedCost,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
    'plan': planId,
    'title': title,
    'description': description,
    'location_name': locationName,
    'location_address': locationAddress,
    'start_time': startTime,
    'end_time': endTime,
    'activity_type': activityType,
    'estimated_cost': estimatedCost,
    'notes': notes,
  };
}

class UpdateActivityRequest {
  final String title;
  final String description;
  final String? locationName;
  final String? locationAddress;
  final String startTime;
  final String endTime;
  final String activityType;
  final double? estimatedCost;
  final String? notes;

  UpdateActivityRequest({
    required this.title,
    required this.description,
    this.locationName,
    this.locationAddress,
    required this.startTime,
    required this.endTime,
    required this.activityType,
    this.estimatedCost,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'location_name': locationName,
    'location_address': locationAddress,
    'start_time': startTime,
    'end_time': endTime,
    'activity_type': activityType,
    'estimated_cost': estimatedCost,
    'notes': notes,
  };
}

class UpdatePlanRequest {
  final String? title;
  final String? description;
  final String? startDate;
  final String? endDate;
  final bool? isPublic;
  final String? planType;

  UpdatePlanRequest({
    this.title,
    this.description,
    this.startDate,
    this.endDate,
    this.isPublic,
    this.planType,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    if (title != null) data['title'] = title;
    if (description != null) data['description'] = description;
    if (startDate != null) data['start_date'] = startDate;
    if (endDate != null) data['end_date'] = endDate;
    if (isPublic != null) data['is_public'] = isPublic;
    if (planType != null) data['plan_type'] = planType;
    return data;
  }
}
