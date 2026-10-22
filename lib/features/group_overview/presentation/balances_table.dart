import 'package:coffee_tracker/app/routes.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/money/money.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/member_avatar.dart';
import 'package:coffee_tracker/core/widgets/money_text.dart';
import 'package:coffee_tracker/core/widgets/states.dart';
import 'package:coffee_tracker/core/widgets/status_chip.dart';
import 'package:coffee_tracker/features/accounting/domain/balance_models.dart';
import 'package:coffee_tracker/features/groups/domain/group_models.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

enum BalanceSort { name, coffees, consumption, contributions, net }

/// Pure filtering and sorting, separated for testing.
List<MemberBalance> filterAndSortBalances(
  List<MemberBalance> rows, {
  String query = '',
  BalanceStatus? status,
  BalanceSort sort = BalanceSort.name,
  bool ascending = true,
}) {
  final q = query.trim().toLowerCase();
  final filtered = rows
      .where((r) => q.isEmpty || r.displayName.toLowerCase().contains(q))
      .where((r) => status == null || r.status == status)
      .toList();
  int compare(MemberBalance a, MemberBalance b) => switch (sort) {
    BalanceSort.name => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    BalanceSort.coffees => a.breakdown.coffees.compareTo(b.breakdown.coffees),
    BalanceSort.consumption => a.breakdown.consumptionCents.compareTo(b.breakdown.consumptionCents),
    BalanceSort.contributions => a.breakdown.contributionsCents.compareTo(b.breakdown.contributionsCents),
    BalanceSort.net => a.breakdown.netCents.compareTo(b.breakdown.netCents),
  };
  filtered.sort((a, b) {
    final result = compare(a, b);
    final ordered = ascending ? result : -result;
    return ordered != 0 ? ordered : a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  });
  return filtered;
}

class BalancesTable extends StatefulWidget {
  const BalancesTable({required this.rows, required this.currency, super.key});

  final List<MemberBalance> rows;
  final String currency;

  @override
  State<BalancesTable> createState() => _BalancesTableState();
}

class _BalancesTableState extends State<BalancesTable> {
  String _query = '';
  BalanceStatus? _status;
  BalanceSort _sort = BalanceSort.name;
  bool _ascending = true;

  void _sortBy(BalanceSort sort) => setState(() {
    if (_sort == sort) {
      _ascending = !_ascending;
    } else {
      _sort = sort;
      _ascending = sort == BalanceSort.name;
    }
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rows = filterAndSortBalances(widget.rows, query: _query, status: _status, sort: _sort, ascending: _ascending);
    final wide = WindowSize.of(context).isAtLeastExpanded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: wide ? 280 : double.infinity,
              child: TextField(
                decoration: InputDecoration(
                  hintText: l10n.searchMembers,
                  prefixIcon: const Icon(Icons.search_rounded),
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            for (final (status, label) in [
              (null, l10n.filterAll),
              (BalanceStatus.owes, l10n.statusOwes),
              (BalanceStatus.owed, l10n.statusOwed),
              (BalanceStatus.settled, l10n.statusSettled),
            ])
              ChoiceChip(
                label: Text(label),
                selected: _status == status,
                onSelected: (_) => setState(() => _status = status),
              ),
            if (!wide)
              PopupMenuButton<BalanceSort>(
                tooltip: l10n.sortBy,
                icon: const Icon(Icons.sort_rounded),
                onSelected: _sortBy,
                itemBuilder: (context) => [
                  for (final (sort, label) in _sortLabels(l10n))
                    CheckedPopupMenuItem(value: sort, checked: sort == _sort, child: Text(label)),
                ],
              ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        if (rows.isEmpty)
          EmptyState(icon: Icons.person_search_rounded, title: l10n.noMembersMatch)
        else if (wide)
          _WideTable(rows: rows, currency: widget.currency, sort: _sort, ascending: _ascending, onSort: _sortBy)
        else
          for (final row in rows) _MemberCard(row: row, currency: widget.currency),
      ],
    );
  }

  static List<(BalanceSort, String)> _sortLabels(AppLocalizations l10n) => [
    (BalanceSort.name, l10n.columnMember),
    (BalanceSort.coffees, l10n.columnCoffees),
    (BalanceSort.consumption, l10n.columnConsumption),
    (BalanceSort.contributions, l10n.columnContributions),
    (BalanceSort.net, l10n.columnNet),
  ];
}

class _WideTable extends StatelessWidget {
  const _WideTable({
    required this.rows,
    required this.currency,
    required this.sort,
    required this.ascending,
    required this.onSort,
  });

  final List<MemberBalance> rows;
  final String currency;
  final BalanceSort sort;
  final bool ascending;
  final ValueChanged<BalanceSort> onSort;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    DataColumn column(String label, BalanceSort value, {bool numeric = true}) =>
        DataColumn(label: Text(label), numeric: numeric, onSort: (_, _) => onSort(value));

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: DataTable(
            sortColumnIndex: BalanceSort.values.indexOf(sort),
            sortAscending: ascending,
            showCheckboxColumn: false,
            headingTextStyle: theme.textTheme.labelLarge,
            columns: [
              column(l10n.columnMember, BalanceSort.name, numeric: false),
              column(l10n.columnCoffees, BalanceSort.coffees),
              column(l10n.columnConsumption, BalanceSort.consumption),
              column(l10n.columnContributions, BalanceSort.contributions),
              column(l10n.columnNet, BalanceSort.net),
              DataColumn(label: Text(l10n.columnStatus)),
            ],
            rows: [
              for (final row in rows)
                DataRow(
                  onSelectChanged: (_) => context.push(Routes.member(row.userId)),
                  cells: [
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MemberAvatar(name: row.displayName, radius: 14),
                          const SizedBox(width: Spacing.sm),
                          Text(row.isMe ? l10n.youSuffix(row.displayName) : row.displayName),
                          if (row.membershipStatus != MembershipStatus.active) ...[
                            const SizedBox(width: Spacing.xs),
                            Text(l10n.formerMember, style: theme.textTheme.bodySmall),
                          ],
                        ],
                      ),
                    ),
                    DataCell(
                      Text(context.number(row.breakdown.coffees), style: const TextStyle(fontFeatures: tabularFigures)),
                    ),
                    DataCell(MoneyText(row.breakdown.consumptionCents, currency: currency)),
                    DataCell(MoneyText(row.breakdown.contributionsCents, currency: currency)),
                    DataCell(
                      MoneyText(
                        row.breakdown.netCents,
                        currency: currency,
                        colorBySign: true,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    DataCell(BalanceStatusChip(row.status)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.row, required this.currency});

  final MemberBalance row;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final b = row.breakdown;
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: () => context.push(Routes.member(row.userId)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.sm, horizontal: Spacing.xs),
        child: Row(
          children: [
            MemberAvatar(name: row.displayName),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.isMe ? l10n.youSuffix(row.displayName) : row.displayName, style: theme.textTheme.titleSmall),
                  Text(
                    l10n.memberCardSummary(
                      b.coffees,
                      context.money(b.consumptionCents, currency: currency),
                      context.money(b.contributionsCents, currency: currency),
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                MoneyText(b.netCents, currency: currency, colorBySign: true, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                BalanceStatusChip(row.status),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
