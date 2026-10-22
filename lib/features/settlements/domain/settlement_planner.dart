import 'package:coffee_tracker/core/utils/json.dart';

/// Inputs for the settlement assistant, as returned by `get_settlement_inputs`.
class SettlementInputs {
  const SettlementInputs({required this.cashBoxCents, required this.pendingBoxOutflowCents, required this.members});

  factory SettlementInputs.fromJson(Json json) => SettlementInputs(
    cashBoxCents: json.intOr('cash_box_cents'),
    pendingBoxOutflowCents: json.intOr('pending_box_outflow_cents'),
    members: json.list('members').map(SettlementMember.fromJson).toList(),
  );

  /// Confirmed cash in the box.
  final int cashBoxCents;

  /// Box purchases and reimbursements already waiting for approval.
  final int pendingBoxOutflowCents;
  final List<SettlementMember> members;
}

class SettlementMember {
  const SettlementMember({
    required this.userId,
    required this.displayName,
    required this.netCents,
    this.active = true,
    this.pendingOutCents = 0,
    this.pendingInCents = 0,
    this.pendingReimbursementCents = 0,
  });

  factory SettlementMember.fromJson(Json json) => SettlementMember(
    userId: json.str('user_id'),
    displayName: json.str('display_name'),
    active: json.boolOr('active', true),
    netCents: json.intOr('net_cents'),
    pendingOutCents: json.intOr('pending_out_cents'),
    pendingInCents: json.intOr('pending_in_cents'),
    pendingReimbursementCents: json.intOr('pending_reimbursement_cents'),
  );

  final String userId;
  final String displayName;
  final bool active;

  /// Confirmed balance. Positive: owes the group. Negative: is owed.
  final int netCents;

  /// Pending payments this member sent to others (not yet confirmed).
  final int pendingOutCents;

  /// Pending payments other members sent to this member.
  final int pendingInCents;

  /// Pending reimbursements from the box to this member.
  final int pendingReimbursementCents;

  /// The balance once every pending item is confirmed. Suggestions are based
  /// on this value so nothing that is already on its way is suggested twice.
  int get projectedCents => netCents - pendingOutCents + pendingInCents + pendingReimbursementCents;

  bool get hasPendingItems => pendingOutCents != 0 || pendingInCents != 0 || pendingReimbursementCents != 0;
}

enum SuggestionType {
  /// The treasurer pays a member from the cash box.
  reimbursement,

  /// One member pays another member directly.
  transfer,

  /// A member pays into the cash box.
  deposit,
}

class SettlementSuggestion {
  const SettlementSuggestion({
    required this.type,
    required this.amountCents,
    this.fromUserId,
    this.fromName,
    this.toUserId,
    this.toName,
    this.fromOutstandingCents = 0,
    this.toOutstandingCents = 0,
    this.cashBeforeCents = 0,
  });

  final SuggestionType type;
  final int amountCents;

  /// Payer (null for reimbursements, which come from the box).
  final String? fromUserId;
  final String? fromName;

  /// Recipient (null for deposits, which go into the box).
  final String? toUserId;
  final String? toName;

  /// What the payer still owed before this step (for the explanation).
  final int fromOutstandingCents;

  /// What the recipient was still owed before this step.
  final int toOutstandingCents;

  /// Cash available in the box before this step (reimbursements only).
  final int cashBeforeCents;
}

class UnsettledCredit {
  const UnsettledCredit({required this.userId, required this.displayName, required this.amountCents});

  final String userId;
  final String displayName;
  final int amountCents;
}

class SettlementPlan {
  const SettlementPlan({
    required this.suggestions,
    required this.availableCashCents,
    required this.unsettledCredits,
    required this.inactiveWithBalance,
    required this.consideredPendingItems,
  });

  final List<SettlementSuggestion> suggestions;

  /// Confirmed cash the plan was allowed to spend (after pending outflows and
  /// the requested reserve).
  final int availableCashCents;

  /// Credits that cannot be repaid yet because the group has no money for them.
  final List<UnsettledCredit> unsettledCredits;

  /// Former members whose balance is not zero; an administrator has to settle
  /// or adjust these, so they are not part of the suggestions.
  final List<SettlementMember> inactiveWithBalance;

  /// Whether pending items changed the figures used for the plan.
  final bool consideredPendingItems;

  bool get isSettled => suggestions.isEmpty && unsettledCredits.isEmpty;

  int get reimbursedFromBoxCents => suggestions
      .where((s) => s.type == SuggestionType.reimbursement)
      .fold(0, (sum, s) => sum + s.amountCents);
}

