import 'dart:async';

import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/app_card.dart';
import 'package:coffee_tracker/core/widgets/page_layout.dart';
import 'package:coffee_tracker/core/widgets/states.dart';
import 'package:coffee_tracker/features/accounting/application/report_providers.dart';
import 'package:coffee_tracker/features/accounting/data/reports_repository.dart';
import 'package:coffee_tracker/features/accounting/domain/ledger_models.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/groups/domain/group_models.dart';
import 'package:coffee_tracker/features/transactions/presentation/activity_tile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ActivityPage extends ConsumerStatefulWidget {
  const ActivityPage({super.key});

  @override
  ConsumerState<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends ConsumerState<ActivityPage> {
  ActivityFilter _filter = ActivityFilter.none;

  ActivityArgs? get _args {
    final groupId = ref.read(currentGroupIdProvider);
    return groupId == null ? null : (groupId: groupId, filter: _filter);
  }

  bool _onScroll(ScrollNotification notification) {
    final args = _args;
    if (args != null && notification.metrics.extentAfter < 600) {
      unawaited(ref.read(activityFeedProvider(args).notifier).loadMore());
    }
    return false;
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: _filter.from == null
          ? null
          : DateTimeRange(start: _filter.from!, end: _filter.to!.subtract(const Duration(days: 1))),
    );
    if (range == null) return;
    setState(
      () => _filter = _filter.copyWith(
        from: () => DateTime(range.start.year, range.start.month, range.start.day),
        to: () => DateTime(range.end.year, range.end.month, range.end.day + 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final groupId = ref.watch(currentGroupIdProvider);
    if (groupId == null) return const SizedBox.shrink();
    final args = (groupId: groupId, filter: _filter);
    final feed = ref.watch(activityFeedProvider(args));
    final members = ref.watch(membersProvider(groupId)).value ?? const <Member>[];
    final cycles = ref.watch(cyclesProvider(groupId)).value ?? const [];

    final types = [
      (ActivityType.coffee, l10n.filterCoffees),
      (ActivityType.deposit, l10n.filterDeposits),
      (ActivityType.purchase, l10n.filterPurchases),
      (ActivityType.transfer, l10n.filterTransfers),
      (ActivityType.reimbursement, l10n.filterReimbursements),
      (ActivityType.adjustment, l10n.filterAdjustments),
      (ActivityType.reversal, l10n.filterReversals),
      (ActivityType.cycle, l10n.filterCycles),
    ];

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: AppPage(
        title: l10n.navActivity,
        maxWidth: 900,
        onRefresh: () async => ref.invalidate(activityFeedProvider(args)),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (type, label) in types)
                    Padding(
                      padding: const EdgeInsets.only(right: Spacing.xs),
                      child: FilterChip(
                        label: Text(label),
                        selected: _filter.types?.contains(type) ?? false,
                        onSelected: (selected) => setState(() {
                          final next = {...?_filter.types};
                          selected ? next.add(type) : next.remove(type);
                          _filter = _filter.copyWith(types: () => next.isEmpty ? null : next);
                        }),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _filter.memberId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: l10n.fieldMember, isDense: true),
                    items: [
                      DropdownMenuItem(child: Text(l10n.filterEveryone)),
                      for (final member in members)
                        DropdownMenuItem(value: member.userId, child: Text(member.displayName)),
                    ],
                    onChanged: (value) => setState(() => _filter = _filter.copyWith(memberId: () => value)),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _filter.cycleId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: l10n.fieldCycle, isDense: true),
                    items: [
                      DropdownMenuItem(child: Text(l10n.filterAllCycles)),
                      for (final cycle in cycles) DropdownMenuItem(value: cycle.id, child: Text(cycle.name)),
                    ],
                    onChanged: (value) => setState(() => _filter = _filter.copyWith(cycleId: () => value)),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => unawaited(_pickRange()),
                  icon: const Icon(Icons.date_range_rounded),
                  label: Text(
                    _filter.from == null
                        ? l10n.filterAnyDate
                        : '${context.dayMonth(_filter.from!)} – ${context.dayMonth(_filter.to!.subtract(const Duration(days: 1)))}',
                  ),
                ),
                FilterChip(
                  label: Text(l10n.filterOpenOnly),
                  selected: _filter.statuses != null,
                  onSelected: (selected) => setState(
                    () => _filter = _filter.copyWith(
                      statuses: () => selected ? {TransactionStatus.pending, TransactionStatus.disputed} : null,
                    ),
                  ),
                ),
                if (!_filter.isEmpty)
                  TextButton.icon(
                    onPressed: () => setState(() => _filter = ActivityFilter.none),
                    icon: const Icon(Icons.filter_alt_off_rounded),
                    label: Text(l10n.clearFilters),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs),
              child: AsyncValueView(
                value: feed,
                onRetry: () => ref.invalidate(activityFeedProvider(args)),
                data: (page) => page.items.isEmpty
                    ? EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: l10n.activityEmptyTitle,
                        message: _filter.isEmpty ? l10n.activityEmptyMessage : l10n.activityEmptyFiltered,
                      )
                    : _GroupedList(
                        page: page,
                        onLoadMore: () => unawaited(ref.read(activityFeedProvider(args).notifier).loadMore()),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupedList extends StatelessWidget {
  const _GroupedList({required this.page, required this.onLoadMore});

  final ActivityFeedPage page;
  final VoidCallback onLoadMore;

  String _dayLabel(BuildContext context, DateTime day) {
    final l10n = context.l10n;
    final today = DateUtils.dateOnly(DateTime.now());
    if (day == today) return l10n.today;
    if (day == today.subtract(const Duration(days: 1))) return l10n.yesterday;
    return context.shortDate(day);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final children = <Widget>[];
    DateTime? currentDay;
    for (final item in page.items) {
      final day = DateUtils.dateOnly(item.createdAt.toLocal());
      if (day != currentDay) {
        currentDay = day;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.xs, Spacing.md, Spacing.xs, Spacing.xxs),
            child: Semantics(
              header: true,
              child: Text(_dayLabel(context, day), style: Theme.of(context).textTheme.labelLarge),
            ),
          ),
        );
      }
      children.add(ActivityTile(item: item));
    }
    if (page.hasMore) {
      children.add(
        Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Center(
            child: page.loadingMore
                ? const CircularProgressIndicator()
                : page.loadMoreError != null
                ? ErrorState(error: page.loadMoreError!, onRetry: onLoadMore, compact: true)
                : OutlinedButton(onPressed: onLoadMore, child: Text(l10n.loadMore)),
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}
