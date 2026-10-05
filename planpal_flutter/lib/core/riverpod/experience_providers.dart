import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/dtos/experience_models.dart';
import 'package:planpal_flutter/core/repositories/experience_repository.dart';
import 'package:planpal_flutter/core/riverpod/auth_notifier.dart';
import 'package:planpal_flutter/core/riverpod/storage_providers.dart';

final experienceRepositoryProvider = Provider<ExperienceRepository>((ref) {
  return ExperienceRepository(
    ref.read(authNotifierProvider),
    ref.read(offlineSyncProvider),
  );
});

final groupPollsProvider = FutureProvider.autoDispose
    .family<List<GroupPollModel>, String>((ref, groupId) {
      return ref.watch(experienceRepositoryProvider).getPolls(groupId);
    });

final liveLocationsProvider = FutureProvider.autoDispose
    .family<List<LiveLocationModel>, String>((ref, conversationId) {
      return ref
          .watch(experienceRepositoryProvider)
          .getLiveLocations(conversationId);
    });
