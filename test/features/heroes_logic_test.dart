import 'package:coffee_tracker/features/achievements/domain/achievements.dart';
import 'package:coffee_tracker/features/leaderboard/domain/leaderboard_models.dart';
import 'package:coffee_tracker/features/leaderboard/domain/ranking.dart';
import 'package:coffee_tracker/features/leaderboard/domain/streaks.dart';
import 'package:flutter_test/flutter_test.dart';

LeaderboardEntry e(String name, int coffees) => LeaderboardEntry(userId: name, displayName: name, coffees: coffees);

MyStats stats({
  int total = 0,
  int days = 0,
  int early = 0,
  int late = 0,
  int beans = 0,
  int personal = 0,
  int settlements = 0,
  int balance = 0,
  DateTime? joined,
}) => MyStats(
  totalCoffees: total,
  cycleCoffees: total,
  distinctDays: days,
  earlyBirdCoffees: early,
  nightOwlCoffees: late,
  coffeeDates: const [],
  weekCoffees: 0,
  monthCoffees: 0,
  groupWeekCoffees: 0,
  groupMonthCoffees: 0,
  beanPurchases: beans,
  personalPurchases: personal,
  personalPurchaseCents: 0,
  settlements: settlements,
  balanceCents: balance,
  joinedAt: joined,
);

void main() {
  group('ranking', () {
    test('uses competition ranking for ties', () {
      final ranked = rankEntries([e('Bob', 10), e('Alice', 12), e('Cara', 10), e('Dan', 4)]);
      expect(ranked.map((r) => (r.entry.displayName, r.rank)), [('Alice', 1), ('Bob', 2), ('Cara', 2), ('Dan', 4)]);
      expect(ranked[1].tied, isTrue);
      expect(ranked[0].tied, isFalse);
    });

    test('assigns medals by rank and keeps ties on the podium', () {
      final ranked = rankEntries([e('A', 5), e('B', 5), e('C', 3), e('D', 1)]);
      expect(podium(ranked).map((r) => r.entry.displayName), ['A', 'B', 'C']);
      expect(ranked[0].medal, Medal.gold);
      expect(ranked[1].medal, Medal.gold);
      expect(ranked[2].medal, Medal.bronze);
      expect(ranked[3].medal, isNull);
    });

    test('ignores members without coffees', () {
      expect(rankEntries([e('A', 0), e('B', 2)]).map((r) => r.entry.displayName), ['B']);
    });

    test('share of consumption', () {
      expect(sharePercent(2, 25), 8);
      expect(sharePercent(0, 0), 0);
      expect(sharePercent(1, 3), 33);
    });

    test('message choice is stable and stays in range', () {
      final first = stableMessageIndex(count: 4, seed: 'month-2026-10-alice');
      expect(stableMessageIndex(count: 4, seed: 'month-2026-10-alice'), first);
      for (final seed in ['a', 'b', 'week-1', 'cycle-xyz']) {
        expect(stableMessageIndex(count: 4, seed: seed), inInclusiveRange(0, 3));
      }
      expect(stableMessageIndex(count: 1, seed: 'x'), 0);
    });
  });

  group('streaks', () {
    // 2026-10-19 is a Monday.
    DateTime d(int day) => DateTime(2026, 10, day);

    test('consecutive working days count, weekends do not break the streak', () {
      final dates = [d(14), d(15), d(16), d(19), d(20)]; // Wed-Fri, weekend off, Mon-Tue
      expect(computeStreaks(dates, d(20)).current, 5);
    });

    test('today without coffee does not break the streak yet', () {
      expect(computeStreaks([d(19), d(20)], d(21)).current, 2);
    });

    test('a missed working day breaks it', () {
      final result = computeStreaks([d(13), d(14), d(16), d(19)], d(19));
      expect(result.current, 2);
      expect(result.best, 2);
    });

    test('weekend coffees extend the streak', () {
      expect(computeStreaks([d(16), d(17), d(18), d(19)], d(19)).current, 4);
    });

    test('best streak is remembered', () {
      final result = computeStreaks([d(5), d(6), d(7), d(8), d(9), d(19)], d(20));
      expect(result.best, 5);
      expect(result.current, 1);
    });

    test('no coffee, no streak', () {
      expect(computeStreaks(const [], d(20)).current, 0);
    });
  });

  group('achievements', () {
    final now = DateTime(2026, 10, 22);

    AchievementProgress find(List<AchievementProgress> list, AchievementId id) => list.firstWhere((a) => a.id == id);

    test('nothing is unlocked for a new member', () {
      final list = evaluateAchievements(stats(joined: now), now);
      expect(list.where((a) => a.unlocked), isEmpty);
      expect(list, hasLength(AchievementId.values.length));
    });

    test('coffee-based achievements follow their thresholds', () {
      final list = evaluateAchievements(stats(total: 10, days: 7, early: 1, late: 2), now);
      expect(find(list, AchievementId.firstSip).unlocked, isTrue);
      expect(find(list, AchievementId.coffeeMarathon).unlocked, isTrue);
      expect(find(list, AchievementId.consistencyChampion).unlocked, isTrue);
      expect(find(list, AchievementId.earlyBird).unlocked, isTrue);
      expect(find(list, AchievementId.nightOwl).unlocked, isTrue);
    });

    test('progress is reported below the threshold', () {
      final marathon = find(evaluateAchievements(stats(total: 6), now), AchievementId.coffeeMarathon);
      expect(marathon.unlocked, isFalse);
      expect(marathon.current, 6);
      expect(marathon.target, AchievementRules.marathonCoffees);
      expect(marathon.fraction, closeTo(0.6, 1e-9));
    });

    test('purchases unlock the bean achievements', () {
      final list = evaluateAchievements(stats(beans: 1, personal: 0), now);
      expect(find(list, AchievementId.beanGuardian).unlocked, isTrue);
      expect(find(list, AchievementId.generousContributor).unlocked, isFalse);
      expect(
        find(evaluateAchievements(stats(beans: 1, personal: 1), now), AchievementId.generousContributor).unlocked,
        isTrue,
      );
    });

    test('perfectly balanced needs a settled balance after real activity', () {
      expect(
        find(evaluateAchievements(stats(total: 3, settlements: 1), now), AchievementId.perfectlyBalanced).unlocked,
        isTrue,
      );
      expect(
        find(evaluateAchievements(stats(total: 3, settlements: 0), now), AchievementId.perfectlyBalanced).unlocked,
        isFalse,
      );
      expect(
        find(
          evaluateAchievements(stats(total: 3, settlements: 2, balance: 20), now),
          AchievementId.perfectlyBalanced,
        ).unlocked,
        isFalse,
      );
      expect(find(evaluateAchievements(stats(settlements: 1), now), AchievementId.perfectlyBalanced).unlocked, isFalse);
    });

    test('veteran counts membership days', () {
      const veteran = AchievementId.coffeeVeteran;
      expect(
        find(evaluateAchievements(stats(joined: now.subtract(const Duration(days: 179))), now), veteran).unlocked,
        isFalse,
      );
      expect(
        find(evaluateAchievements(stats(joined: now.subtract(const Duration(days: 180))), now), veteran).unlocked,
        isTrue,
      );
    });
  });
}
