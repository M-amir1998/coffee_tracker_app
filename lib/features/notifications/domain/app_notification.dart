import 'package:coffee_tracker/core/utils/json.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.payload,
    required this.createdAt,
    this.groupId,
    this.transactionId,
    this.readAt,
  });

  factory AppNotification.fromJson(Json json) => AppNotification(
    id: json.str('id'),
    groupId: json.strOrNull('group_id'),
    kind: json.str('kind'),
    transactionId: json.strOrNull('transaction_id'),
    payload: json.objOrNull('payload') ?? const {},
    createdAt: json.date('created_at'),
    readAt: json.dateOrNull('read_at'),
  );

  final String id;
  final String? groupId;
  final String kind;
  final String? transactionId;
  final Json payload;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  String? get actorName => payload.strOrNull('actor_name');
  String? get memberName => payload.strOrNull('member_name');
  String? get counterpartyName => payload.strOrNull('counterparty_name');
  int? get amountCents => payload.intOrNull('amount_cents');
  String? get note => payload.strOrNull('note');
}
