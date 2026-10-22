class StreakSummary {
  const StreakSummary({required this.current, required this.best});

  /// Consecutive working days with coffee, ending today (or yesterday if
  /// today's coffee has not happened yet).
  final int current;
  final int best;
}

DateTime _day(DateTime value) => DateTime.utc(value.year, value.month, value.day);

bool _isWeekend(DateTime day) => day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

/// Computes coffee streaks over calendar dates.
///
/// Rules (kept simple and predictable):
/// * a working day (Mon-Fri) with at least one coffee extends the streak;
/// * a weekend day with coffee extends it too, a weekend day without coffee
///   neither extends nor breaks it;
/// * a working day without coffee breaks the streak, except today, which is
///   not over yet.
StreakSummary computeStreaks(Iterable<DateTime> coffeeDates, DateTime today) {
  final days = coffeeDates.map(_day).toSet();
  final todayDay = _day(today);
  if (days.isEmpty) return const StreakSummary(current: 0, best: 0);

  final sorted = days.toList()..sort();
  final earliest = sorted.first;

  var current = 0;
  for (var day = todayDay; !day.isBefore(earliest); day = day.subtract(const Duration(days: 1))) {
    if (days.contains(day)) {
      current++;
    } else if (!_isWeekend(day) && day != todayDay) {
      break;
    }
  }

  var best = 0;
  var run = 0;
  for (var day = earliest; !day.isAfter(todayDay); day = day.add(const Duration(days: 1))) {
    if (days.contains(day)) {
      run++;
      if (run > best) best = run;
    } else if (!_isWeekend(day)) {
      if (day != todayDay) run = 0;
    }
  }
  return StreakSummary(current: current, best: best < current ? current : best);
}
