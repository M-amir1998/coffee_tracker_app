import 'package:coffee_tracker/features/analytics/domain/analytics_models.dart';

enum TrendGranularity { day, week, month }

class TrendPoint {
  const TrendPoint({
    required this.start,
    required this.groupCoffees,
    required this.myCoffees,
    required this.groupSpendCents,
    required this.mySpendCents,
  });

  /// First calendar day of the bucket.
  final DateTime start;
  final int groupCoffees;
  final int myCoffees;
  final int groupSpendCents;
  final int mySpendCents;
}

DateTime bucketStart(DateTime date, TrendGranularity granularity) {
  final day = DateTime.utc(date.year, date.month, date.day);
  return switch (granularity) {
    TrendGranularity.day => day,
    TrendGranularity.week => day.subtract(Duration(days: day.weekday - DateTime.monday)),
    TrendGranularity.month => DateTime.utc(date.year, date.month),
  };
}

/// Groups the daily series into weekly (ISO, Monday start) or monthly buckets.
List<TrendPoint> aggregateTrend(List<DailyPoint> daily, TrendGranularity granularity) {
  final buckets = <DateTime, List<DailyPoint>>{};
  for (final point in daily) {
    buckets.putIfAbsent(bucketStart(point.date, granularity), () => []).add(point);
  }
  final starts = buckets.keys.toList()..sort();
  return [
    for (final start in starts)
      TrendPoint(
        start: start,
        groupCoffees: buckets[start]!.fold(0, (sum, p) => sum + p.groupCoffees),
        myCoffees: buckets[start]!.fold(0, (sum, p) => sum + p.myCoffees),
        groupSpendCents: buckets[start]!.fold(0, (sum, p) => sum + p.groupSpendCents),
        mySpendCents: buckets[start]!.fold(0, (sum, p) => sum + p.mySpendCents),
      ),
  ];
}

/// A sensible default granularity for a range length.
TrendGranularity granularityFor(int days) {
  if (days <= 45) return TrendGranularity.day;
  if (days <= 200) return TrendGranularity.week;
  return TrendGranularity.month;
}

/// Relative change from [previous] to [current] in percent, or null when there
/// is no previous value to compare with.
int? percentChange(num current, num previous) {
  if (previous == 0) return null;
  return ((current - previous) * 100 / previous).round();
}
