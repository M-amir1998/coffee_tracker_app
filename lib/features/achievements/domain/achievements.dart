import 'package:coffee_tracker/features/leaderboard/domain/leaderboard_models.dart';

enum AchievementId {
  firstSip,
  earlyBird,
  nightOwl,
  coffeeMarathon,
  consistencyChampion,
  beanGuardian,
  generousContributor,
  perfectlyBalanced,
  coffeeVeteran,
}

class AchievementProgress {
  const AchievementProgress({required this.id, required this.current, required this.target});

  final AchievementId id;
  final int current;
  final int target;

  bool get unlocked => current >= target;

  /// 0.0 - 1.0, for progress indicators.
  double get fraction => target == 0 ? 1 : (current / target).clamp(0, 1).toDouble();
}

/// Thresholds of the achievements. Kept here so rules and UI agree.
abstract final class AchievementRules {
  static const marathonCoffees = 10;
  static const consistencyDays = 7;
  static const veteranDays = 180;

  /// Local hours that count as "early" (04:00-07:59) and "late" (20:00-03:59)
  /// are evaluated by the server when it counts the coffees.
  static const earlyBirdUntilHour = 8;
  static const nightOwlFromHour = 20;
}

/// Evaluates every achievement from the member's statistics. Achievements are
/// derived, not stored: the same facts always give the same result.
List<AchievementProgress> evaluateAchievements(MyStats stats, DateTime now) {
  final memberDays = stats.joinedAt == null ? 0 : now.difference(stats.joinedAt!).inDays.clamp(0, 1 << 30);
  final balanced = stats.balanceCents == 0 && stats.settlements > 0 && stats.totalCoffees > 0;

  return [
    AchievementProgress(id: AchievementId.firstSip, current: stats.totalCoffees.clamp(0, 1), target: 1),
    AchievementProgress(id: AchievementId.earlyBird, current: stats.earlyBirdCoffees.clamp(0, 1), target: 1),
    AchievementProgress(id: AchievementId.nightOwl, current: stats.nightOwlCoffees.clamp(0, 1), target: 1),
    AchievementProgress(
      id: AchievementId.coffeeMarathon,
      current: stats.totalCoffees.clamp(0, AchievementRules.marathonCoffees),
      target: AchievementRules.marathonCoffees,
    ),
    AchievementProgress(
      id: AchievementId.consistencyChampion,
      current: stats.distinctDays.clamp(0, AchievementRules.consistencyDays),
      target: AchievementRules.consistencyDays,
    ),
    AchievementProgress(id: AchievementId.beanGuardian, current: stats.beanPurchases.clamp(0, 1), target: 1),
    AchievementProgress(id: AchievementId.generousContributor, current: stats.personalPurchases.clamp(0, 1), target: 1),
    AchievementProgress(id: AchievementId.perfectlyBalanced, current: balanced ? 1 : 0, target: 1),
    AchievementProgress(
      id: AchievementId.coffeeVeteran,
      current: memberDays.clamp(0, AchievementRules.veteranDays),
      target: AchievementRules.veteranDays,
    ),
  ];
}
