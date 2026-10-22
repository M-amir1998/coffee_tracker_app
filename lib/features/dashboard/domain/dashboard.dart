import 'package:coffee_tracker/core/utils/json.dart';
import 'package:coffee_tracker/features/accounting/domain/balance_models.dart';
import 'package:coffee_tracker/features/accounting/domain/ledger_models.dart';
import 'package:coffee_tracker/features/groups/domain/group_models.dart';

/// Everything the home screen needs, loaded in a single request.
class Dashboard {
  const Dashboard({
    required this.group,
    required this.userId,
    required this.displayName,
    required this.role,
    required this.cycle,
    required this.priceCents,
    required this.balance,
    required this.todayCoffees,
    required this.allTimeCoffees,
    required this.allTimeNetCents,
    required this.toReviewCount,
    required this.mySubmissionsCount,
    required this.unreadNotifications,
    required this.recent,
    this.joinedAt,
    this.nextPrice,
  });

  factory Dashboard.fromJson(Json json) {
    final me = json.obj('me');
    final allTime = json.obj('all_time');
    final pending = json.obj('pending');
    final next = json.objOrNull('next_price');
    return Dashboard(
      group: GroupSettings.fromJson(json.obj('group')),
      userId: me.str('user_id'),
      displayName: me.str('display_name'),
      role: MemberRole.parse(me.str('role')),
      joinedAt: me.dateOrNull('joined_at'),
      cycle: CycleInfo.fromJson(json.obj('cycle')),
      priceCents: json.intOr('price_cents'),
      nextPrice: next == null ? null : (priceCents: next.integer('price_cents'), from: next.date('effective_from')),
      balance: BalanceBreakdown.fromJson(json.obj('balance')),
      todayCoffees: json.intOr('today_coffees'),
      allTimeCoffees: allTime.intOr('coffees'),
      allTimeNetCents: allTime.intOr('net_cents'),
      toReviewCount: pending.intOr('to_review'),
      mySubmissionsCount: pending.intOr('my_submissions'),
      unreadNotifications: json.intOr('unread_notifications'),
      recent: json.list('recent').map(ActivityItem.fromJson).toList(),
    );
  }

  final GroupSettings group;
  final String userId;
  final String displayName;
  final MemberRole role;
  final DateTime? joinedAt;
  final CycleInfo cycle;
  final int priceCents;
  final ({int priceCents, DateTime from})? nextPrice;

  /// Current-cycle figures of the signed-in member.
  final BalanceBreakdown balance;
  final int todayCoffees;
  final int allTimeCoffees;
  final int allTimeNetCents;
  final int toReviewCount;
  final int mySubmissionsCount;
  final int unreadNotifications;
  final List<ActivityItem> recent;
}
