import 'package:coffee_tracker/features/leaderboard/domain/leaderboard_models.dart';

enum Medal { gold, silver, bronze }

class RankedEntry {
  const RankedEntry({required this.rank, required this.entry, required this.tied});

  /// Standard competition ranking: equal counts share a rank ("1, 1, 3").
  final int rank;
  final LeaderboardEntry entry;

  /// Whether another entry has the same rank.
  final bool tied;

  Medal? get medal => switch (rank) {
    1 => Medal.gold,
    2 => Medal.silver,
    3 => Medal.bronze,
    _ => null,
  };
}

/// Ranks entries by coffees (descending), breaking display ties by name.
/// Entries without coffees are not ranked.
List<RankedEntry> rankEntries(Iterable<LeaderboardEntry> entries) {
  final sorted = entries.where((e) => e.coffees > 0).toList()
    ..sort((a, b) {
      final byCoffees = b.coffees.compareTo(a.coffees);
      if (byCoffees != 0) return byCoffees;
      final byName = a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      return byName != 0 ? byName : a.userId.compareTo(b.userId);
    });

  final counts = <int, int>{};
  for (final entry in sorted) {
    counts.update(entry.coffees, (n) => n + 1, ifAbsent: () => 1);
  }

  final ranked = <RankedEntry>[];
  for (var i = 0; i < sorted.length; i++) {
    final entry = sorted[i];
    final rank = i > 0 && sorted[i - 1].coffees == entry.coffees ? ranked[i - 1].rank : i + 1;
    ranked.add(RankedEntry(rank: rank, entry: entry, tied: counts[entry.coffees]! > 1));
  }
  return ranked;
}

/// Entries that stand on the podium (ranks 1-3, ties included).
List<RankedEntry> podium(List<RankedEntry> ranked) => ranked.where((r) => r.rank <= 3).toList();

/// Whole-percent share of [part] in [total]; 0 when nothing was consumed.
int sharePercent(int part, int total) => total <= 0 ? 0 : (part * 100 / total).round();

/// Picks one of [count] messages so it stays stable while the period and
/// person are the same, and rotates when either changes.
int stableMessageIndex({required int count, required String seed}) {
  if (count <= 1) return 0;
  var hash = 0x811C9DC5;
  for (final unit in seed.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  return hash % count;
}
