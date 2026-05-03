import 'package:flutter_test/flutter_test.dart';
import 'package:planpal_flutter/core/dtos/plan_activity.dart';
import 'package:planpal_flutter/core/dtos/plan_activity_requests.dart';

void main() {
  test('PlanActivity parses version from backend payload', () {
    final activity = PlanActivity.fromJson({
      'id': 'activity-1',
      'plan': 'plan-1',
      'title': 'Visit museum',
      'activity_type': 'sightseeing',
      'start_time': '2026-04-21T09:00:00Z',
      'end_time': '2026-04-21T11:00:00Z',
      'order': 0,
      'is_completed': false,
      'version': 4,
      'duration_hours': 2.0,
      'has_location': false,
      'created_at': '2026-04-21T08:00:00Z',
      'updated_at': '2026-04-21T08:30:00Z',
    });

    expect(activity.version, 4);
  });

  test('UpdatePlanActivityRequest includes optimistic lock fields', () {
    final request = UpdatePlanActivityRequest(
      version: 3,
      force: true,
      title: 'Updated title',
      locationName: 'Da Nang',
      latitude: 16.05441234,
      longitude: 108.20216678,
    );

    final json = request.toJson();

    expect(json['version'], 3);
    expect(json['force'], true);
    expect(json['title'], 'Updated title');
    expect(json['location_name'], 'Da Nang');
    expect(json['latitude'], 16.054412);
    expect(json['longitude'], 108.202167);
  });
}