class _Position {
  _Position(this.member, this.outstanding);

  final SettlementMember member;
  int outstanding;
}

int _byLargestThenName(_Position a, _Position b) {
  final amount = b.outstanding.compareTo(a.outstanding);
  if (amount != 0) return amount;
  final name = a.member.displayName.toLowerCase().compareTo(b.member.displayName.toLowerCase());
  if (name != 0) return name;
  return a.member.userId.compareTo(b.member.userId);
}

/// Deterministic greedy settlement plan.
///
/// 1. Confirmed box cash (minus pending outflows and [reserveCents]) reimburses
///    the largest credits first.
/// 2. Remaining debts are matched with remaining credits, largest first, as
///    direct payments.
/// 3. Debt left over (the group's surplus, e.g. beans not yet consumed) is
///    paid into the box.
///
/// This keeps the number of payments low but is not guaranteed to be the
/// minimum possible (finding the minimum is NP-hard in general). The plan is
/// only a recommendation: every step still has to happen in real life and be
/// recorded and confirmed through the normal workflows.
SettlementPlan planSettlements(SettlementInputs inputs, {int reserveCents = 0, bool useCashBox = true}) {
  final active = inputs.members.where((m) => m.active).toList();
  final inactive = inputs.members.where((m) => !m.active && m.projectedCents != 0).toList();

  final debtors = <_Position>[];
  final creditors = <_Position>[];
  for (final member in active) {
    final projected = member.projectedCents;
    if (projected > 0) debtors.add(_Position(member, projected));
    if (projected < 0) creditors.add(_Position(member, -projected));
  }
  debtors.sort(_byLargestThenName);
  creditors.sort(_byLargestThenName);

  var cash = 0;
  if (useCashBox) {
    final spendable = inputs.cashBoxCents - inputs.pendingBoxOutflowCents - reserveCents;
    cash = spendable > 0 ? spendable : 0;
  }
  final availableCash = cash;
  final suggestions = <SettlementSuggestion>[];

  // 1. Reimburse from the box.
  for (final creditor in creditors) {
    if (cash == 0) break;
    final amount = creditor.outstanding < cash ? creditor.outstanding : cash;
    if (amount <= 0) continue;
    suggestions.add(
      SettlementSuggestion(
        type: SuggestionType.reimbursement,
        amountCents: amount,
        toUserId: creditor.member.userId,
        toName: creditor.member.displayName,
        toOutstandingCents: creditor.outstanding,
        cashBeforeCents: cash,
      ),
    );
    creditor.outstanding -= amount;
    cash -= amount;
  }

  // 2. Direct payments between members.
  final open = creditors.where((c) => c.outstanding > 0).toList()..sort(_byLargestThenName);
  var c = 0;
  for (final debtor in debtors) {
    while (debtor.outstanding > 0 && c < open.length) {
      final creditor = open[c];
      final amount = debtor.outstanding < creditor.outstanding ? debtor.outstanding : creditor.outstanding;
      suggestions.add(
        SettlementSuggestion(
          type: SuggestionType.transfer,
          amountCents: amount,
          fromUserId: debtor.member.userId,
          fromName: debtor.member.displayName,
          toUserId: creditor.member.userId,
          toName: creditor.member.displayName,
          fromOutstandingCents: debtor.outstanding,
          toOutstandingCents: creditor.outstanding,
        ),
      );
      debtor.outstanding -= amount;
      creditor.outstanding -= amount;
      if (creditor.outstanding == 0) c++;
    }
  }

  // 3. Remaining debt goes into the box.
  for (final debtor in debtors) {
    if (debtor.outstanding <= 0) continue;
    suggestions.add(
      SettlementSuggestion(
        type: SuggestionType.deposit,
        amountCents: debtor.outstanding,
        fromUserId: debtor.member.userId,
        fromName: debtor.member.displayName,
        fromOutstandingCents: debtor.outstanding,
      ),
    );
    debtor.outstanding = 0;
  }

  final unsettled = [
    for (final creditor in open)
      if (creditor.outstanding > 0)
        UnsettledCredit(
          userId: creditor.member.userId,
          displayName: creditor.member.displayName,
          amountCents: creditor.outstanding,
        ),
  ];

  return SettlementPlan(
    suggestions: suggestions,
    availableCashCents: availableCash,
    unsettledCredits: unsettled,
    inactiveWithBalance: inactive,
    consideredPendingItems: active.any((m) => m.hasPendingItems) || inputs.pendingBoxOutflowCents > 0,
  );
}
