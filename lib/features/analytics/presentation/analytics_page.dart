import 'dart:async';
import 'dart:math' as math;

import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/app_card.dart';
import 'package:coffee_tracker/core/widgets/page_layout.dart';
import 'package:coffee_tracker/core/widgets/stat_tile.dart';
import 'package:coffee_tracker/core/widgets/states.dart';
import 'package:coffee_tracker/features/accounting/application/report_providers.dart';
import 'package:coffee_tracker/features/analytics/domain/analytics_models.dart';
import 'package:coffee_tracker/features/analytics/domain/trends.dart';
import 'package:coffee_tracker/features/analytics/presentation/charts.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

enum _Preset { week, month, quarter, year, custom }

class AnalyticsPage extends ConsumerStatefulWidget {
  const AnalyticsPage({super.key});

  @override
  ConsumerState<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends ConsumerState<AnalyticsPage> {
  _Preset _preset = _Preset.month;
  DateTimeRange? _custom;

  DateTimeRange get _range {
    final today = DateUtils.dateOnly(DateTime.now());
    return switch (_preset) {
      _Preset.week => DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today),
      _Preset.month => DateTimeRange(start: today.subtract(const Duration(days: 29)), end: today),
      _Preset.quarter => DateTimeRange(start: today.subtract(const Duration(days: 89)), end: today),
      _Preset.year => DateTimeRange(start: today.subtract(const Duration(days: 364)), end: today),
      _Preset.custom => _custom ?? DateTimeRange(start: today.subtract(const Duration(days: 29)), end: today),
    };
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _range,
    );
    if (picked != null) {
      setState(() {
        _custom = picked;
        _preset = _Preset.custom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final group = ref.watch(currentGroupProvider).value;
    if (group == null) return const SizedBox.shrink();
    final range = _range;
    final args = (groupId: group.id, from: range.start, to: range.end);
    final data = ref.watch(analyticsProvider(args));

    return AppPage(
      title: l10n.navAnalytics,
      subtitle: '${context.shortDate(range.start)} – ${context.shortDate(range.end)}',
      onRefresh: () async => ref.invalidate(analyticsProvider(args)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: Spacing.xs,
            runSpacing: Spacing.xs,
            children: [
              for (final (preset, label) in [
                (_Preset.week, l10n.range7Days),
                (_Preset.month, l10n.range30Days),
                (_Preset.quarter, l10n.range90Days),
                (_Preset.year, l10n.range12Months),
              ])
                ChoiceChip(label: Text(label), selected: _preset == preset, onSelected: (_) => setState(() => _preset = preset)),
              ChoiceChip(
                avatar: const Icon(Icons.date_range_rounded, size: 18),
                label: Text(l10n.rangeCustom),
                selected: _preset == _Preset.custom,
                onSelected: (_) => unawaited(_pickCustom()),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          AsyncValueView(
            value: data,
            onRetry: () => ref.invalidate(analyticsProvider(args)),
            data: (analytics) => _AnalyticsContent(data: analytics, currency: group.currency),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsContent extends StatelessWidget {
  const _AnalyticsContent({required this.data, required this.currency});

  final AnalyticsData data;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final days = data.to.difference(data.from).inDays + 1;
    final granularity = granularityFor(days);
    final trend = aggregateTrend(data.daily, granularity);
    String bucketLabel(DateTime start) => switch (granularity) {
      TrendGranularity.month => context.monthShort(start),
      _ => context.dayMonth(start),
    };
    final labels = [for (final p in trend) bucketLabel(p.start)];
    final every = math.max(1, (labels.length / 8).ceil());
    String euros(double cents) => context.money(cents.round(), currency: currency);

    final groupColor = scheme.secondary;
    final myColor = scheme.tertiary;

    final consumption = SectionCard(
      title: switch (granularity) {
        TrendGranularity.day => l10n.chartDailyConsumption,
        TrendGranularity.week => l10n.chartWeeklyConsumption,
        TrendGranularity.month => l10n.chartMonthlyConsumption,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChartLegend(items: [(l10n.seriesGroup, groupColor), (l10n.seriesYou, myColor)]),
          const SizedBox(height: Spacing.sm),
          SimpleBarChart(
            labels: labels,
            labelEvery: every,
            semanticLabel: l10n.chartConsumptionSemantic(data.groupCoffees, data.myCoffees),
            series: [
              BarSeries(label: l10n.seriesGroup, values: [for (final p in trend) p.groupCoffees.toDouble()], color: groupColor),
              BarSeries(label: l10n.seriesYou, values: [for (final p in trend) p.myCoffees.toDouble()], color: myColor),
            ],
          ),
        ],
      ),
    );

    final weekday = SectionCard(
      title: l10n.chartByWeekday,
      child: SimpleBarChart(
        height: 180,
        labels: [for (final b in data.weekday) context.weekdayShort(b.bucket)],
        semanticLabel: l10n.chartByWeekday,
        series: [
          BarSeries(label: l10n.seriesGroup, values: [for (final b in data.weekday) b.groupCoffees.toDouble()], color: groupColor),
          BarSeries(label: l10n.seriesYou, values: [for (final b in data.weekday) b.myCoffees.toDouble()], color: myColor),
        ],
      ),
    );

    final hourly = SectionCard(
      title: l10n.chartByHour,
      child: SimpleBarChart(
        height: 180,
        labels: [for (final b in data.hourly) '${b.bucket}'],
        labelEvery: 3,
        semanticLabel: l10n.chartByHour,
        series: [
          BarSeries(label: l10n.seriesGroup, values: [for (final b in data.hourly) b.groupCoffees.toDouble()], color: groupColor),
        ],
      ),
    );

    final spending = SectionCard(
      title: l10n.chartSpending,
      child: TrendLineChart(
        labels: labels,
        labelEvery: every,
        valueFormatter: euros,
        semanticLabel: l10n.chartSpendingSemantic(context.money(data.groupSpendCents, currency: currency)),
        series: [
          LineSeries(label: l10n.seriesGroup, values: [for (final p in trend) p.groupSpendCents.toDouble()], color: groupColor, filled: true),
          LineSeries(label: l10n.seriesYou, values: [for (final p in trend) p.mySpendCents.toDouble()], color: myColor),
        ],
      ),
    );

    final cashEvery = math.max(1, (data.cashBox.length / 8).ceil());
    final cash = SectionCard(
      title: l10n.chartCashBox,
      child: TrendLineChart(
        labels: [for (final p in data.cashBox) context.dayMonth(p.date)],
        labelEvery: cashEvery,
        valueFormatter: euros,
        semanticLabel: l10n.chartCashBoxSemantic(
          context.money(data.cashBox.isEmpty ? 0 : data.cashBox.last.balanceCents, currency: currency),
        ),
        series: [
          LineSeries(
            label: l10n.statCashBox,
            values: [for (final p in data.cashBox) p.balanceCents.toDouble()],
            color: scheme.primary,
            filled: true,
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TileGrid(
          children: [
            StatTile(icon: Icons.coffee_rounded, label: l10n.statGroupCoffees, value: context.number(data.groupCoffees)),
            StatTile(icon: Icons.person_rounded, label: l10n.statMyCoffees, value: context.number(data.myCoffees)),
            StatTile(
              icon: Icons.euro_rounded,
              label: l10n.statGroupSpend,
              value: context.money(data.groupSpendCents, currency: currency),
            ),
            StatTile(
              icon: Icons.groups_rounded,
              label: l10n.statParticipation,
              value: '${data.consumingMembers}/${data.activeMembers}',
              caption: l10n.statParticipationCaption,
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        ResponsiveColumns(
          minColumnWidth: 460,
          maxColumns: 2,
          children: [
            consumption,
            spending,
            weekday,
            hourly,
            cash,
            _CycleComparison(data: data, currency: currency),
            _Participation(data: data),
            _Purchases(data: data, currency: currency),
          ],
        ),
      ],
    );
  }
}

class _CycleComparison extends StatelessWidget {
  const _CycleComparison({required this.data, required this.currency});

  final AnalyticsData data;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final current = data.currentCycle;
    final previous = data.previousCycle;
    final rows = <(String, String, String?, int?)>[
      (
        l10n.compareCoffeesPerDay,
        current.coffeesPerDay.toStringAsFixed(1),
        previous?.coffeesPerDay.toStringAsFixed(1),
        previous == null ? null : percentChange(current.coffeesPerDay, previous.coffeesPerDay),
      ),
      (
        l10n.compareCoffees,
        context.number(current.coffees),
        previous == null ? null : context.number(previous.coffees),
        previous == null ? null : percentChange(current.coffees, previous.coffees),
      ),
      (
        l10n.compareConsumption,
        context.money(current.consumptionCents, currency: currency),
        previous == null ? null : context.money(previous.consumptionCents, currency: currency),
        previous == null ? null : percentChange(current.consumptionCents, previous.consumptionCents),
      ),
      (
        l10n.compareConsumers,
        context.number(current.consumers),
        previous == null ? null : context.number(previous.consumers),
        null,
      ),
    ];
    return SectionCard(
      title: l10n.compareTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            previous == null ? l10n.compareNoPrevious(current.cycle.name) : l10n.compareSubtitle(current.cycle.name, previous.cycle.name),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: Spacing.sm),
          for (final (label, now, before, change) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(child: Text(label)),
                  Text(now, style: theme.textTheme.titleSmall),
                  if (before != null) ...[
                    const SizedBox(width: Spacing.sm),
                    Text(l10n.compareWas(before), style: theme.textTheme.bodySmall),
                  ],
                  if (change != null) ...[
                    const SizedBox(width: Spacing.sm),
                    Text(
                      '${change > 0 ? '+' : ''}$change%',
                      style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.secondary),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Participation extends StatelessWidget {
  const _Participation({required this.data});

  final AnalyticsData data;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final total = data.groupCoffees;
    return SectionCard(
      title: l10n.participationTitle,
      child: data.participation.isEmpty
          ? Text(l10n.noDataInRange)
          : Column(
              children: [
                for (final entry in data.participation.take(12))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(
                            entry.displayName ?? l10n.hiddenMember,
                            overflow: TextOverflow.ellipsis,
                            style: entry.isMe ? theme.textTheme.titleSmall : null,
                          ),
                        ),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: total == 0 ? 0 : entry.coffees / total,
                            minHeight: 10,
                            borderRadius: BorderRadius.circular(Radii.pill),
                            color: entry.isMe ? theme.colorScheme.tertiary : theme.colorScheme.secondary,
                            backgroundColor: theme.colorScheme.surfaceContainerHigh,
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        SizedBox(width: 44, child: Text('${entry.coffees}', textAlign: TextAlign.end)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Purchases extends StatelessWidget {
  const _Purchases({required this.data, required this.currency});

  final AnalyticsData data;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final total = data.purchases.fold<int>(0, (sum, p) => sum + p.amountCents);
    return SectionCard(
      title: l10n.purchaseHistoryTitle,
      trailing: Text(context.money(total, currency: currency), style: Theme.of(context).textTheme.titleSmall),
      child: data.purchases.isEmpty
          ? Text(l10n.noPurchasesInRange)
          : Column(
              children: [
                for (final p in data.purchases.reversed.take(10))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(p.fromCashBox ? Icons.inventory_2_rounded : Icons.shopping_bag_rounded),
                    title: Text(p.description ?? l10n.purchaseDefaultDescription),
                    subtitle: Text(
                      '${context.shortDate(p.date)} · ${p.memberName ?? ''} · ${p.fromCashBox ? l10n.purchaseFundingBox : l10n.purchaseFundingPersonal}',
                    ),
                    trailing: Text(context.money(p.amountCents, currency: currency)),
                  ),
              ],
            ),
    );
  }
}
