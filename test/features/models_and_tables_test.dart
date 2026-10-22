import 'package:coffee_tracker/core/money/money.dart';
import 'package:coffee_tracker/features/accounting/domain/balance_models.dart';
import 'package:coffee_tracker/features/accounting/domain/ledger_models.dart';
import 'package:coffee_tracker/features/admin/domain/csv_exports.dart';
import 'package:coffee_tracker/features/analytics/domain/analytics_models.dart';
import 'package:coffee_tracker/features/analytics/domain/trends.dart';
import 'package:coffee_tracker/features/dashboard/domain/dashboard.dart';
import 'package:coffee_tracker/features/group_overview/presentation/balances_table.dart';
import 'package:coffee_tracker/features/groups/domain/group_models.dart';
import 'package:flutter_test/flutter_test.dart';

MemberBalance row(String name, {int coffees = 0, int net = 0, int consumption = 0, int deposits = 0}) => MemberBalance(
  userId: name.toLowerCase(),
  displayName: name,
  role: MemberRole.member,
  membershipStatus: MembershipStatus.active,
  isMe: false,
  breakdown: BalanceBreakdown(coffees: coffees, netCents: net, consumptionCents: consumption, depositsCents: deposits),
);

void main() {
  group('BalanceBreakdown', () {
    test('parses the server shape and checks the documented equation', () {
      final b = BalanceBreakdown.fromJson({
        'opening_cents': 100,
        'coffees': 30,
        'consumption_cents': 600,
        'deposits_cents': 500,
        'personal_purchases_cents': 1500,
        'transfers_sent_cents': 200,
        'transfers_received_cents': 300,
        'reimbursements_cents': 400,
        'adjustments_cents': -50,
        'net_cents': -850,
      });
      // 100 + 600 - 500 - 1500 - 200 + 300 + 400 - 50 = -850
      expect(b.isConsistent, isTrue);
      expect(b.contributionsCents, 2000);
      expect(b.status, BalanceStatus.owed);
    });

    test('detects inconsistent figures', () {
      expect(const BalanceBreakdown(consumptionCents: 100, netCents: 90).isConsistent, isFalse);
    });
  });

  test('cash summary equation', () {
    const ok = CashSummary(
      openingCashCents: 200,
      depositsCents: 900,
      boxPurchasesCents: 300,
      reimbursementsCents: 500,
      cashAdjustmentsCents: -10,
      closingCashCents: 290,
    );
    expect(ok.isConsistent, isTrue);
  });

  test('dashboard parses the RPC payload', () {
    final dashboard = Dashboard.fromJson({
      'group': {
        'id': 'g1',
        'name': 'Lab',
        'currency': 'EUR',
        'timezone': 'Europe/Madrid',
        'require_deposit_confirmation': true,
        'require_purchase_approval': false,
        'member_undo_window_minutes': 15,
      },
      'me': {'user_id': 'u1', 'display_name': 'Alice', 'role': 'treasurer', 'joined_at': '2026-09-01T08:00:00Z'},
      'cycle': {
        'id': 'c1',
        'sequence_no': 2,
        'name': 'October 2026',
        'status': 'open',
        'opened_at': '2026-10-01T06:00:00Z',
      },
      'price_cents': 20,
      'next_price': {'price_cents': 25, 'effective_from': '2026-11-01T00:00:00Z'},
      'balance': {'coffees': 21, 'consumption_cents': 420, 'net_cents': 420},
      'today_coffees': 2,
      'all_time': {'coffees': 80, 'net_cents': 420},
      'pending': {'to_review': 3, 'my_submissions': 1},
      'unread_notifications': 4,
      'recent': [
        {
          'item_type': 'transaction',
          'id': 't1',
          'kind': 'deposit',
          'status': 'pending',
          'amount_cents': 500,
          'member_name': 'Alice',
          'occurred_at': '2026-10-20T08:00:00Z',
          'created_at': '2026-10-20T08:00:00Z',
        },
      ],
    });
    expect(dashboard.role, MemberRole.treasurer);
    expect(dashboard.balance.status, BalanceStatus.owes);
    expect(dashboard.nextPrice?.priceCents, 25);
    expect(dashboard.recent.single.status, TransactionStatus.pending);
    expect(dashboard.recent.single.kind, TransactionKind.deposit);
    expect(dashboard.toReviewCount, 3);
  });

  group('balances table', () {
    final rows = [
      row('Charlie', coffees: 30, net: 0, consumption: 600, deposits: 600),
      row('alice', coffees: 45, net: 400, consumption: 900, deposits: 500),
      row('Bob', coffees: 60, net: -800, consumption: 1200, deposits: 2000),
    ];

    test('sorts by name case-insensitively by default', () {
      expect(filterAndSortBalances(rows).map((r) => r.displayName), ['alice', 'Bob', 'Charlie']);
    });

    test('sorts by numbers in both directions', () {
      expect(filterAndSortBalances(rows, sort: BalanceSort.net).map((r) => r.displayName), ['Bob', 'Charlie', 'alice']);
      expect(filterAndSortBalances(rows, sort: BalanceSort.coffees, ascending: false).map((r) => r.displayName), [
        'Bob',
        'alice',
        'Charlie',
      ]);
    });

    test('filters by status and search text', () {
      expect(filterAndSortBalances(rows, status: BalanceStatus.owed).single.displayName, 'Bob');
      expect(filterAndSortBalances(rows, status: BalanceStatus.settled).single.displayName, 'Charlie');
      expect(filterAndSortBalances(rows, query: 'AL').single.displayName, 'alice');
    });
  });

  test('balances CSV contains one row per member with plain decimals', () {
    final csv = balancesCsv(
      [row('Bob', coffees: 60, net: -800, consumption: 1200, deposits: 2000)],
      currency: 'EUR',
      scope: 'cycle',
    );
    final lines = csv.split('\r\n');
    expect(lines.first, startsWith('﻿member,membership,role,scope,currency,opening,coffees,consumption'));
    expect(lines[1], 'Bob,active,member,cycle,EUR,0.00,60,12.00,20.00,0.00,0.00,0.00,0.00,0.00,-8.00,owed');
  });

  group('trends', () {
    final daily = [
      for (var i = 0; i < 14; i++)
        DailyPoint(
          date: DateTime.utc(2026, 10, 12 + i), // starts on a Monday
          groupCoffees: i + 1,
          myCoffees: i.isEven ? 1 : 0,
          groupSpendCents: (i + 1) * 20,
          mySpendCents: i.isEven ? 20 : 0,
        ),
    ];

    test('weekly buckets start on Monday and keep the totals', () {
      final weeks = aggregateTrend(daily, TrendGranularity.week);
      expect(weeks.map((w) => w.start), [DateTime.utc(2026, 10, 12), DateTime.utc(2026, 10, 19)]);
      expect(weeks.map((w) => w.groupCoffees), [28, 77]);
      expect(weeks.fold<int>(0, (sum, w) => sum + w.groupSpendCents), 105 * 20);
    });

    test('monthly buckets', () {
      final months = aggregateTrend(daily, TrendGranularity.month);
      expect(months.single.start, DateTime.utc(2026, 10));
      expect(months.single.myCoffees, 7);
    });

    test('granularity follows the range length and percent change is safe', () {
      expect(granularityFor(30), TrendGranularity.day);
      expect(granularityFor(90), TrendGranularity.week);
      expect(granularityFor(365), TrendGranularity.month);
      expect(percentChange(120, 100), 20);
      expect(percentChange(5, 0), isNull);
    });
  });

  test('invitation validity', () {
    final now = DateTime(2026, 10, 22);
    final base = Invitation(
      id: 'i',
      code: 'ABCDEFGH',
      role: MemberRole.member,
      useCount: 2,
      createdAt: now,
      maxUses: 3,
    );
    expect(base.isActiveAt(now), isTrue);
    expect(base.displayCode, 'ABCD-EFGH');
    expect(
      Invitation(
        id: 'i',
        code: 'ABCDEFGH',
        role: MemberRole.member,
        useCount: 3,
        createdAt: now,
        maxUses: 3,
      ).isActiveAt(now),
      isFalse,
    );
    expect(
      Invitation(
        id: 'i',
        code: 'X',
        role: MemberRole.member,
        useCount: 0,
        createdAt: now,
        expiresAt: now,
      ).isActiveAt(now),
      isFalse,
    );
  });
}
