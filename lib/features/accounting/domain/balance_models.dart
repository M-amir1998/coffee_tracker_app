import 'package:coffee_tracker/core/money/money.dart';
import 'package:coffee_tracker/core/utils/json.dart';
import 'package:coffee_tracker/features/groups/domain/group_models.dart';

/// A member's figures for a scope (one cycle or all time), in the units of the
/// documented equation:
///
///   net = opening + consumption - deposits - personal purchases
///         - transfers sent + transfers received + reimbursements + adjustments
///
/// Positive net: the member owes the group. Negative: the group owes them.
class BalanceBreakdown {
  const BalanceBreakdown({
    this.openingCents = 0,
    this.coffees = 0,
    this.consumptionCents = 0,
    this.depositsCents = 0,
    this.personalPurchasesCents = 0,
    this.transfersSentCents = 0,
    this.transfersReceivedCents = 0,
    this.reimbursementsCents = 0,
    this.adjustmentsCents = 0,
    this.netCents = 0,
  });

  factory BalanceBreakdown.fromJson(Json json, {String netKey = 'net_cents'}) => BalanceBreakdown(
    openingCents: json.intOr('opening_cents'),
    coffees: json.intOr('coffees'),
    consumptionCents: json.intOr('consumption_cents'),
    depositsCents: json.intOr('deposits_cents'),
    personalPurchasesCents: json.intOr('personal_purchases_cents'),
    transfersSentCents: json.intOr('transfers_sent_cents'),
    transfersReceivedCents: json.intOr('transfers_received_cents'),
    reimbursementsCents: json.intOr('reimbursements_cents'),
    adjustmentsCents: json.intOr('adjustments_cents'),
    netCents: json.intOr(netKey),
  );

  final int openingCents;
  final int coffees;
  final int consumptionCents;
  final int depositsCents;
  final int personalPurchasesCents;
  final int transfersSentCents;
  final int transfersReceivedCents;
  final int reimbursementsCents;
  final int adjustmentsCents;
  final int netCents;

  /// Money the member put into the group: box deposits and beans they paid.
  int get contributionsCents => depositsCents + personalPurchasesCents;

  BalanceStatus get status => BalanceStatus.fromNet(netCents);

  /// True when the server figures satisfy the documented equation. The UI
  /// shows a warning instead of silently presenting inconsistent numbers.
  bool get isConsistent =>
      netCents ==
      openingCents +
          consumptionCents -
          depositsCents -
          personalPurchasesCents -
          transfersSentCents +
          transfersReceivedCents +
          reimbursementsCents +
          adjustmentsCents;
}

class CycleInfo {
  const CycleInfo({
    required this.id,
    required this.sequenceNo,
    required this.name,
    required this.isOpen,
    required this.openedAt,
    this.closedAt,
    this.openedByName,
    this.closedByName,
    this.closeNote,
  });

  factory CycleInfo.fromJson(Json json) => CycleInfo(
    id: json.str('id'),
    sequenceNo: json.intOr('sequence_no', 1),
    name: json.str('name'),
    isOpen: json.strOrNull('status') != 'closed',
    openedAt: json.date('opened_at'),
    closedAt: json.dateOrNull('closed_at'),
    openedByName: json.strOrNull('opened_by_name'),
    closedByName: json.strOrNull('closed_by_name'),
    closeNote: json.strOrNull('close_note'),
  );

  final String id;
  final int sequenceNo;
  final String name;
  final bool isOpen;
  final DateTime openedAt;
  final DateTime? closedAt;
  final String? openedByName;
  final String? closedByName;
  final String? closeNote;
}

class MemberBalance {
  const MemberBalance({
    required this.userId,
    required this.displayName,
    required this.role,
    required this.membershipStatus,
    required this.breakdown,
    required this.isMe,
    this.avatarPath,
  });

  factory MemberBalance.fromJson(Json json) => MemberBalance(
    userId: json.str('user_id'),
    displayName: json.str('display_name'),
    avatarPath: json.strOrNull('avatar_path'),
    role: MemberRole.parse(json.str('role')),
    membershipStatus: MembershipStatus.parse(json.str('membership_status')),
    breakdown: BalanceBreakdown.fromJson(json),
    isMe: json.boolOr('is_me'),
  );

  final String userId;
  final String displayName;
  final String? avatarPath;
  final MemberRole role;
  final MembershipStatus membershipStatus;
  final BalanceBreakdown breakdown;
  final bool isMe;

  BalanceStatus get status => breakdown.status;
}

