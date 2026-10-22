import 'package:coffee_tracker/core/data/rpc.dart';
import 'package:coffee_tracker/core/errors/app_failure.dart';
import 'package:coffee_tracker/core/utils/json.dart';
import 'package:coffee_tracker/features/profile/domain/profile_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  Future<Profile?> myProfile(String userId) {
    return guard(() async {
      final row = await _client.from('profiles').select('id, display_name, avatar_path').eq('id', userId).maybeSingle();
      return row == null ? null : Profile.fromJson(row);
    });
  }

  Future<UserPreferences> myPreferences(String userId) {
    return guard(() async {
      final row = await _client.from('user_preferences').select().eq('user_id', userId).maybeSingle();
      return row == null ? const UserPreferences() : UserPreferences.fromJson(row);
    });
  }

  Future<void> updateDisplayName(String displayName) =>
      _client.call('update_profile', {'p_display_name': displayName});

  Future<UserPreferences> updatePreferences(UserPreferences preferences) async {
    final Json json = await _client.callJson('update_preferences', {
      'p_theme': preferences.theme.name,
      'p_locale': preferences.locale.name,
      'p_show_on_leaderboard': preferences.showOnLeaderboard,
      'p_gamification_enabled': preferences.gamificationEnabled,
      'p_notify_settlements': preferences.notifySettlements,
      'p_notify_approvals': preferences.notifyApprovals,
      'p_notify_balance': preferences.notifyBalance,
      'p_notify_cycles': preferences.notifyCycles,
      'p_notify_awards': preferences.notifyAwards,
    });
    return UserPreferences.fromJson(json);
  }

  /// Fails with `outstanding_balance`, `open_items` or `last_admin` when the
  /// account cannot be deleted yet.
  Future<void> deleteAccount() => _client.call('delete_my_account');
}
