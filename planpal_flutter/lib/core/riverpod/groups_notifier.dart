import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../dtos/group_summary.dart';
import '../repositories/group_repository.dart';
import 'repository_providers.dart';

/// Shared state for the groups list — used by both HomePage and GroupPage.
class GroupsNotifier extends AsyncNotifier<List<GroupSummary>> {
  late GroupRepository _repo;

  @override
  Future<List<GroupSummary>> build() async {
    _repo = ref.watch(groupRepositoryProvider);
    return _repo.getGroups();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.getGroups());
  }

  void addGroup(GroupSummary group) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData([group, ...current]);
  }

  void updateGroup(GroupSummary updated) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.map((g) => g.id == updated.id ? updated : g).toList(),
    );
  }

  void removeGroup(String groupId) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.where((g) => g.id != groupId).toList());
  }
}

final groupsNotifierProvider =
    AsyncNotifierProvider<GroupsNotifier, List<GroupSummary>>(
      GroupsNotifier.new,
    );

/// Active groups for the home page (first 5)
final activeGroupsProvider = Provider<List<GroupSummary>>((ref) {
  final groups = ref.watch(groupsNotifierProvider).valueOrNull ?? [];
  return groups.take(5).toList();
});