class PendingSummary {
  const PendingSummary({
    this.count = 0,
    this.depositsCents = 0,
    this.purchasesCents = 0,
    this.boxPurchasesCents = 0,
    this.transfersCents = 0,
    this.reimbursementsCents = 0,
  });

  factory PendingSummary.fromJson(Json json) => PendingSummary(
    count: json.intOr('count'),
    depositsCents: json.intOr('deposits_cents'),
    purchasesCents: json.intOr('purchases_cents'),
    boxPurchasesCents: json.intOr('box_purchases_cents'),
    transfersCents: json.intOr('transfers_cents'),
    reimbursementsCents: json.intOr('reimbursements_cents'),
  );

  final int count;
  final int depositsCents;
  final int purchasesCents;
  final int boxPurchasesCents;
  final int transfersCents;
  final int reimbursementsCents;
}

/// Group-level figures. Debts, credits, net position and physical cash are
/// different quantities and are never presented as one another.
class GroupOverview {
  const GroupOverview({
    required this.allTime,
    required this.cycle,
    required this.coffees,
    required this.consumptionCents,
    required this.depositsCents,
    required this.personalPurchasesCents,
    required this.boxPurchasesCents,
    required this.transfersCents,
    required this.reimbursementsCents,
    required this.cashAdjustmentsCents,
    required this.balanceAdjustmentsCents,
    required this.openingCashCents,
    required this.cashBoxCents,
    required this.debtsCents,
    required this.creditsCents,
    required this.netPositionCents,
    required this.membersOwing,
    required this.membersOwed,
    required this.membersSettled,
    required this.activeMembers,
    required this.pending,
  });

  factory GroupOverview.fromJson(Json json) => GroupOverview(
    allTime: json.strOrNull('scope') == 'all_time',
    cycle: CycleInfo.fromJson(json.obj('cycle')),
    coffees: json.intOr('coffees'),
    consumptionCents: json.intOr('consumption_cents'),
    depositsCents: json.intOr('deposits_cents'),
    personalPurchasesCents: json.intOr('personal_purchases_cents'),
    boxPurchasesCents: json.intOr('box_purchases_cents'),
    transfersCents: json.intOr('transfers_cents'),
    reimbursementsCents: json.intOr('cash_reimbursements_cents'),
    cashAdjustmentsCents: json.intOr('cash_adjustments_cents'),
    balanceAdjustmentsCents: json.intOr('balance_adjustments_cents'),
    openingCashCents: json.intOr('opening_cash_cents'),
    cashBoxCents: json.intOr('cash_box_cents'),
    debtsCents: json.intOr('debts_cents'),
    creditsCents: json.intOr('credits_cents'),
    netPositionCents: json.intOr('net_position_cents'),
    membersOwing: json.intOr('members_owing'),
    membersOwed: json.intOr('members_owed'),
    membersSettled: json.intOr('members_settled'),
    activeMembers: json.intOr('active_members'),
    pending: PendingSummary.fromJson(json.obj('pending')),
  );

  final bool allTime;
  final CycleInfo cycle;
  final int coffees;
  final int consumptionCents;
  final int depositsCents;
  final int personalPurchasesCents;
  final int boxPurchasesCents;
  final int transfersCents;
  final int reimbursementsCents;
  final int cashAdjustmentsCents;
  final int balanceAdjustmentsCents;
  final int openingCashCents;
  final int cashBoxCents;

  /// Sum of what members who owe money owe.
  final int debtsCents;

  /// Sum of what the group owes to members who are owed money.
  final int creditsCents;

  /// debts - credits.
  final int netPositionCents;
  final int membersOwing;
  final int membersOwed;
  final int membersSettled;
  final int activeMembers;
  final PendingSummary pending;
}

class CashSummary {
  const CashSummary({
    required this.openingCashCents,
    required this.depositsCents,
    required this.boxPurchasesCents,
    required this.reimbursementsCents,
    required this.cashAdjustmentsCents,
    required this.closingCashCents,
  });

  factory CashSummary.fromJson(Json json) => CashSummary(
    openingCashCents: json.intOr('opening_cash_cents'),
    depositsCents: json.intOr('deposits_cents'),
    boxPurchasesCents: json.intOr('box_purchases_cents'),
    reimbursementsCents: json.intOr('reimbursements_cents'),
    cashAdjustmentsCents: json.intOr('cash_adjustments_cents'),
    closingCashCents: json.intOr('closing_cash_cents'),
  );

