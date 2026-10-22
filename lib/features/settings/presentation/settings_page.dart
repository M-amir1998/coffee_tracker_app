import 'dart:async';

import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/app/routes.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/app_card.dart';
import 'package:coffee_tracker/core/widgets/feedback.dart';
import 'package:coffee_tracker/core/widgets/member_avatar.dart';
import 'package:coffee_tracker/core/widgets/page_layout.dart';
import 'package:coffee_tracker/features/auth/presentation/auth_layout.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/groups/presentation/group_switcher.dart';
import 'package:coffee_tracker/features/profile/application/profile_providers.dart';
import 'package:coffee_tracker/features/profile/domain/profile_models.dart';
import 'package:coffee_tracker/features/shell/presentation/shortcuts_help.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

const appVersion = '1.0.0';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  Future<void> _update(BuildContext context, WidgetRef ref, UserPreferences next) async {
    try {
      await ref.read(preferencesProvider.notifier).update(next);
      ref.read(dataRevisionProvider.notifier).bump();
    } on Object catch (error) {
      if (context.mounted) showErrorToast(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final prefs = ref.watch(preferencesProvider);
    void set(UserPreferences next) => unawaited(_update(context, ref, next));

    return AppPage(
      title: l10n.navSettings,
      maxWidth: 1000,
      body: ResponsiveColumns(
        minColumnWidth: 420,
        maxColumns: 2,
        children: [
          const _ProfileCard(),
          SectionCard(
            title: l10n.settingsAppearance,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.settingsTheme, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: Spacing.xs),
                SegmentedButton<ThemeMode>(
                  segments: [
                    ButtonSegment(value: ThemeMode.system, label: Text(l10n.themeSystem), icon: const Icon(Icons.brightness_auto_rounded)),
                    ButtonSegment(value: ThemeMode.light, label: Text(l10n.themeLight), icon: const Icon(Icons.light_mode_rounded)),
                    ButtonSegment(value: ThemeMode.dark, label: Text(l10n.themeDark), icon: const Icon(Icons.dark_mode_rounded)),
                  ],
                  selected: {prefs.theme},
                  onSelectionChanged: (value) => set(prefs.copyWith(theme: value.first)),
                ),
                const SizedBox(height: Spacing.md),
                Text(l10n.settingsLanguage, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: Spacing.xs),
                SegmentedButton<AppLocalePreference>(
                  segments: [
                    ButtonSegment(value: AppLocalePreference.system, label: Text(l10n.languageSystem)),
                    const ButtonSegment(value: AppLocalePreference.en, label: Text('English')),
                    const ButtonSegment(value: AppLocalePreference.es, label: Text('Español')),
                  ],
                  selected: {prefs.locale},
                  onSelectionChanged: (value) => set(prefs.copyWith(locale: value.first)),
                ),
              ],
            ),
          ),
          SectionCard(
            title: l10n.navHeroes,
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.settingsGamification),
                  subtitle: Text(l10n.settingsGamificationHint),
                  value: prefs.gamificationEnabled,
                  onChanged: (value) => set(prefs.copyWith(gamificationEnabled: value)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.showMeOnHeroes),
                  subtitle: Text(l10n.showMeOnHeroesHint),
                  value: prefs.showOnLeaderboard,
                  onChanged: (value) => set(prefs.copyWith(showOnLeaderboard: value)),
                ),
              ],
            ),
          ),
          SectionCard(
            title: l10n.settingsNotifications,
            child: Column(
              children: [
                for (final (title, subtitle, value, apply) in [
                  (l10n.notifySettlements, l10n.notifySettlementsHint, prefs.notifySettlements,
                      (bool v) => prefs.copyWith(notifySettlements: v)),
                  (l10n.notifyApprovals, l10n.notifyApprovalsHint, prefs.notifyApprovals,
                      (bool v) => prefs.copyWith(notifyApprovals: v)),
                  (l10n.notifyBalance, l10n.notifyBalanceHint, prefs.notifyBalance,
                      (bool v) => prefs.copyWith(notifyBalance: v)),
                  (l10n.notifyCycles, l10n.notifyCyclesHint, prefs.notifyCycles,
                      (bool v) => prefs.copyWith(notifyCycles: v)),
                  (l10n.notifyAwards, l10n.notifyAwardsHint, prefs.notifyAwards,
                      (bool v) => prefs.copyWith(notifyAwards: v)),
                ])
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(title),
                    subtitle: Text(subtitle),
                    value: value,
                    onChanged: (v) => set(apply(v)),
                  ),
                Text(l10n.notificationsActionNote, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const _GroupsCard(),
          const _AccountCard(),
        ],
      ),
    );
  }
}

class _ProfileCard extends ConsumerWidget {
  const _ProfileCard();

