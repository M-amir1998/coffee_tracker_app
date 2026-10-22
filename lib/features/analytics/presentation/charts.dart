import 'dart:math' as math;

import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';

/// One series of a bar chart.
class BarSeries {
  const BarSeries({required this.label, required this.values, required this.color});

  final String label;
  final List<double> values;
  final Color color;
}

double _niceMax(double max) {
  if (max <= 0) return 1;
  final magnitude = math.pow(10, (math.log(max) / math.ln10).floor()).toDouble();
  for (final step in [1, 2, 2.5, 5, 10]) {
    if (step * magnitude >= max) return step * magnitude;
  }
  return 10 * magnitude;
}

TextStyle _axisStyle(BuildContext context) =>
    Theme.of(context).textTheme.bodySmall!
        .copyWith(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant);

/// Grouped bar chart with labelled axes and tooltips.
class SimpleBarChart extends StatelessWidget {
  const SimpleBarChart({
    required this.labels,
    required this.series,
    required this.semanticLabel,
    super.key,
    this.height = 220,
    this.valueFormatter,
    this.labelEvery = 1,
  });

  final List<String> labels;
  final List<BarSeries> series;
  final String semanticLabel;
  final double height;
  final String Function(double value)? valueFormatter;

  /// Show every n-th x-axis label to avoid crowding.
  final int labelEvery;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final format = valueFormatter ?? (double v) => v.round().toString();
    final maxValue = series.expand((s) => s.values).fold<double>(0, math.max);
    final maxY = _niceMax(maxValue);
    final barWidth = math.max(3, math.min(18, 260 / math.max(1, labels.length * series.length))).toDouble();

    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        height: height,
        child: BarChart(
          BarChartData(
            maxY: maxY,
            alignment: BarChartAlignment.spaceAround,
            barGroups: [
              for (var i = 0; i < labels.length; i++)
                BarChartGroupData(
                  x: i,
                  barsSpace: 2,
                  barRods: [
                    for (final s in series)
                      BarChartRodData(
                        toY: i < s.values.length ? s.values[i] : 0,
                        color: s.color,
                        width: barWidth,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                  ],
                ),
            ],
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: maxY / 4,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: scheme.outlineVariant.withValues(alpha: 0.6), strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  interval: maxY / 4,
                  getTitlesWidget: (value, meta) => SideTitleWidget(
                    meta: meta,
                    child: Text(format(value), style: _axisStyle(context)),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 26,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index >= labels.length || index % labelEvery != 0) return const SizedBox.shrink();
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(labels[index], style: _axisStyle(context)),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => scheme.inverseSurface,
                getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                  '${labels[group.x]}\n${series[rodIndex].label}: ${format(rod.toY)}',
                  TextStyle(color: scheme.onInverseSurface, fontSize: 12),
                ),
              ),
            ),
          ),
          duration: Motion.of(context, Motion.medium),
        ),
      ),
    );
  }
}

class LineSeries {
  const LineSeries({required this.label, required this.values, required this.color, this.filled = false});

  final String label;
  final List<double> values;
  final Color color;
  final bool filled;
}

/// Line chart for trends over time.
class TrendLineChart extends StatelessWidget {
  const TrendLineChart({
    required this.labels,
    required this.series,
    required this.semanticLabel,
    super.key,
    this.height = 220,
    this.valueFormatter,
    this.labelEvery = 1,
  });

  final List<String> labels;
  final List<LineSeries> series;
  final String semanticLabel;
  final double height;
  final String Function(double value)? valueFormatter;
  final int labelEvery;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final format = valueFormatter ?? (double v) => v.round().toString();
    final all = series.expand((s) => s.values);
    final maxY = _niceMax(all.fold<double>(0, math.max));
    final minValue = all.fold<double>(0, math.min);
    final minY = minValue < 0 ? -_niceMax(-minValue) : 0.0;

    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        height: height,
        child: LineChart(
          LineChartData(
            minY: minY,
            maxY: maxY,
            lineBarsData: [
              for (final s in series)
                LineChartBarData(
                  spots: [for (var i = 0; i < s.values.length; i++) FlSpot(i.toDouble(), s.values[i])],
                  color: s.color,
                  barWidth: 2.5,
                  isCurved: true,
                  preventCurveOverShooting: true,
                  dotData: FlDotData(show: s.values.length <= 14),
                  belowBarData: BarAreaData(show: s.filled, color: s.color.withValues(alpha: 0.15)),
                ),
            ],
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: (maxY - minY) / 4,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: scheme.outlineVariant.withValues(alpha: 0.6), strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 48,
                  interval: (maxY - minY) / 4,
                  getTitlesWidget: (value, meta) => SideTitleWidget(
                    meta: meta,
                    child: Text(format(value), style: _axisStyle(context)),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 26,
                  interval: 1,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (value != index || index < 0 || index >= labels.length || index % labelEvery != 0) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(labels[index], style: _axisStyle(context)),
                    );
                  },
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => scheme.inverseSurface,
                getTooltipItems: (spots) => [
                  for (final spot in spots)
                    LineTooltipItem(
                      '${labels[spot.x.toInt()]}\n${series[spot.barIndex].label}: ${format(spot.y)}',
                      TextStyle(color: scheme.onInverseSurface, fontSize: 12),
                    ),
                ],
              ),
            ),
          ),
          duration: Motion.of(context, Motion.medium),
        ),
      ),
    );
  }
}

/// Small legend row for charts.
class ChartLegend extends StatelessWidget {
  const ChartLegend({required this.items, super.key});

  final List<(String, Color)> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Spacing.md,
      runSpacing: Spacing.xxs,
      children: [
        for (final (label, color) in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                child: const SizedBox(width: 12, height: 12),
              ),
              const SizedBox(width: 6),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
      ],
    );
  }
}
