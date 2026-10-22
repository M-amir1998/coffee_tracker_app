import 'package:coffee_tracker/core/utils/json.dart';

enum TransactionKind {
  coffee('coffee'),
  deposit('deposit'),
  purchasePersonal('purchase_personal'),
  purchaseBox('purchase_box'),
  transfer('transfer'),
  reimbursement('reimbursement'),
  cashAdjustment('cash_adjustment'),
  balanceAdjustment('balance_adjustment'),
  reversal('reversal');

  const TransactionKind(this.wireName);

  final String wireName;

  static TransactionKind parse(String value) => values.firstWhere((kind) => kind.wireName == value);

  static TransactionKind? tryParse(String? value) =>
      value == null ? null : values.where((kind) => kind.wireName == value).firstOrNull;

  bool get isPurchase => this == purchasePersonal || this == purchaseBox;
  bool get isAdjustment => this == cashAdjustment || this == balanceAdjustment;
}

/// Filter categories offered in the activity feed.
enum ActivityType {
  coffee,
  deposit,
  purchase,
  transfer,
  reimbursement,
  adjustment,
  reversal,
  cycle;

  String get wireName => name;
}

enum TransactionStatus {
  pending,
  posted,
  rejected,
  cancelled,
  disputed,
  reversed;

  static TransactionStatus parse(String value) => TransactionStatus.values.byName(value);

  static TransactionStatus? tryParse(String? value) => value == null ? null : parse(value);

  /// Pending and disputed items have not changed any balance yet.
  bool get isOpen => this == pending || this == disputed;
  bool get affectedBalances => this == posted || this == reversed;
}

enum ActivityItemType {
  transaction,
  cycleOpened,
  cycleClosed;

  static ActivityItemType parse(String value) => switch (value) {
    'cycle_opened' => cycleOpened,
    'cycle_closed' => cycleClosed,
    _ => transaction,
  };
}

/// One entry of the unified activity feed.
class ActivityItem {
  const ActivityItem({
    required this.itemType,
    required this.id,
    required this.occurredAt,
    required this.createdAt,
    this.kind,
    this.status,
    this.amountCents,
    this.quantity,
    this.unitPriceCents,
    this.direction,
    this.memberId,
    this.memberName,
    this.counterpartyId,
    this.counterpartyName,
    this.initiatedBy,
    this.initiatorName,
    this.description,
    this.reversesId,
    this.reversedKind,
    this.cycleId,
    this.cycleName,
    this.hasEvidence = false,
  });

  factory ActivityItem.fromJson(Json json) => ActivityItem(
    itemType: ActivityItemType.parse(json.strOrNull('item_type') ?? 'transaction'),
    id: json.str('id'),
    kind: TransactionKind.tryParse(json.strOrNull('kind')),
    status: TransactionStatus.tryParse(json.strOrNull('status')),
    amountCents: json.intOrNull('amount_cents'),
    quantity: json.intOrNull('quantity'),
    unitPriceCents: json.intOrNull('unit_price_cents'),
    direction: json.intOrNull('direction'),
    memberId: json.strOrNull('member_id'),
    memberName: json.strOrNull('member_name'),
    counterpartyId: json.strOrNull('counterparty_id'),
    counterpartyName: json.strOrNull('counterparty_name'),
    initiatedBy: json.strOrNull('initiated_by'),
    initiatorName: json.strOrNull('initiator_name'),
    occurredAt: json.date('occurred_at'),
    createdAt: json.date('created_at'),
    description: json.strOrNull('description'),
    reversesId: json.strOrNull('reverses_id'),
    reversedKind: TransactionKind.tryParse(json.strOrNull('reversed_kind')),
    cycleId: json.strOrNull('cycle_id'),
    cycleName: json.strOrNull('cycle_name'),
    hasEvidence: json.boolOr('has_evidence'),
  );

  final ActivityItemType itemType;
  final String id;
  final TransactionKind? kind;
  final TransactionStatus? status;
  final int? amountCents;
  final int? quantity;
  final int? unitPriceCents;

  /// For adjustments: +1 increases the member debt / box cash, -1 decreases it.
  final int? direction;
  final String? memberId;
  final String? memberName;
  final String? counterpartyId;
  final String? counterpartyName;
  final String? initiatedBy;
  final String? initiatorName;
  final DateTime occurredAt;
  final DateTime createdAt;
  final String? description;
  final String? reversesId;
  final TransactionKind? reversedKind;
  final String? cycleId;
  final String? cycleName;
  final bool hasEvidence;

  bool get isTransaction => itemType == ActivityItemType.transaction;

