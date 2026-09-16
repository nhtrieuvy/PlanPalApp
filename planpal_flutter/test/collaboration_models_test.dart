import 'package:flutter_test/flutter_test.dart';
import 'package:planpal_flutter/core/dtos/collaboration_models.dart';

void main() {
  test('availability poll parses vote summary and current vote', () {
    final poll = AvailabilityPollModel.fromJson({
      'id': 'poll-1',
      'title': 'Weekend',
      'created_by': {'id': 'u1', 'username': 'vy', 'full_name': 'Vy'},
      'is_closed': false,
      'total_voters': 2,
      'options': [
        {
          'id': 'option-1',
          'label': 'Saturday',
          'start_at': '2026-09-12T08:00:00Z',
          'end_at': '2026-09-12T18:00:00Z',
          'vote_counts': {'available': 2, 'maybe': 0, 'unavailable': 0},
          'current_user_vote': 'available',
        },
      ],
    });

    expect(poll.totalVoters, 2);
    expect(poll.options.single.voteCounts['available'], 2);
    expect(poll.options.single.currentUserVote, 'available');
  });

  test('work item and comment tolerate optional nested values', () {
    final item = PlanWorkItemModel.fromJson({
      'id': 'task-1',
      'title': 'Bring passport',
      'item_type': 'checklist',
      'status': 'todo',
    });
    final comment = PlanCommentModel.fromJson({
      'id': 'comment-1',
      'body': 'Ready',
      'author': {'id': 'u1', 'username': 'vy'},
      'reaction_counts': {'like': 1},
      'created_at': '2026-09-10T10:00:00Z',
    });

    expect(item.assignee, isNull);
    expect(comment.author.fullName, 'vy');
    expect(comment.reactionCounts['like'], 1);
  });
}
