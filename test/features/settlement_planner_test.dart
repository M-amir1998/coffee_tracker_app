import 'dart:math';

import 'package:coffee_tracker/features/settlements/domain/settlement_planner.dart';
import 'package:flutter_test/flutter_test.dart';

SettlementMember m(String name, int net, {bool active = true, int out = 0, int inbound = 0, int reimb = 0}) =>
    SettlementMember(
      userId: name.toLowerCase(),
      displayName: name,
      netCents: net,
      active: active,
      pendingOutCents: out,
      pendingInCents: inbound,
      pendingReimbursementCents: reimb,
    );

SettlementInputs inputs(List<SettlementMember> members, {int cash = 0, int pendingOut = 0}) =>
    SettlementInputs(cashBoxCents: cash, pendingBoxOutflowCents: pendingOut, members: members);

/// Applies the suggestions and returns the resulting balances and cash.
(Map<String, int>, int) apply(SettlementInputs input, SettlementPlan plan) {
  final balances = {for (final member in input.members.where((x) => x.active)) member.userId: member.projectedCents};
  var cash = input.cashBoxCents - input.pendingBoxOutflowCents;
  for (final s in plan.suggestions) {
    switch (s.type) {
      case SuggestionType.reimbursement:
        balances[s.toUserId!] = balances[s.toUserId!]! + s.amountCents;
        cash -= s.amountCents;
      case SuggestionType.transfer:
        balances[s.fromUserId!] = balances[s.fromUserId!]! - s.amountCents;
        balances[s.toUserId!] = balances[s.toUserId!]! + s.amountCents;
      case SuggestionType.deposit:
        balances[s.fromUserId!] = balances[s.fromUserId!]! - s.amountCents;
        cash += s.amountCents;
    }
  }
  return (balances, cash);
}

