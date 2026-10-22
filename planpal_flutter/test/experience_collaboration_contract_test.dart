import 'package:flutter_test/flutter_test.dart';
import 'package:planpal_flutter/core/dtos/collaboration_models.dart';
import 'package:planpal_flutter/core/dtos/experience_models.dart';

void main() {
  test('poll option parses voter summaries for participant avatars', () {
    final option = GroupPollOptionModel.fromJson({
      'id': 'option-1',
      'text': 'Shinjuku',
      'vote_count': 1,
      'voters': [
        {
          'id': 'user-1',
          'username': 'vy',
          'full_name': 'Nguyen Vy',
          'avatar_url': 'https://example.com/vy.jpg',
        },
      ],
    });

    expect(option.voters, hasLength(1));
    expect(option.voters.single.displayName, 'Nguyen Vy');
  });

  test('availability option parses participant vote details', () {
    final option = AvailabilityOptionModel.fromJson({
      'id': 'option-1',
      'label': 'Friday',
      'start_at': '2026-10-16T08:00:00Z',
      'end_at': '2026-10-16T18:00:00Z',
      'vote_counts': {'available': 1, 'maybe': 0, 'unavailable': 0},
      'current_user_vote': 'available',
      'votes': [
        {
          'status': 'available',
          'user': {
            'id': 'user-1',
            'username': 'vy',
            'full_name': 'Nguyen Vy',
            'avatar_url': '',
          },
        },
      ],
    });

    expect(option.votes, hasLength(1));
    expect(option.votes.single.status, 'available');
    expect(option.votes.single.user.fullName, 'Nguyen Vy');
  });
}
