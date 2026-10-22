import 'package:coffee_tracker/core/utils/json.dart';
import 'package:coffee_tracker/features/accounting/domain/balance_models.dart';

class DailyPoint {
  const DailyPoint({
    required this.date,
    required this.groupCoffees,
    required this.myCoffees,
    required this.groupSpendCents,
    required this.mySpendCents,
  });

  factory DailyPoint.fromJson(Json json) => DailyPoint(
    date: DateTime.parse(json.str('date')),
    groupCoffees: json.intOr('group_coffees'),
    myCoffees: json.intOr('my_coffees'),
    groupSpendCents: json.intOr('group_spend_cents'),
    mySpendCents: json.intOr('my_spend_cents'),
  );

  final DateTime date;
  final int groupCoffees;
  final int myCoffees;
  final int groupSpendCents;
  final int mySpendCents;
}

class BucketPoint {
  const BucketPoint({required this.bucket, required this.groupCoffees, required this.myCoffees});

  final int bucket;
  final int groupCoffees;
  final int myCoffees;
}

class CashPoint {
  const CashPoint({required this.date, required this.balanceCents});

  final DateTime date;
  final int balanceCents;
}

class PurchasePoint {
  const PurchasePoint({
    required this.id,
    required this.date,
    required this.amountCents,
    required this.fromCashBox,
    this.memberName,
    this.description,
  });

  final String id;
  final DateTime date;
  final int amountCents;
  final bool fromCashBox;
  final String? memberName;
  final String? description;
}

class ParticipationEntry {
  const ParticipationEntry({required this.coffees, required this.isMe, this.userId, this.displayName});

  /// Null when the member hides themselves from Coffee Heroes.
  final String? userId;
  final String? displayName;
  final int coffees;
  final bool isMe;
}

class CycleFigures {
  const CycleFigures({
    required this.cycle,
    required this.coffees,
    required this.consumptionCents,
    required this.depositsCents,
    required this.personalPurchasesCents,
    required this.consumers,
    required this.days,
  });

  factory CycleFigures.fromJson(Json json) => CycleFigures(
    cycle: CycleInfo.fromJson(json.obj('cycle')),
    coffees: json.intOr('coffees'),
    consumptionCents: json.intOr('consumption_cents'),
    depositsCents: json.intOr('deposits_cents'),
    personalPurchasesCents: json.intOr('personal_purchases_cents'),
    consumers: json.intOr('consumers'),
    days: json.intOr('days', 1),
  );

  final CycleInfo cycle;
  final int coffees;
  final int consumptionCents;
  final int depositsCents;
  final int personalPurchasesCents;
  final int consumers;
  final int days;

  double get coffeesPerDay => days == 0 ? 0 : coffees / days;
}

class AnalyticsData {
  const AnalyticsData({
    required this.from,
    required this.to,
    required this.groupCoffees,
    required this.myCoffees,
    required this.groupSpendCents,
    required this.mySpendCents,
    required this.daily,
    required this.weekday,
    required this.hourly,
    required this.cashBox,
    required this.purchases,
    required this.activeMembers,
    required this.consumingMembers,
    required this.participation,
    required this.currentCycle,
    this.previousCycle,
  });

  factory AnalyticsData.fromJson(Json json) {
    final totals = json.obj('totals');
    final participation = json.obj('participation');
    final comparison = json.obj('cycle_comparison');
    return AnalyticsData(
      from: DateTime.parse(json.str('from')),
      to: DateTime.parse(json.str('to')),
      groupCoffees: totals.intOr('group_coffees'),
      myCoffees: totals.intOr('my_coffees'),
      groupSpendCents: totals.intOr('group_spend_cents'),
      mySpendCents: totals.intOr('my_spend_cents'),
      daily: json.list('daily').map(DailyPoint.fromJson).toList(),
      weekday: json
          .list('weekday')
          .map((e) => BucketPoint(bucket: e.integer('weekday'), groupCoffees: e.intOr('group_coffees'), myCoffees: e.intOr('my_coffees')))
          .toList(),
      hourly: json
          .list('hourly')
          .map((e) => BucketPoint(bucket: e.integer('hour'), groupCoffees: e.intOr('group_coffees'), myCoffees: e.intOr('my_coffees')))
          .toList(),
      cashBox: json
          .list('cash_box')
          .map((e) => CashPoint(date: DateTime.parse(e.str('date')), balanceCents: e.intOr('balance_cents')))
          .toList(),
      purchases: json
          .list('purchases')
          .map(
            (e) => PurchasePoint(
              id: e.str('id'),
              date: DateTime.parse(e.str('date')),
              amountCents: e.integer('amount_cents'),
              fromCashBox: e.str('funding') == 'cash_box',
              memberName: e.strOrNull('member_name'),
              description: e.strOrNull('description'),
            ),
          )
          .toList(),
      activeMembers: participation.intOr('active_members'),
      consumingMembers: participation.intOr('consuming_members'),
      participation: participation
          .list('members')
          .map(
            (e) => ParticipationEntry(
              userId: e.strOrNull('user_id'),
              displayName: e.strOrNull('display_name'),
              coffees: e.intOr('coffees'),
              isMe: e.boolOr('is_me'),
            ),
          )
          .toList(),
      currentCycle: CycleFigures.fromJson(comparison.obj('current')),
      previousCycle: comparison['previous'] == null ? null : CycleFigures.fromJson(comparison.obj('previous')),
    );
  }

  final DateTime from;
  final DateTime to;
  final int groupCoffees;
  final int myCoffees;
  final int groupSpendCents;
  final int mySpendCents;
  final List<DailyPoint> daily;
  final List<BucketPoint> weekday;
  final List<BucketPoint> hourly;
  final List<CashPoint> cashBox;
  final List<PurchasePoint> purchases;
  final int activeMembers;
  final int consumingMembers;
  final List<ParticipationEntry> participation;
  final CycleFigures currentCycle;
  final CycleFigures? previousCycle;
}