void main() {
  test('example from the requirements: two debtors pay the creditor directly', () {
    final plan = planSettlements(inputs([m('Alice', -1200), m('Bob', 700), m('Charlie', 500)]));
    expect(plan.suggestions, hasLength(2));
    expect(plan.suggestions.map((s) => (s.type, s.fromName, s.toName, s.amountCents)), [
      (SuggestionType.transfer, 'Bob', 'Alice', 700),
      (SuggestionType.transfer, 'Charlie', 'Alice', 500),
    ]);
    expect(plan.unsettledCredits, isEmpty);
  });

  test('confirmed box cash reimburses creditors first', () {
    final plan = planSettlements(inputs([m('Alice', -1200), m('Bob', 700), m('Charlie', 500)], cash: 1000));
    expect(plan.suggestions.first.type, SuggestionType.reimbursement);
    expect(plan.suggestions.first.toName, 'Alice');
    expect(plan.suggestions.first.amountCents, 1000);
    // Alice is still owed 2.00; Bob pays it, the rest goes into the box.
    expect(plan.suggestions[1].type, SuggestionType.transfer);
    expect(plan.suggestions[1].amountCents, 200);
    final deposits = plan.suggestions.where((s) => s.type == SuggestionType.deposit).toList();
    expect(deposits.map((s) => (s.fromName, s.amountCents)), [('Bob', 500), ('Charlie', 500)]);
  });

  test('never spends more than the box holds, pending payouts and the reserve', () {
    final plan = planSettlements(
      inputs([m('Alice', -2000), m('Bob', 300)], cash: 1500, pendingOut: 400),
      reserveCents: 600,
    );
    expect(plan.availableCashCents, 500);
    expect(plan.reimbursedFromBoxCents, 500);
  });

  test('cash box can be ignored', () {
    final plan = planSettlements(inputs([m('Alice', -500), m('Bob', 500)], cash: 5000), useCashBox: false);
    expect(plan.suggestions.single.type, SuggestionType.transfer);
  });

  test('pending payments are not suggested twice', () {
    // Bob already sent Alice 7.00 (pending); only the remaining 5.00 is planned.
    final plan = planSettlements(inputs([m('Alice', -1200, inbound: 700), m('Bob', 700, out: 700), m('Charlie', 500)]));
    expect(plan.suggestions.map((s) => (s.fromName, s.amountCents)), [('Charlie', 500)]);
    expect(plan.consideredPendingItems, isTrue);
  });

  test('pending reimbursement requests reduce what is still owed', () {
    final plan = planSettlements(inputs([m('Alice', -1000, reimb: 1000)], cash: 5000));
    expect(plan.isSettled, isTrue);
  });

  test('credits the group cannot cover yet are reported, not invented', () {
    final plan = planSettlements(inputs([m('Alice', -1500), m('Bob', 200)], cash: 300));
    expect(plan.unsettledCredits.single.amountCents, 1000);
    expect(plan.suggestions.every((s) => s.amountCents > 0), isTrue);
  });

  test('former members are excluded and listed separately', () {
    final plan = planSettlements(inputs([m('Alice', -300), m('Dora', 300, active: false)]));
    expect(plan.suggestions, isEmpty);
    expect(plan.inactiveWithBalance.single.displayName, 'Dora');
    expect(plan.unsettledCredits.single.amountCents, 300);
  });

  test('everyone settled gives an empty plan', () {
    expect(planSettlements(inputs([m('Alice', 0), m('Bob', 0)], cash: 900)).isSettled, isTrue);
  });

  test('properties hold for random groups', () {
    final random = Random(42);
    for (var round = 0; round < 500; round++) {
      final members = [
        for (var i = 0; i < 2 + random.nextInt(10); i++)
          SettlementMember(
            userId: 'u$i',
            displayName: 'Member ${String.fromCharCode(65 + i)}',
            netCents: random.nextInt(4001) - 2000,
            pendingOutCents: random.nextInt(6) == 0 ? random.nextInt(300) : 0,
            pendingInCents: random.nextInt(6) == 0 ? random.nextInt(300) : 0,
          ),
      ];
      final input = inputs(members, cash: random.nextInt(3000), pendingOut: random.nextInt(500));
      final reserve = random.nextInt(400);
      final plan = planSettlements(input, reserveCents: reserve);

      for (final s in plan.suggestions) {
        expect(s.amountCents, greaterThan(0));
        expect(s.fromUserId == null || s.fromUserId != s.toUserId, isTrue, reason: 'no self payments');
      }
      final spendable = max(0, input.cashBoxCents - input.pendingBoxOutflowCents - reserve);
      expect(plan.reimbursedFromBoxCents, lessThanOrEqualTo(spendable));

      final projected = {for (final x in members) x.userId: x.projectedCents};
      final paid = <String, int>{};
      final received = <String, int>{};
      for (final s in plan.suggestions) {
        if (s.fromUserId != null) paid.update(s.fromUserId!, (v) => v + s.amountCents, ifAbsent: () => s.amountCents);
        if (s.toUserId != null) received.update(s.toUserId!, (v) => v + s.amountCents, ifAbsent: () => s.amountCents);
      }
      for (final x in members) {
        expect(
          paid[x.userId] ?? 0,
          lessThanOrEqualTo(max(0, projected[x.userId]!)),
          reason: 'nobody pays more than owed',
        );
        expect(
          received[x.userId] ?? 0,
          lessThanOrEqualTo(max(0, -projected[x.userId]!)),
          reason: 'nobody receives more',
        );
      }

      final (after, cashAfter) = apply(input, plan);
      for (final entry in after.entries) {
        expect(entry.value, lessThanOrEqualTo(0), reason: 'all debts are covered');
      }
      final unsettled = plan.unsettledCredits.fold<int>(0, (sum, c) => sum + c.amountCents);
      expect(after.values.where((v) => v < 0).fold<int>(0, (sum, v) => sum - v), unsettled);
      // Reimbursements never push the box below what it holds net of pending payouts.
      expect(cashAfter, greaterThanOrEqualTo(min(0, input.cashBoxCents - input.pendingBoxOutflowCents)));

      // Deterministic, independent of the input order.
      final shuffled = planSettlements(
        inputs([...members]..shuffle(random), cash: input.cashBoxCents, pendingOut: input.pendingBoxOutflowCents),
        reserveCents: reserve,
      );
      expect(
        shuffled.suggestions.map((s) => '${s.type}:${s.fromUserId}:${s.toUserId}:${s.amountCents}').toList(),
        plan.suggestions.map((s) => '${s.type}:${s.fromUserId}:${s.toUserId}:${s.amountCents}').toList(),
      );
    }
  });
}
