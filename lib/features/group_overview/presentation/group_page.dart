import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/finance_colors.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/app_card.dart';
import 'package:coffee_tracker/core/widgets/page_layout.dart';
import 'package:coffee_tracker/core/widgets/stat_tile.dart';
import 'package:coffee_tracker/core/widgets/states.dart';
import 'package:coffee_tracker/features/accounting/application/report_providers.dart';
import 'package:coffee_tracker/features/accounting/domain/balance_models.dart';
import 'package:coffee_tracker/features/group_overview/presentation/balances_table.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class GroupPage extends ConsumerStatefulWidget {
  const GroupPage({super.key});

  @override
  ConsumerState<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends ConsumerState<GroupPage> {
  bool _allTime = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final group = ref.watch(currentGroupProvider).value;
    if (group == null) return const SizedBox.shrink();
    final scope = (groupId: group.id, cycleId: null, allTime: _allTime);
    final overview = ref.watch(overviewProvider(scope));
    final balances = ref.watch(memberBalancesProvider(scope));

    return AppPage(
      title: l10n.navGroup,
      subtitle: group.name,
      onRefresh: () async => ref.read(dataRevisionProvider.notifier).bump(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(l10n.scopeCycle), icon: const Icon(Icons.event_rounded)),
                ButtonSegment(
                  value: true,
                  label: Text(l10n.scopeAllTime),
                  icon: const Icon(Icons.all_inclusive_rounded),
                ),
              ],
              selected: {_allTime},
              onSelectionChanged: (value) => setState(() => _allTime = value.first),
            ),
          ),
          const SizedBox(height: Spacing.md),
          AsyncValueView(
            value: overview,
            onRetry: () => ref.invalidate(overviewProvider(scope)),
            data: (data) => _Overview(overview: data, currency: group.currency),
          ),
          const SizedBox(height: Spacing.lg),
          SectionCard(
            title: l10n.balancesTitle,
            child: AsyncValueView(
              value: balances,
              onRetry: () => ref.invalidate(memberBalancesProvider(scope)),
              data: (rows) => BalancesTable(rows: rows, currency: group.currency),
            ),
          ),
        ],
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.overview, required this.currency});

  final GroupOverview overview;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final finance = FinanceColors.of(context);
    String money(int cents) => context.money(cents, currency: currency);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TileGrid(
          children: [
            StatTile(
              icon: Icons.inventory_2_rounded,
              label: l10n.statCashBox,
              value: money(overview.cashBoxCents),
              caption: l10n.statCashBoxCaption,
              emphasis: true,
            ),
            StatTile(
              icon: Icons.trending_up_rounded,
              label: l10n.statDebts,
              value: money(overview.debtsCents),
              caption: l10n.statMembersCount(overview.membersOwing),
              valueColor: finance.owes,
            ),
            StatTile(
              icon: Icons.trending_down_rounded,
              label: l10n.statCredits,
              value: money(overview.creditsCents),
              caption: l10n.statMembersCount(overview.membersOwed),
              valueColor: finance.owed,
            ),
            StatTile(
              icon: Icons.balance_rounded,
              label: l10n.statNetPosition,
              value: context.money(overview.netPositionCents, currency: currency, signed: true),
              caption: l10n.statNetPositionCaption,
            ),
            StatTile(
              icon: Icons.coffee_rounded,
              label: l10n.statCoffees,
              value: context.number(overview.coffees),
              caption: money(overview.consumptionCents),
            ),
            StatTile(
              icon: Icons.savings_rounded,
              label: l10n.statDeposits,
              value: money(overview.depositsCents),
              caption: l10n.statDepositsCaption,
            ),
            StatTile(
              icon: Icons.shopping_bag_rounded,
              label: l10n.statPersonalPurchases,
              value: money(overview.personalPurchasesCents),
              caption: l10n.statPersonalPurchasesCaption,
            ),
            StatTile(
              icon: Icons.inventory_rounded,
              label: l10n.statBoxPurchases,
              value: money(overview.boxPurchasesCents),
              caption: l10n.statBoxPurchasesCaption,
            ),
            StatTile(
              icon: Icons.groups_rounded,
              label: l10n.statActiveMembers,
              value: context.number(overview.activeMembers),
            ),
            if (overview.pending.count > 0)
              StatTile(
                icon: Icons.schedule_rounded,
                label: l10n.statPending,
                value: context.number(overview.pending.count),
                caption: l10n.statPendingCaption,
                valueColor: finance.pending,
              ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        _MoneyMap(overview: overview, currency: currency),
      ],
    );
  }
}

/// A visual explanation of where the money is: physical cash, money members
/// still owe, and money the group owes to members.
class _MoneyMap extends StatelessWidget {
  const _MoneyMap({required this.overview, required this.currency});

  final GroupOverview overview;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final finance = FinanceColors.of(context);
    final parts = [
      (l10n.statCashBox, overview.cashBoxCents, theme.colorScheme.secondary),
      (l10n.statDebts, overview.debtsCents, finance.owes),
      (l10n.statCredits, overview.creditsCents, finance.owed),
    ];
    final total = parts.fold<int>(0, (sum, p) => sum + p.$2);
    return SectionCard(
      title: l10n.moneyMapTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.moneyMapExplanation, style: theme.textTheme.bodySmall),
          const SizedBox(height: Spacing.md),
          if (total > 0)
            ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.pill),
                child: SizedBox(
                  height: 14,
                  child: Row(
                    children: [
                      for (final (_, cents, color) in parts)
                        if (cents > 0)
                          Expanded(
                            flex: cents,
                            child: ColoredBox(color: color),
                          ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: Spacing.sm),
          Wrap(
            spacing: Spacing.lg,
            runSpacing: Spacing.xs,
            children: [
              for (final (label, cents, color) in parts)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      child: const SizedBox.square(dimension: 10),
                    ),
                    const SizedBox(width: 6),
                    Text('$label: ${context.money(cents, currency: currency)}', style: theme.textTheme.bodySmall),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
