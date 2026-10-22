import 'dart:async';

import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/app_card.dart';
import 'package:coffee_tracker/core/widgets/feedback.dart';
import 'package:coffee_tracker/core/widgets/page_layout.dart';
import 'package:coffee_tracker/features/admin/domain/csv_exports.dart';
import 'package:coffee_tracker/features/admin/presentation/file_export.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/leaderboard/domain/leaderboard_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ExportsPage extends ConsumerStatefulWidget {
  const ExportsPage({super.key});

  @override
  ConsumerState<ExportsPage> createState() => _ExportsPageState();
}

class _ExportsPageState extends ConsumerState<ExportsPage> {
  DateTimeRange? _range;
  String? _busy;

  String get _stamp => DateTime.now().toIso8601String().substring(0, 10);

  Future<void> _export(String id, Future<(String, String)> Function() build) async {
    setState(() => _busy = id);
    try {
      final (name, content) = await build();
      if (!mounted) return;
      final saved = await exportTextFile(context, fileName: name, content: content);
      if (mounted && saved) showToast(context, context.l10n.exportDone, icon: Icons.check_rounded);
    } on Object catch (error) {
      if (mounted) showErrorToast(context, error);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final group = ref.watch(currentGroupProvider).value;
    if (group == null) return const SizedBox.shrink();
    final reports = ref.read(reportsRepositoryProvider);
    final from = _range?.start;
    final to = _range?.end.add(const Duration(days: 1));

    final exports = <(String, IconData, String, String, Future<(String, String)> Function())>[
      (
        'balances',
        Icons.account_balance_wallet_rounded,
        l10n.exportBalancesCycle,
        l10n.exportBalancesCycleHint,
        () async => (
          'balances-cycle-$_stamp.csv',
          balancesCsv(await reports.memberBalances(group.id), currency: group.currency, scope: 'cycle'),
        ),
      ),
      (
        'balances_all',
        Icons.all_inclusive_rounded,
        l10n.exportBalancesAllTime,
        l10n.exportBalancesAllTimeHint,
        () async => (
          'balances-all-time-$_stamp.csv',
          balancesCsv(await reports.memberBalances(group.id, allTime: true), currency: group.currency, scope: 'all_time'),
        ),
      ),
      (
        'coffees',
        Icons.coffee_rounded,
        l10n.exportCoffeeStats,
        l10n.exportCoffeeStatsHint,
        () async {
          final boards = <String, LeaderboardData>{};
          for (final period in LeaderboardPeriod.values) {
            boards[period.wireName] = await reports.leaderboard(group.id, period);
          }
          return ('coffee-statistics-$_stamp.csv', coffeeStatsCsv(boards));
        },
      ),
      (
        'transactions',
        Icons.receipt_long_rounded,
        l10n.exportTransactions,
        l10n.exportTransactionsHint,
        () async => (
          'transactions-$_stamp.csv',
          transactionsCsv(await reports.exportTransactions(group.id, from: from, to: to), currency: group.currency),
        ),
      ),
      (
        'purchases',
        Icons.shopping_bag_rounded,
        l10n.exportPurchases,
        l10n.exportPurchasesHint,
        () async => (
          'bean-purchases-$_stamp.csv',
          purchasesCsv(await reports.exportTransactions(group.id, from: from, to: to), currency: group.currency),
        ),
      ),
    ];

    return AppPage(
      title: l10n.adminExports,
      showBackButton: true,
      maxWidth: 760,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.exportsExplanation),
                const SizedBox(height: Spacing.sm),
                OutlinedButton.icon(
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(now.year - 5),
                      lastDate: now,
                      initialDateRange: _range,
                    );
                    setState(() => _range = picked);
                  },
                  icon: const Icon(Icons.date_range_rounded),
                  label: Text(
                    _range == null
                        ? l10n.exportRangeAll
                        : '${context.shortDate(_range!.start)} – ${context.shortDate(_range!.end)}',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.md),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
            child: Column(
              children: [
                for (final (id, icon, title, subtitle, build) in exports)
                  ListTile(
                    leading: Icon(icon),
                    title: Text(title),
                    subtitle: Text(subtitle),
                    trailing: _busy == id
                        ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download_rounded),
                    onTap: _busy != null ? null : () => unawaited(_export(id, build)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Text(l10n.exportCycleHint, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
