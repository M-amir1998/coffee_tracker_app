import 'package:coffee_tracker/app/core_providers.dart';
import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/features/auth/application/auth_providers.dart';
import 'package:coffee_tracker/features/groups/domain/group_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Incremented whenever group data changes (realtime event, successful write,
/// manual refresh). Data providers watch it to refetch.
final dataRevisionProvider = NotifierProvider<DataRevision, int>(DataRevision.new);

class DataRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final myGroupsProvider = FutureProvider<List<GroupSummary>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const [];
  ref.watch(dataRevisionProvider);
  return ref.watch(groupRepositoryProvider).myGroups();
});

const _activeGroupKey = 'active_group_id';

/// The group the user chose last (persisted on this device).
final selectedGroupIdProvider = NotifierProvider<SelectedGroupId, String?>(SelectedGroupId.new);

class SelectedGroupId extends Notifier<String?> {
  @override
  String? build() => ref.watch(sharedPreferencesProvider).getString(_activeGroupKey);

  Future<void> select(String groupId) async {
    state = groupId;
    await ref.read(sharedPreferencesProvider).setString(_activeGroupKey, groupId);
  }
}

/// The group shown in the app: the stored selection when the user still
/// belongs to it, otherwise their first group. Null when they have none.
final currentGroupProvider = Provider<AsyncValue<GroupSummary?>>((ref) {
  final groups = ref.watch(myGroupsProvider);
  final selected = ref.watch(selectedGroupIdProvider);
  return groups.whenData((list) => list.where((g) => g.id == selected).firstOrNull ?? list.firstOrNull);
});

/// Convenience accessor for screens that only render inside a group.
final currentGroupIdProvider = Provider<String?>((ref) => ref.watch(currentGroupProvider).value?.id);

final membersProvider = FutureProvider.autoDispose.family<List<Member>, String>((ref, groupId) {
  ref.watch(dataRevisionProvider);
  return ref.watch(groupRepositoryProvider).members(groupId, includeInactive: true);
});

final invitationsProvider = FutureProvider.autoDispose.family<List<Invitation>, String>((ref, groupId) {
  ref.watch(dataRevisionProvider);
  return ref.watch(groupRepositoryProvider).invitations(groupId);
});

final pricesProvider = FutureProvider.autoDispose.family<List<CoffeePrice>, String>((ref, groupId) {
  ref.watch(dataRevisionProvider);
  return ref.watch(groupRepositoryProvider).prices(groupId);
});

final timezonesProvider = FutureProvider<List<String>>((ref) => ref.watch(groupRepositoryProvider).timezones());
