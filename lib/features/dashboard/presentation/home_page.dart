import 'package:coffee_tracker/app/routes.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/app_card.dart';
import 'package:coffee_tracker/core/widgets/page_layout.dart';
import 'package:coffee_tracker/core/widgets/states.dart';
import 'package:coffee_tracker/features/accounting/application/report_providers.dart';
import 'package:coffee_tracker/features/coffee/presentation/coffee_button.dart';
import 'package:coffee_tracker/features/dashboard/domain/dashboard.dart';
import 'package:coffee_tracker/features/dashboard/presentation/balance_card.dart';
import 'package:coffee_tracker/features/dashboard/presentation/home_widgets.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/notifications/application/notification_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  String _greeting(AppLocalizations l10n, String name) {
    final hour = DateTime.now().hour;
    if (hour < 5) return l10n.greetingNight(name);
    if (hour < 12) return l10n.greetingMorning(name);
    if (hour < 18) return l10n.greetingAfternoon(name);
    return l10n.greetingEvening(name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final groupId = ref.watch(currentGroupIdProvider);
    if (groupId == null) return const SizedBox.shrink();
    final dashboard = ref.watch(dashboardProvider(groupId));
    final unread = ref.watch(unreadNotificationsProvider);
    final compact = WindowSize.of(context).isCompact;
    final name = dashboard.value?.displayName;

    return AppPage(
      title: name == null ? l10n.navHome : _greeting(l10n, name),
      subtitle: dashboard.value?.group.name,
      onRefresh: () async => ref.read(dataRevisionProvider.notifier).bump(),
      actions: [
        if (compact)
          IconButton(
            tooltip: l10n.navNotifications,
            onPressed: () => context.go(Routes.notifications),
            icon: unread > 0
                ? Badge(label: Text('$unread'), child: const Icon(Icons.notifications_outlined))
                : const Icon(Icons.notifications_outlined),
          ),
      ],
      body: AsyncValueView(
        value: dashboard,
        onRetry: () => ref.invalidate(dashboardProvider(groupId)),
        loading: const _HomeSkeleton(),
        data: (data) => _HomeContent(dashboard: data),
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({required this.dashboard});

  final Dashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final groupId = dashboard.group.id;
    final coffee = AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CoffeeButton(
            groupId: groupId,
            todayCoffees: dashboard.todayCoffees,
            priceLabel: context.money(dashboard.priceCents, currency: dashboard.group.currency),
          ),
          PendingCoffeesBanner(groupId: groupId),
        ],
      ),
    );
    final left = [BalanceCard(dashboard: dashboard), coffee, QuickActions(dashboard: dashboard)];
    final right = [AttentionCard(groupId: groupId), RecentActivityCard(dashboard: dashboard), const QuoteCard()];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 860) {
          // On phones the coffee button comes first: one tap from opening the app.
          return _Stack(children: [coffee, left[0], ...right.take(1), left[2], ...right.skip(1)]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: _Stack(children: left)),
            const SizedBox(width: Spacing.md),
            Expanded(flex: 4, child: _Stack(children: right)),
          ],
        );
      },
    );
  }
}

class _Stack extends StatelessWidget {
  const _Stack({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final child in children) ...[child, const SizedBox(height: Spacing.md)],
      ],
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(child: Skeleton(height: 76, radius: Radii.pill)),
        SizedBox(height: Spacing.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Skeleton(height: 14, width: 120),
              SizedBox(height: Spacing.md),
              Skeleton(height: 44, width: 200),
              SizedBox(height: Spacing.md),
              Skeleton(height: 14),
            ],
          ),
        ),
        SizedBox(height: Spacing.md),
        AppCard(child: SkeletonList(rows: 3)),
      ],
    );
  }
}