  final int openingCashCents;
  final int depositsCents;
  final int boxPurchasesCents;
  final int reimbursementsCents;
  final int cashAdjustmentsCents;
  final int closingCashCents;

  bool get isConsistent =>
      closingCashCents ==
      openingCashCents + depositsCents - boxPurchasesCents - reimbursementsCents + cashAdjustmentsCents;
}

class CycleReportRow {
  const CycleReportRow({
    required this.userId,
    required this.displayName,
    required this.breakdown,
    required this.active,
  });

  factory CycleReportRow.fromJson(Json json) => CycleReportRow(
    userId: json.str('user_id'),
    displayName: json.str('display_name'),
    active: json.strOrNull('membership_status') == 'active',
    breakdown: BalanceBreakdown.fromJson(json, netKey: 'closing_cents'),
  );

  final String userId;
  final String displayName;
  final bool active;
  final BalanceBreakdown breakdown;
}

class CycleReport {
  const CycleReport({
    required this.groupName,
    required this.currency,
    required this.timezone,
    required this.cycle,
    required this.isFinal,
    required this.generatedAt,
    required this.members,
    required this.cash,
    this.pending,
  });

  factory CycleReport.fromJson(Json json) {
    final group = json.obj('group');
    return CycleReport(
      groupName: group.str('name'),
      currency: group.str('currency'),
      timezone: group.str('timezone'),
      cycle: CycleInfo.fromJson(json.obj('cycle')),
      isFinal: json.boolOr('is_final'),
      generatedAt: json.date('generated_at'),
      members: json.list('members').map(CycleReportRow.fromJson).toList(),
      cash: CashSummary.fromJson(json.obj('cash')),
      pending: json['pending'] == null ? null : PendingSummary.fromJson(json.obj('pending')),
    );
  }

  final String groupName;
  final String currency;
  final String timezone;
  final CycleInfo cycle;
  final bool isFinal;
  final DateTime generatedAt;
  final List<CycleReportRow> members;
  final CashSummary cash;
  final PendingSummary? pending;

  int get totalCoffees => members.fold(0, (sum, row) => sum + row.breakdown.coffees);
  int get totalConsumptionCents => members.fold(0, (sum, row) => sum + row.breakdown.consumptionCents);
  Iterable<CycleReportRow> get carriedForward => members.where((row) => row.breakdown.netCents != 0);
}

class CycleListItem {
  const CycleListItem({
    required this.id,
    required this.sequenceNo,
    required this.name,
    required this.isOpen,
    required this.openedAt,
    required this.coffees,
    required this.consumptionCents,
    this.closedAt,
    this.closedByName,
    this.closingCashCents,
  });

  factory CycleListItem.fromJson(Json json) => CycleListItem(
    id: json.str('id'),
    sequenceNo: json.integer('sequence_no'),
    name: json.str('name'),
    isOpen: json.str('status') == 'open',
    openedAt: json.date('opened_at'),
    closedAt: json.dateOrNull('closed_at'),
    closedByName: json.strOrNull('closed_by_name'),
    coffees: json.intOr('coffees'),
    consumptionCents: json.intOr('consumption_cents'),
    closingCashCents: json.intOrNull('closing_cash_cents'),
  );

  final String id;
  final int sequenceNo;
  final String name;
  final bool isOpen;
  final DateTime openedAt;
  final DateTime? closedAt;
  final String? closedByName;
  final int coffees;
  final int consumptionCents;
  final int? closingCashCents;
}

class Reconciliation {
  const Reconciliation({
    required this.id,
    required this.expectedCents,
    required this.countedCents,
    required this.createdAt,
    this.note,
    this.adjustmentTransactionId,
    this.createdByName,
  });

  factory Reconciliation.fromJson(Json json) => Reconciliation(
    id: json.str('id'),
    expectedCents: json.integer('expected_cents'),
    countedCents: json.integer('counted_cents'),
    note: json.strOrNull('note'),
    adjustmentTransactionId: json.strOrNull('adjustment_transaction_id'),
    createdByName: json.strOrNull('created_by_name'),
    createdAt: json.date('created_at'),
  );

  final String id;
  final int expectedCents;
  final int countedCents;
  final String? note;
  final String? adjustmentTransactionId;
  final String? createdByName;
  final DateTime createdAt;

  int get differenceCents => countedCents - expectedCents;
}

class CashBoxInfo {
  const CashBoxInfo({
    required this.expectedCents,
    required this.pendingDepositsCount,
    required this.pendingDepositsCents,
    required this.pendingOutflowsCount,
    required this.pendingOutflowsCents,
    required this.reconciliations,
  });

