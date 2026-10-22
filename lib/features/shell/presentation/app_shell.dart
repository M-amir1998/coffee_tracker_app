import 'dart:async';

import 'package:coffee_tracker/app/router.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/member_avatar.dart';
import 'package:coffee_tracker/features/coffee/presentation/coffee_actions.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/groups/domain/group_models.dart';
import 'package:coffee_tracker/features/groups/presentation/group_switcher.dart';
import 'package:coffee_tracker/features/notifications/application/notification_providers.dart';
import 'package:coffee_tracker/features/profile/application/profile_providers.dart';
import 'package:coffee_tracker/features/realtime/realtime_sync.dart';
import 'package:coffee_tracker/features/shell/presentation/app_logo.dart';
import 'package:coffee_tracker/features/shell/presentation/shortcuts_help.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class Destination {
  const Destination(this.branch, this.icon, this.selectedIcon, this.label, {this.badge = 0});

  final ShellBranch branch;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badge;
}

/// Navigation destinations for the signed-in member, adapted to role and
/// preferences.
List<Destination> destinationsFor(AppLocalizations l10n, {required MemberRole? role, required bool heroes, required int unread}) {
  return [
    Destination(ShellBranch.home, Icons.home_outlined, Icons.home_rounded, l10n.navHome),
    Destination(ShellBranch.group, Icons.groups_outlined, Icons.groups_rounded, l10n.navGroup),
    Destination(ShellBranch.activity, Icons.receipt_long_outlined, Icons.receipt_long_rounded, l10n.navActivity),
    if (heroes) Destination(ShellBranch.heroes, Icons.emoji_events_outlined, Icons.emoji_events_rounded, l10n.navHeroes),
    Destination(ShellBranch.analytics, Icons.insights_outlined, Icons.insights_rounded, l10n.navAnalytics),
    Destination(ShellBranch.settle, Icons.handshake_outlined, Icons.handshake_rounded, l10n.navSettleUp),
    Destination(ShellBranch.cycles, Icons.event_repeat_outlined, Icons.event_repeat_rounded, l10n.navCycles),
    if (role != null && role.managesCash)
      Destination(ShellBranch.admin, Icons.admin_panel_settings_outlined, Icons.admin_panel_settings_rounded, l10n.navAdmin),
    Destination(ShellBranch.notifications, Icons.notifications_outlined, Icons.notifications_rounded, l10n.navNotifications, badge: unread),
    Destination(ShellBranch.settings, Icons.settings_outlined, Icons.settings_rounded, l10n.navSettings),
  ];
}

class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  void _go(ShellBranch branch) =>
      navigationShell.goBranch(branch.index, initialLocation: branch.index == navigationShell.currentIndex);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final group = ref.watch(currentGroupProvider).value;
    if (group != null) ref.watch(realtimeSyncProvider(group.id));
    final heroes = ref.watch(preferencesProvider.select((p) => p.gamificationEnabled));
    final unread = ref.watch(unreadNotificationsProvider);
    final destinations = destinationsFor(l10n, role: group?.role, heroes: heroes, unread: unread);
    final current = ShellBranch.values[navigationShell.currentIndex];
    final size = WindowSize.of(context);

    final Widget body = switch (size) {
      WindowSize.compact => _CompactShell(
        shell: navigationShell,
        destinations: destinations,
        current: current,
        onSelect: _go,
        unread: unread,
      ),
      WindowSize.medium => _RailShell(shell: navigationShell, destinations: destinations, current: current, onSelect: _go),
      _ => _SidebarShell(shell: navigationShell, destinations: destinations, current: current, onSelect: _go),
    };

    return CallbackShortcuts(
      bindings: {
        for (final (index, branch) in const [
          ShellBranch.home,
          ShellBranch.group,
          ShellBranch.activity,
          ShellBranch.heroes,
          ShellBranch.analytics,
          ShellBranch.settle,
          ShellBranch.cycles,
          ShellBranch.admin,
          ShellBranch.settings,
        ].indexed)
          SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + index), alt: true): () {
            if (destinations.any((d) => d.branch == branch)) _go(branch);
          },
        const SingleActivator(LogicalKeyboardKey.keyC, alt: true): () {
          if (group != null) unawaited(recordCoffee(context, ref, groupId: group.id));
        },
        const SingleActivator(LogicalKeyboardKey.keyR, alt: true): () => ref.read(dataRevisionProvider.notifier).bump(),
        const SingleActivator(LogicalKeyboardKey.slash, alt: true): () => unawaited(showShortcutsHelp(context)),
      },
      child: Focus(autofocus: true, child: body),
    );
  }
}

class _CompactShell extends StatelessWidget {
  const _CompactShell({
    required this.shell,
    required this.destinations,
    required this.current,
    required this.onSelect,
    required this.unread,
  });