  Future<void> _editName(BuildContext context, WidgetRef ref, String current) async {
    final l10n = context.l10n;
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.editDisplayName),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: InputDecoration(labelText: l10n.fieldDisplayName, helperText: l10n.displayNameHelper),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.actionCancel)),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: Text(l10n.actionSave)),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || name == current) return;
    try {
      await ref.read(profileRepositoryProvider).updateDisplayName(name);
      ref.read(dataRevisionProvider.notifier).bump();
      ref.invalidate(myProfileProvider);
    } on Object catch (error) {
      if (context.mounted) showErrorToast(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final profile = ref.watch(myProfileProvider).value;
    final email = ref.watch(authRepositoryProvider).currentUser?.email;
    return SectionCard(
      title: l10n.settingsProfile,
      child: Row(
        children: [
          MemberAvatar(name: profile?.displayName ?? '?', radius: 28),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(profile?.displayName ?? '', style: theme.textTheme.titleMedium),
                if (email != null) Text(email, style: theme.textTheme.bodySmall),
                Text(l10n.emailPrivate, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          IconButton(
            tooltip: l10n.editDisplayName,
            icon: const Icon(Icons.edit_rounded),
            onPressed: profile == null ? null : () => unawaited(_editName(context, ref, profile.displayName)),
          ),
        ],
      ),
    );
  }
}

class _GroupsCard extends ConsumerWidget {
  const _GroupsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final group = ref.watch(currentGroupProvider).value;
    return SectionCard(
      title: l10n.settingsGroups,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GroupSwitcher(),
          const SizedBox(height: Spacing.sm),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: () => context.push(Routes.join),
                icon: const Icon(Icons.group_add_outlined),
                label: Text(l10n.joinAnotherGroup),
              ),
              OutlinedButton.icon(
                onPressed: () => context.push(Routes.createGroup),
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.createAnotherGroup),
              ),
              if (group != null)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                  onPressed: () async {
                    final ok = await confirmAction(
                      context,
                      title: l10n.leaveGroupTitle(group.name),
                      message: l10n.leaveGroupMessage,
                      confirmLabel: l10n.leaveGroup,
                      destructive: true,
                    );
                    if (!ok) return;
                    try {
                      await ref.read(groupRepositoryProvider).leaveGroup(group.id);
                      ref.invalidate(myGroupsProvider);
                    } on Object catch (error) {
                      if (context.mounted) showErrorToast(context, error);
                    }
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: Text(l10n.leaveGroup),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard();

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final password = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.changePassword),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PasswordField(
                controller: controller,
                label: l10n.fieldNewPassword,
                autofillHints: const [AutofillHints.newPassword],
                validator: (value) => AuthValidators.newPassword(l10n, value),
              ),
              const SizedBox(height: Spacing.xs),
              Text(l10n.passwordPolicy, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.actionCancel)),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) Navigator.pop(context, controller.text);
            },
            child: Text(l10n.actionSave),
          ),
        ],
      ),
    );
    controller.dispose();
    if (password == null) return;
    try {
      await ref.read(authRepositoryProvider).updatePassword(password);
      if (context.mounted) showToast(context, l10n.passwordUpdated, icon: Icons.check_rounded);
    } on Object catch (error) {
      if (context.mounted) showErrorToast(context, error);
    }
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await confirmByTyping(
      context,
      title: l10n.deleteAccountTitle,
      message: l10n.deleteAccountMessage,
      expected: l10n.deleteAccountKeyword,
      confirmLabel: l10n.deleteAccount,
    );
    if (!confirmed) return;
    try {
      await ref.read(profileRepositoryProvider).deleteAccount();
      await ref.read(authRepositoryProvider).signOut();
    } on Object catch (error) {
      if (context.mounted) showErrorToast(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      title: l10n.settingsAccount,
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.password_rounded),
            title: Text(l10n.changePassword),
            onTap: () => unawaited(_changePassword(context, ref)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.keyboard_rounded),
            title: Text(l10n.shortcutsTitle),
            onTap: () => unawaited(showShortcutsHelp(context)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline_rounded),
            title: Text(l10n.aboutApp),
            subtitle: Text(l10n.versionLabel(appVersion)),
            onTap: () => showLicensePage(context: context, applicationName: l10n.appTitle, applicationVersion: appVersion),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout_rounded),
            title: Text(l10n.signOut),
            onTap: () => unawaited(ref.read(authRepositoryProvider).signOut()),
          ),
          const Divider(height: Spacing.lg),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_forever_rounded, color: scheme.error),
            title: Text(l10n.deleteAccount, style: TextStyle(color: scheme.error)),
            subtitle: Text(l10n.deleteAccountHint),
            onTap: () => unawaited(_deleteAccount(context, ref)),
          ),
        ],
      ),
    );
  }
}
