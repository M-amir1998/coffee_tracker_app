import 'package:coffee_tracker/core/utils/json.dart';
import 'package:material_ui/material_ui.dart';

class Profile {
  const Profile({required this.id, required this.displayName, this.avatarPath});

  factory Profile.fromJson(Json json) =>
      Profile(id: json.str('id'), displayName: json.str('display_name'), avatarPath: json.strOrNull('avatar_path'));

  final String id;
  final String displayName;
  final String? avatarPath;
}

enum AppLocalePreference {
  system,
  en,
  es;

  static AppLocalePreference parse(String? value) =>
      AppLocalePreference.values.where((v) => v.name == value).firstOrNull ?? AppLocalePreference.system;

  Locale? get locale => this == system ? null : Locale(name);
}

class UserPreferences {
  const UserPreferences({
    this.theme = ThemeMode.system,
    this.locale = AppLocalePreference.system,
    this.showOnLeaderboard = true,
    this.gamificationEnabled = true,
    this.notifySettlements = true,
    this.notifyApprovals = true,
    this.notifyBalance = true,
    this.notifyCycles = true,
    this.notifyAwards = true,
  });

  factory UserPreferences.fromJson(Json json) => UserPreferences(
    theme: ThemeMode.values.where((m) => m.name == json.strOrNull('theme')).firstOrNull ?? ThemeMode.system,
    locale: AppLocalePreference.parse(json.strOrNull('locale')),
    showOnLeaderboard: json.boolOr('show_on_leaderboard', true),
    gamificationEnabled: json.boolOr('gamification_enabled', true),
    notifySettlements: json.boolOr('notify_settlements', true),
    notifyApprovals: json.boolOr('notify_approvals', true),
    notifyBalance: json.boolOr('notify_balance', true),
    notifyCycles: json.boolOr('notify_cycles', true),
    notifyAwards: json.boolOr('notify_awards', true),
  );

  final ThemeMode theme;
  final AppLocalePreference locale;
  final bool showOnLeaderboard;
  final bool gamificationEnabled;
  final bool notifySettlements;
  final bool notifyApprovals;
  final bool notifyBalance;
  final bool notifyCycles;
  final bool notifyAwards;

  UserPreferences copyWith({
    ThemeMode? theme,
    AppLocalePreference? locale,
    bool? showOnLeaderboard,
    bool? gamificationEnabled,
    bool? notifySettlements,
    bool? notifyApprovals,
    bool? notifyBalance,
    bool? notifyCycles,
    bool? notifyAwards,
  }) {
    return UserPreferences(
      theme: theme ?? this.theme,
      locale: locale ?? this.locale,
      showOnLeaderboard: showOnLeaderboard ?? this.showOnLeaderboard,
      gamificationEnabled: gamificationEnabled ?? this.gamificationEnabled,
      notifySettlements: notifySettlements ?? this.notifySettlements,
      notifyApprovals: notifyApprovals ?? this.notifyApprovals,
      notifyBalance: notifyBalance ?? this.notifyBalance,
      notifyCycles: notifyCycles ?? this.notifyCycles,
      notifyAwards: notifyAwards ?? this.notifyAwards,
    );
  }

  Json toJson() => {
    'theme': theme.name,
    'locale': locale.name,
    'show_on_leaderboard': showOnLeaderboard,
    'gamification_enabled': gamificationEnabled,
    'notify_settlements': notifySettlements,
    'notify_approvals': notifyApprovals,
    'notify_balance': notifyBalance,
    'notify_cycles': notifyCycles,
    'notify_awards': notifyAwards,
  };
}