  /// Whether [userId] is a party of this item.
  bool involves(String userId) => memberId == userId || counterpartyId == userId || initiatedBy == userId;
}

class TransactionEvent {
  const TransactionEvent({required this.toStatus, required this.createdAt, this.fromStatus, this.actorName, this.note});

  factory TransactionEvent.fromJson(Json json) => TransactionEvent(
    fromStatus: TransactionStatus.tryParse(json.strOrNull('from_status')),
    toStatus: TransactionStatus.parse(json.str('to_status')),
    actorName: json.strOrNull('actor_name'),
    note: json.strOrNull('note'),
    createdAt: json.date('created_at'),
  );

  final TransactionStatus? fromStatus;
  final TransactionStatus toStatus;
  final String? actorName;
  final String? note;
  final DateTime createdAt;

  /// A history entry that did not change the status (e.g. carried forward).
  bool get isAnnotation => fromStatus == toStatus;
}

class TransactionPermissions {
  const TransactionPermissions({
    this.canDecide = false,
    this.canCancel = false,
    this.canDispute = false,
    this.canResolve = false,
    this.canReverse = false,
    this.canUndo = false,
  });

  factory TransactionPermissions.fromJson(Json json) => TransactionPermissions(
    canDecide: json.boolOr('can_decide'),
    canCancel: json.boolOr('can_cancel'),
    canDispute: json.boolOr('can_dispute'),
    canResolve: json.boolOr('can_resolve'),
    canReverse: json.boolOr('can_reverse'),
    canUndo: json.boolOr('can_undo'),
  );

  final bool canDecide;
  final bool canCancel;
  final bool canDispute;
  final bool canResolve;
  final bool canReverse;
  final bool canUndo;

  bool get any => canDecide || canCancel || canDispute || canResolve || canReverse || canUndo;
}

class TransactionDetail {
  const TransactionDetail({
    required this.item,
    required this.events,
    required this.permissions,
    this.evidencePath,
    this.cycleClosed = false,
    this.reversalId,
    this.reversalNote,
    this.reversesKind,
  });

  factory TransactionDetail.fromJson(Json json) {
    final txn = json.obj('transaction');
    final reversal = json.objOrNull('reversal');
    final reverses = json.objOrNull('reverses');
    return TransactionDetail(
      item: ActivityItem.fromJson({
        ...txn,
        'item_type': 'transaction',
        'has_evidence': txn['evidence_path'] != null,
        'reversed_kind': reverses?['kind'],
      }),
      evidencePath: txn.strOrNull('evidence_path'),
      cycleClosed: txn.strOrNull('cycle_status') == 'closed',
      events: json.list('events').map(TransactionEvent.fromJson).toList(),
      permissions: TransactionPermissions.fromJson(json.obj('permissions')),
      reversalId: reversal?.strOrNull('id'),
      reversalNote: reversal?.strOrNull('description'),
      reversesKind: TransactionKind.tryParse(reverses?.strOrNull('kind')),
    );
  }

  final ActivityItem item;
  final String? evidencePath;
  final bool cycleClosed;
  final List<TransactionEvent> events;
  final TransactionPermissions permissions;
  final String? reversalId;
  final String? reversalNote;
  final TransactionKind? reversesKind;
}

class PendingActions {
  const PendingActions({required this.toReview, required this.mySubmissions});

  factory PendingActions.fromJson(Json json) => PendingActions(
    toReview: json.list('to_review').map(ActivityItem.fromJson).toList(),
    mySubmissions: json.list('my_submissions').map(ActivityItem.fromJson).toList(),
  );

  static const empty = PendingActions(toReview: [], mySubmissions: []);

  final List<ActivityItem> toReview;
  final List<ActivityItem> mySubmissions;

  bool get isEmpty => toReview.isEmpty && mySubmissions.isEmpty;
}

/// Result of a balance-changing call.
class TransactionResult {
  const TransactionResult({
    required this.transactionId,
    required this.status,
    required this.replayed,
    this.amountCents,
    this.balanceCents,
    this.unitPriceCents,
  });

  factory TransactionResult.fromJson(Json json) => TransactionResult(
    transactionId: json.str('transaction_id'),
    status: TransactionStatus.parse(json.str('status')),
    replayed: json.boolOr('replayed'),
    amountCents: json.intOrNull('amount_cents'),
    balanceCents: json.intOrNull('balance_cents'),
    unitPriceCents: json.intOrNull('unit_price_cents'),
  );

  final String transactionId;
  final TransactionStatus status;
  final bool replayed;
  final int? amountCents;
  final int? balanceCents;
  final int? unitPriceCents;

  bool get isPending => status == TransactionStatus.pending;
}