  final StatefulNavigationShell shell;
  final List<Destination> destinations;
  final ShellBranch current;
  final ValueChanged<ShellBranch> onSelect;
  final int unread;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Phones show four primary destinations plus "More".
    final primary = destinations.where((d) => d.branch.index <= ShellBranch.analytics.index).take(4).toList();
    final more = Destination(ShellBranch.more, Icons.menu_rounded, Icons.menu_open_rounded, l10n.navMore, badge: unread);
    final items = [...primary, more];
    final selected = items.indexWhere((d) => d.branch == current);

    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected < 0 ? items.length - 1 : selected,
        onDestinationSelected: (index) => onSelect(items[index].branch),
        destinations: [
          for (final d in items)
            NavigationDestination(
              icon: _BadgeIcon(icon: d.icon, count: d.badge),
              selectedIcon: _BadgeIcon(icon: d.selectedIcon, count: d.badge),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _RailShell extends StatelessWidget {
  const _RailShell({required this.shell, required this.destinations, required this.current, required this.onSelect});

  final StatefulNavigationShell shell;
  final List<Destination> destinations;
  final ShellBranch current;
  final ValueChanged<ShellBranch> onSelect;

  @override
  Widget build(BuildContext context) {
    final selected = destinations.indexWhere((d) => d.branch == current);
    return Scaffold(
      body: Row(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).height - 48),
                child: IntrinsicHeight(
                  child: NavigationRail(
                    selectedIndex: selected < 0 ? null : selected,
                    onDestinationSelected: (index) => onSelect(destinations[index].branch),
                    labelType: NavigationRailLabelType.all,
                    leading: const Padding(padding: EdgeInsets.symmetric(vertical: Spacing.sm), child: AppLogo(size: 40)),
                    destinations: [
                      for (final d in destinations)
                        NavigationRailDestination(
                          icon: _BadgeIcon(icon: d.icon, count: d.badge),
                          selectedIcon: _BadgeIcon(icon: d.selectedIcon, count: d.badge),
                          label: Text(d.label),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: shell),
        ],
      ),
    );
  }
}

class _SidebarShell extends ConsumerWidget {
  const _SidebarShell({required this.shell, required this.destinations, required this.current, required this.onSelect});

  final StatefulNavigationShell shell;
  final List<Destination> destinations;
  final ShellBranch current;
  final ValueChanged<ShellBranch> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final profile = ref.watch(myProfileProvider).value;
    final main = destinations.where((d) => d.branch.index < ShellBranch.admin.index).toList();
    final admin = destinations.where((d) => d.branch == ShellBranch.admin).toList();
    final footer = destinations.where((d) => d.branch.index > ShellBranch.admin.index).toList();

    Widget item(Destination d) => _SidebarItem(destination: d, selected: d.branch == current, onTap: () => onSelect(d.branch));

    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 268,
            child: Material(
              color: theme.colorScheme.surfaceContainerLow,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.lg, Spacing.md, Spacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const AppLogo(size: 40),
                          const SizedBox(width: Spacing.sm),
                          Expanded(child: Text(l10n.appTitle, style: theme.textTheme.headlineSmall)),
                        ],
                      ),
                      const SizedBox(height: Spacing.lg),
                      const GroupSwitcher(),
                      const SizedBox(height: Spacing.md),
                      Expanded(
                        child: ListView(
                          children: [
                            for (final d in main) item(d),
                            if (admin.isNotEmpty) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(Spacing.sm, Spacing.lg, Spacing.sm, Spacing.xs),
                                child: Text(l10n.navSectionAdministration, style: theme.textTheme.labelMedium),
                              ),
                              for (final d in admin) item(d),
                            ],
                          ],
                        ),
                      ),
                      for (final d in footer) item(d),
                      if (profile != null) ...[
                        const Divider(height: Spacing.lg),
                        Row(
                          children: [
                            MemberAvatar(name: profile.displayName),
                            const SizedBox(width: Spacing.sm),
                            Expanded(
                              child: Text(profile.displayName, style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis),
                            ),
                            IconButton(
                              tooltip: l10n.shortcutsTitle,
                              icon: const Icon(Icons.keyboard_outlined),
                              onPressed: () => unawaited(showShortcutsHelp(context)),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: shell),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({required this.destination, required this.selected, required this.onTap});

  final Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? scheme.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.md),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      destination.label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: selected ? scheme.onSecondaryContainer : scheme.onSurface,
                      ),
                    ),
                  ),
                  if (destination.badge > 0) Badge(label: Text('${destination.badge}')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BadgeIcon extends StatelessWidget {
  const _BadgeIcon({required this.icon, required this.count});

  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) =>
      count > 0 ? Badge(label: Text(count > 99 ? '99+' : '$count'), child: Icon(icon)) : Icon(icon);
}
