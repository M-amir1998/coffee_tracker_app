import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/features/accounting/domain/ledger_models.dart';
import 'package:material_ui/material_ui.dart';

/// Builds the human sentence for an activity item, e.g.
/// "Alice bought coffee beans for €12.50".
String activitySentence(BuildContext context, ActivityItem item) {
  final l10n = context.l10n;
  final unknown = l10n.someone;
  final member = item.memberName ?? unknown;
  final counterparty = item.counterpartyName ?? unknown;
  final actor = item.initiatorName ?? unknown;
  final amount = item.amountCents == null ? '' : context.money(item.amountCents!);

  switch (item.itemType) {
    case ActivityItemType.cycleOpened:
      return l10n.activityCycleOpened(item.cycleName ?? '');
    case ActivityItemType.cycleClosed:
      return l10n.activityCycleClosed(item.cycleName ?? '');
    case ActivityItemType.transaction:
      break;
  }

  return switch (item.kind) {
    TransactionKind.coffee =>
      item.initiatedBy != null && item.initiatedBy != item.memberId
          ? l10n.activityCoffeeForMember(actor, member, item.quantity ?? 1)
          : l10n.activityCoffee(member, item.quantity ?? 1),
    TransactionKind.deposit => l10n.activityDeposit(member, amount),
    TransactionKind.purchasePersonal => l10n.activityPurchasePersonal(member, amount),
    TransactionKind.purchaseBox => l10n.activityPurchaseBox(member, amount),
    TransactionKind.transfer => l10n.activityTransfer(member, counterparty, amount),
    TransactionKind.reimbursement =>
      item.initiatedBy == item.memberId
          ? l10n.activityReimbursementRequest(member, amount)
          : l10n.activityReimbursement(actor, member, amount),
    TransactionKind.cashAdjustment =>
      (item.direction ?? 1) > 0
          ? l10n.activityCashAdjustmentUp(actor, amount)
          : l10n.activityCashAdjustmentDown(actor, amount),
    TransactionKind.balanceAdjustment =>
      (item.direction ?? 1) > 0
          ? l10n.activityBalanceCharge(actor, member, amount)
          : l10n.activityBalanceCredit(actor, member, amount),
    TransactionKind.reversal => l10n.activityReversal(actor, kindLabel(l10n, item.reversedKind)),
    null => l10n.activityUnknown,
  };
}

/// Short noun for a transaction kind ("deposit", "coffee", ...).
String kindLabel(AppLocalizations l10n, TransactionKind? kind) => switch (kind) {
  TransactionKind.coffee => l10n.kindCoffee,
  TransactionKind.deposit => l10n.kindDeposit,
  TransactionKind.purchasePersonal => l10n.kindPurchasePersonal,
  TransactionKind.purchaseBox => l10n.kindPurchaseBox,
  TransactionKind.transfer => l10n.kindTransfer,
  TransactionKind.reimbursement => l10n.kindReimbursement,
  TransactionKind.cashAdjustment => l10n.kindCashAdjustment,
  TransactionKind.balanceAdjustment => l10n.kindBalanceAdjustment,
  TransactionKind.reversal => l10n.kindReversal,
  null => l10n.kindTransaction,
};

IconData activityIcon(ActivityItem item) => switch (item.itemType) {
  ActivityItemType.cycleOpened => Icons.flag_rounded,
  ActivityItemType.cycleClosed => Icons.lock_clock_rounded,
  ActivityItemType.transaction => switch (item.kind) {
    TransactionKind.coffee => Icons.coffee_rounded,
    TransactionKind.deposit => Icons.savings_rounded,
    TransactionKind.purchasePersonal => Icons.shopping_bag_rounded,
    TransactionKind.purchaseBox => Icons.inventory_2_rounded,
    TransactionKind.transfer => Icons.swap_horiz_rounded,
    TransactionKind.reimbursement => Icons.payments_rounded,
    TransactionKind.cashAdjustment => Icons.calculate_rounded,
    TransactionKind.balanceAdjustment => Icons.tune_rounded,
    TransactionKind.reversal => Icons.undo_rounded,
    null => Icons.receipt_rounded,
  },
};
