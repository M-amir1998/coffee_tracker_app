import 'package:coffee_tracker/app/routes.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/app_card.dart';
import 'package:coffee_tracker/core/widgets/page_layout.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/groups/presentation/group_switcher.dart';
import 'package:coffee_tracker/features/notifications/application/notification_providers.dart';
import 'package:coffee_tracker/features/profile/application/profile_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Secondary destinations on phones.
class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final role = ref.watch(currentGroupProvider).value?.role;
    final unread = ref.watch(unreadNotificationsProvider);
    final heroes = ref.watch(preferencesProvider.select((p) => p.gamificationEnabled));

    final items = [
      if (heroes) (Icons.insights_rounded, l10n.navAnalytics, l10n.moreAnalyticsHint, Routes.analytics, 0),
      (Icons.handshake_rounded, l10n.navSettleUp, l10n.moreSettleHint, Routes.settle, 0),
      (Icons.event_repeat_rounded, l10n.navCycles, l10n.moreCyclesHint, Routes.cycles, 0),
      if (role != null && role.managesCash)
        (Icons.admin_panel_settings_rounded, l10n.navAdmin, l10n.moreAdminHint, Routes.admin, 0),
      (Icons.notifications_rounded, l10n.navNotifications, l10n.moreNotificationsHint, Routes.notifications, unread),
      (Icons.settings_rounded, l10n.navSettings, l10n.moreSettingsHint, Routes.settings, 0),
    ];

    return AppPage(
      title: l10n.navMore,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GroupSwitcher(),
          const SizedBox(height: Spacing.md),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
            child: Column(
              children: [
                for (final (icon, title, subtitle, route, badge) in items)
                  ListTile(
                    leading: Icon(icon),
                    title: Text(title),
                    subtitle: Text(subtitle),
                    trailing: badge > 0 ? Badge(label: Text('$badge')) : const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.go(route),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
