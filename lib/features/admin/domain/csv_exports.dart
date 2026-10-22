import 'package:coffee_tracker/core/utils/csv.dart';
import 'package:coffee_tracker/features/accounting/domain/balance_models.dart';
import 'package:coffee_tracker/features/leaderboard/domain/leaderboard_models.dart';

/// CSV exports. Headers are in English and amounts are plain decimals so the
/// files stay machine-readable regardless of the app language.

String balancesCsv(List<MemberBalance> rows, {required String currency, required String scope}) {
  final csv = CsvBuilder([
    'member',
    'membership',
    'role',
    'scope',
    'currency',
    'opening',
    'coffees',
    'consumption',
    'deposits',
    'personal_purchases',
    'transfers_sent',
    'transfers_received',
    'reimbursements',
    'adjustments',
    'net_balance',
    'status',
  ]);
  for (final row in rows) {
    final b = row.breakdown;
    csv.addRow([
      row.displayName,
      row.membershipStatus.name,
      row.role.name,
      scope,
      currency,
      centsToDecimal(b.openingCents),
      b.coffees,
      centsToDecimal(b.consumptionCents),
      centsToDecimal(b.depositsCents),
      centsToDecimal(b.personalPurchasesCents),
      centsToDecimal(b.transfersSentCents),
      centsToDecimal(b.transfersReceivedCents),
      centsToDecimal(b.reimbursementsCents),
      centsToDecimal(b.adjustmentsCents),
      centsToDecimal(b.netCents),
      row.status.name,
    ]);
  }
  return csv.build();
}

String coffeeStatsCsv(Map<String, LeaderboardData> boards) {
  final csv = CsvBuilder(['period', 'member', 'coffees', 'group_total']);
  for (final MapEntry(key: period, value: board) in boards.entries) {
    for (final entry in board.entries) {
      csv.addRow([period, entry.displayName, entry.coffees, board.totalCoffees]);
    }
  }
  return csv.build();
}

String transactionsCsv(List<ExportTransaction> rows, {required String currency}) {
  final csv = CsvBuilder([
    'id',
    'recorded_at',
    'occurred_at',
    'cycle',
    'type',
    'status',
    'currency',
    'amount',
    'quantity',
    'unit_price',
    'direction',
    'member',
    'counterparty',
    'recorded_by',
    'description',
    'reverses',
  ]);
  for (final t in rows) {
    csv.addRow([
      t.id,
      t.createdAt.toUtc().toIso8601String(),
      t.occurredAt.toUtc().toIso8601String(),
      t.cycleName,
      t.kind,
      t.status,
      currency,
      centsToDecimal(t.amountCents),
      t.quantity,
      t.unitPriceCents == null ? null : centsToDecimal(t.unitPriceCents!),
      t.direction,
      t.memberName,
      t.counterpartyName,
      t.initiatorName,
      t.description,
      t.reversesId,
    ]);
  }
  return csv.build();
}

String purchasesCsv(List<ExportTransaction> rows, {required String currency}) {
  final csv = CsvBuilder(['date', 'buyer', 'funding', 'status', 'currency', 'amount', 'description']);
  for (final t in rows.where((t) => t.kind == 'purchase_personal' || t.kind == 'purchase_box')) {
    csv.addRow([
      t.occurredAt.toUtc().toIso8601String().substring(0, 10),
      t.memberName,
      t.kind == 'purchase_box' ? 'cash_box' : 'personal',
      t.status,
      currency,
      centsToDecimal(t.amountCents),
      t.description,
    ]);
  }
  return csv.build();
}

String cycleReportCsv(CycleReport report) {
  final csv = CsvBuilder([
    'group',
    'cycle',
    'final',
    'member',
    'opening',
    'coffees',
    'consumption',
    'deposits',
    'personal_purchases',
    'transfers_sent',
    'transfers_received',
    'reimbursements',
    'adjustments',
    'closing',
  ]);
  for (final row in report.members) {
    final b = row.breakdown;
    csv.addRow([
      report.groupName,
      report.cycle.name,
      report.isFinal,
      row.displayName,
      centsToDecimal(b.openingCents),
      b.coffees,
      centsToDecimal(b.consumptionCents),
      centsToDecimal(b.depositsCents),
      centsToDecimal(b.personalPurchasesCents),
      centsToDecimal(b.transfersSentCents),
      centsToDecimal(b.transfersReceivedCents),
      centsToDecimal(b.reimbursementsCents),
      centsToDecimal(b.adjustmentsCents),
      centsToDecimal(b.netCents),
    ]);
  }
  final cash = report.cash;
  csv
    ..addRow([])
    ..addRow(['cash_box', 'opening', 'deposits', 'box_purchases', 'reimbursements', 'adjustments', 'closing'])
    ..addRow([
      report.cycle.name,
      centsToDecimal(cash.openingCashCents),
      centsToDecimal(cash.depositsCents),
      centsToDecimal(cash.boxPurchasesCents),
      centsToDecimal(cash.reimbursementsCents),
      centsToDecimal(cash.cashAdjustmentsCents),
      centsToDecimal(cash.closingCashCents),
    ]);
  return csv.build();
}
