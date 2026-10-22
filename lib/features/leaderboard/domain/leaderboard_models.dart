import 'package:coffee_tracker/core/utils/json.dart';

enum LeaderboardPeriod {
  week('week'),
  month('month'),
  cycle('cycle'),
  allTime('all_time');

  const LeaderboardPeriod(this.wireName);

  final String wireName;
}

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.userId,
    required this.displayName,
    required this.coffees,
    this.avatarPath,
    this.isMe = false,
    this.isHidden = false,
  });

  factory LeaderboardEntry.fromJson(Json json) => LeaderboardEntry(
    userId: json.str('user_id'),
    displayName: json.str('display_name'),
    avatarPath: json.strOrNull('avatar_path'),
    coffees: json.intOr('coffees'),
    isMe: json.boolOr('is_me'),
    isHidden: json.boolOr('is_hidden'),
  );

  final String userId;
  final String displayName;
  final String? avatarPath;
  final int coffees;
  final bool isMe;

  /// The member opted out of Coffee Heroes; only they can see this row.
  final bool isHidden;
}

class LeaderboardData {
  const LeaderboardData({required this.period, required this.totalCoffees, required this.entries, this.periodStart});

  factory LeaderboardData.fromJson(Json json) => LeaderboardData(
    period: LeaderboardPeriod.values.firstWhere((p) => p.wireName == json.str('period')),
    periodStart: json.dateOrNull('period_start'),
    totalCoffees: json.intOr('total_coffees'),
    entries: json.list('rows').map(LeaderboardEntry.fromJson).toList(),
  );

  final LeaderboardPeriod period;
  final DateTime? periodStart;

  /// All coffees in the period, including members who hide themselves.
  final int totalCoffees;
  final List<LeaderboardEntry> entries;
}

class AwardWinner {
  const AwardWinner({required this.userId, required this.displayName, required this.coffees, this.avatarPath});

  factory AwardWinner.fromJson(Json json) => AwardWinner(
    userId: json.str('user_id'),
    displayName: json.str('display_name'),
    avatarPath: json.strOrNull('avatar_path'),
    coffees: json.intOr('coffees'),
  );

  final String userId;
  final String displayName;
  final String? avatarPath;
  final int coffees;
}

class MonthlyAward {
  const MonthlyAward({required this.month, required this.winners});

  factory MonthlyAward.fromJson(Json json) => MonthlyAward(
    month: DateTime.parse(json.str('month')),
    winners: json.list('winners').map(AwardWinner.fromJson).toList(),
  );

  /// First day of the awarded month (a calendar date).
  final DateTime month;
  final List<AwardWinner> winners;
}

/// Facts about the signed-in member used by achievements, streaks and fun
/// statistics. All aggregation happens on the server.
class MyStats {
  const MyStats({
    required this.totalCoffees,
    required this.cycleCoffees,
    required this.distinctDays,
    required this.earlyBirdCoffees,
    required this.nightOwlCoffees,
    required this.coffeeDates,
    required this.weekCoffees,
    required this.monthCoffees,
    required this.groupWeekCoffees,
    required this.groupMonthCoffees,
    required this.beanPurchases,
    required this.personalPurchases,
    required this.personalPurchaseCents,
    required this.settlements,
    required this.balanceCents,
    this.favoriteHour,
    this.groupWeekBusiestHour,
    this.groupMonthBusiestWeekday,
    this.joinedAt,
  });

  factory MyStats.fromJson(Json json) => MyStats(
    totalCoffees: json.intOr('total_coffees'),
    cycleCoffees: json.intOr('cycle_coffees'),
    distinctDays: json.intOr('distinct_days'),
    earlyBirdCoffees: json.intOr('early_bird_coffees'),
    nightOwlCoffees: json.intOr('night_owl_coffees'),
    coffeeDates: ((json['coffee_dates'] as List?) ?? const <Object?>[])
        .map((value) => DateTime.parse(value as String))
        .toList(),
    favoriteHour: json.intOrNull('favorite_hour'),
    weekCoffees: json.intOr('week_coffees'),
    monthCoffees: json.intOr('month_coffees'),
    groupWeekCoffees: json.intOr('group_week_coffees'),
    groupMonthCoffees: json.intOr('group_month_coffees'),
    groupWeekBusiestHour: json.intOrNull('group_week_busiest_hour'),
    groupMonthBusiestWeekday: json.intOrNull('group_month_busiest_weekday'),
    beanPurchases: json.intOr('bean_purchases'),
    personalPurchases: json.intOr('personal_purchases'),
    personalPurchaseCents: json.intOr('personal_purchase_cents'),
    settlements: json.intOr('settlements'),
    balanceCents: json.intOr('balance_cents'),
    joinedAt: json.dateOrNull('joined_at'),
  );

  final int totalCoffees;
  final int cycleCoffees;
  final int distinctDays;
  final int earlyBirdCoffees;
  final int nightOwlCoffees;

  /// Distinct local calendar dates with at least one coffee (last 120 days).
  final List<DateTime> coffeeDates;
  final int? favoriteHour;
  final int weekCoffees;
  final int monthCoffees;
  final int groupWeekCoffees;
  final int groupMonthCoffees;
  final int? groupWeekBusiestHour;

  /// ISO weekday (1 = Monday).
  final int? groupMonthBusiestWeekday;
  final int beanPurchases;
  final int personalPurchases;
  final int personalPurchaseCents;
  final int settlements;
  final int balanceCents;
  final DateTime? joinedAt;
}