  factory CashBoxInfo.fromJson(Json json) {
    final deposits = json.obj('pending_deposits');
    final outflows = json.obj('pending_outflows');
    return CashBoxInfo(
      expectedCents: json.intOr('expected_cents'),
      pendingDepositsCount: deposits.intOr('count'),
      pendingDepositsCents: deposits.intOr('cents'),
      pendingOutflowsCount: outflows.intOr('count'),
      pendingOutflowsCents: outflows.intOr('cents'),
      reconciliations: json.list('reconciliations').map(Reconciliation.fromJson).toList(),
    );
  }

  final int expectedCents;
  final int pendingDepositsCount;
  final int pendingDepositsCents;
  final int pendingOutflowsCount;
  final int pendingOutflowsCents;
  final List<Reconciliation> reconciliations;
}

class ReconciliationResult {
  const ReconciliationResult({required this.expectedCents, required this.countedCents, this.adjustmentTransactionId});

  factory ReconciliationResult.fromJson(Json json) => ReconciliationResult(
    expectedCents: json.integer('expected_cents'),
    countedCents: json.integer('counted_cents'),
    adjustmentTransactionId: json.strOrNull('adjustment_transaction_id'),
  );

  final int expectedCents;
  final int countedCents;
  final String? adjustmentTransactionId;

  int get differenceCents => countedCents - expectedCents;
}

class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.action,
    required this.details,
    required this.createdAt,
    this.actorName,
    this.targetType,
    this.targetId,
  });

  factory AuditEntry.fromJson(Json json) => AuditEntry(
    id: json.integer('id'),
    action: json.str('action'),
    actorName: json.strOrNull('actor_name'),
    targetType: json.strOrNull('target_type'),
    targetId: json.strOrNull('target_id'),
    details: json.objOrNull('details') ?? const {},
    createdAt: json.date('created_at'),
  );

  final int id;
  final String action;
  final String? actorName;
  final String? targetType;
  final String? targetId;
  final Json details;
  final DateTime createdAt;
}

class IntegrityCheck {
  const IntegrityCheck({required this.key, required this.ok, required this.value});

  factory IntegrityCheck.fromJson(Json json) =>
      IntegrityCheck(key: json.str('key'), ok: json.boolOr('ok'), value: json.intOr('value'));

  final String key;
  final bool ok;
  final int value;
}

class LedgerIntegrity {
  const LedgerIntegrity({required this.ok, required this.checkedAt, required this.checks, required this.figures});

  factory LedgerIntegrity.fromJson(Json json) => LedgerIntegrity(
    ok: json.boolOr('ok'),
    checkedAt: json.date('checked_at'),
    checks: json.list('checks').map(IntegrityCheck.fromJson).toList(),
    figures: json.obj('figures').map((key, value) => MapEntry(key, (value as num).toInt())),
  );

  final bool ok;
  final DateTime checkedAt;
  final List<IntegrityCheck> checks;
  final Map<String, int> figures;
}

class ExportTransaction {
  const ExportTransaction({
    required this.id,
    required this.createdAt,
    required this.occurredAt,
    required this.cycleName,
    required this.kind,
    required this.status,
    required this.amountCents,
    this.quantity,
    this.unitPriceCents,
    this.direction,
    this.memberName,
    this.counterpartyName,
    this.initiatorName,
    this.description,
    this.reversesId,
  });

  factory ExportTransaction.fromJson(Json json) => ExportTransaction(
    id: json.str('id'),
    createdAt: json.date('created_at'),
    occurredAt: json.date('occurred_at'),
    cycleName: json.str('cycle_name'),
    kind: json.str('kind'),
    status: json.str('status'),
    amountCents: json.integer('amount_cents'),
    quantity: json.intOrNull('quantity'),
    unitPriceCents: json.intOrNull('unit_price_cents'),
    direction: json.intOrNull('direction'),
    memberName: json.strOrNull('member_name'),
    counterpartyName: json.strOrNull('counterparty_name'),
    initiatorName: json.strOrNull('initiator_name'),
    description: json.strOrNull('description'),
    reversesId: json.strOrNull('reverses_id'),
  );

  final String id;
  final DateTime createdAt;
  final DateTime occurredAt;
  final String cycleName;
  final String kind;
  final String status;
  final int amountCents;
  final int? quantity;
  final int? unitPriceCents;
  final int? direction;
  final String? memberName;
  final String? counterpartyName;
  final String? initiatorName;
  final String? description;
  final String? reversesId;
}
