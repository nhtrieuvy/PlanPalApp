import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/dtos/collaboration_models.dart';
import 'package:planpal_flutter/core/repositories/collaboration_repository.dart';
import 'package:planpal_flutter/core/services/activity_websocket_service.dart';
import 'auth_notifier.dart';

final collaborationRepositoryProvider = Provider<CollaborationRepository>((
  ref,
) {
  return CollaborationRepository(ref.read(authNotifierProvider));
});

final availabilityPollsProvider = FutureProvider.autoDispose
    .family<List<AvailabilityPollModel>, String>((ref, groupId) {
      return ref.watch(collaborationRepositoryProvider).getPolls(groupId);
    });

final planWorkItemsProvider = FutureProvider.autoDispose
    .family<List<PlanWorkItemModel>, String>((ref, planId) {
      return ref.watch(collaborationRepositoryProvider).getWorkItems(planId);
    });

final planCommentsProvider = FutureProvider.autoDispose
    .family<List<PlanCommentModel>, String>((ref, planId) {
      return ref.watch(collaborationRepositoryProvider).getComments(planId);
    });

final planCollaborationEventsProvider = StreamProvider.autoDispose
    .family<ActivitySocketEvent, String>((ref, planId) {
      final service = ActivityWebSocketService(planId);
      final token = ref.read(authNotifierProvider).token;
      ref.onDispose(service.dispose);
      if (token != null && token.isNotEmpty) {
        unawaited(service.connect(token));
      }
      return service.eventStream.where(
        (event) => event.rawEventType.startsWith('collaboration.'),
      );
    });
