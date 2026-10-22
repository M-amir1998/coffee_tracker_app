import 'dart:async';
import 'dart:convert';

import 'package:coffee_tracker/app/core_providers.dart';
import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/core/utils/json.dart';
import 'package:coffee_tracker/features/auth/application/auth_providers.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/profile/domain/profile_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final myProfileProvider = FutureProvider<Profile?>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  ref.watch(dataRevisionProvider);
  return ref.watch(profileRepositoryProvider).myProfile(userId);
});

const _preferencesKey = 'preferences_v1';

/// Preferences are cached on the device so the theme and language apply
/// instantly at start-up, and synchronised with the account when signed in.
final preferencesProvider = NotifierProvider<PreferencesController, UserPreferences>(PreferencesController.new);

class PreferencesController extends Notifier<UserPreferences> {
  @override
  UserPreferences build() {
    ref.listen(currentUserIdProvider, (previous, next) {
      if (next != null && next != previous) unawaited(_loadRemote(next));
    }, fireImmediately: true);
    return _loadLocal();
  }

  UserPreferences _loadLocal() {
    final raw = ref.read(sharedPreferencesProvider).getString(_preferencesKey);
    if (raw == null) return const UserPreferences();
    try {
      return UserPreferences.fromJson(asJson(jsonDecode(raw)));
    } on FormatException {
      return const UserPreferences();
    }
  }

  Future<void> _saveLocal(UserPreferences preferences) =>
      ref.read(sharedPreferencesProvider).setString(_preferencesKey, jsonEncode(preferences.toJson()));

  Future<void> _loadRemote(String userId) async {
    try {
      final remote = await ref.read(profileRepositoryProvider).myPreferences(userId);
      if (!ref.mounted) return;
      state = remote;
      await _saveLocal(remote);
    } on Object {
      // Offline: keep the cached preferences.
    }
  }

  /// Applies [next] immediately and stores it for the account.
  Future<void> update(UserPreferences next) async {
    final previous = state;
    state = next;
    await _saveLocal(next);
    if (ref.read(currentUserIdProvider) == null) return;
    try {
      final saved = await ref.read(profileRepositoryProvider).updatePreferences(next);
      if (ref.mounted) state = saved;
    } on Object {
      if (ref.mounted) {
        state = previous;
        await _saveLocal(previous);
      }
      rethrow;
    }
  }
}
