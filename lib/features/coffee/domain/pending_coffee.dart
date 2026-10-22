import 'package:coffee_tracker/core/utils/json.dart';

enum PendingCoffeeState {
  /// Saved on this device, waiting to be sent.
  waiting,

  /// The server refused it (e.g. the member left the group). Needs attention.
  failed,
}

/// A coffee recorded on this device that the server has not confirmed yet.
class PendingCoffee {
  const PendingCoffee({
    required this.key,
    required this.userId,
    required this.groupId,
    required this.quantity,
    required this.occurredAt,
    this.state = PendingCoffeeState.waiting,
    this.attempts = 0,
    this.errorCode,
  });

  factory PendingCoffee.fromJson(Json json) => PendingCoffee(
    key: json.str('key'),
    userId: json.str('user_id'),
    groupId: json.str('group_id'),
    quantity: json.integer('quantity'),
    occurredAt: json.date('occurred_at'),
    state: PendingCoffeeState.values.byName(json.strOrNull('state') ?? 'waiting'),
    attempts: json.intOr('attempts'),
    errorCode: json.strOrNull('error_code'),
  );

  /// Idempotency key generated on the device; retries reuse it, so the server
  /// records the coffee at most once.
  final String key;

  /// The member who drank it. Only their session may send it, so a coffee
  /// queued on a shared device is never charged to the next person who signs in.
  final String userId;
  final String groupId;
  final int quantity;

  /// When the coffee was drunk; the server charges the price valid then.
  final DateTime occurredAt;
  final PendingCoffeeState state;
  final int attempts;
  final String? errorCode;

  /// The server only accepts coffees from the last seven days.
  static const maxAge = Duration(days: 7);

  bool isExpired(DateTime now) => now.difference(occurredAt) > maxAge;

  PendingCoffee copyWith({PendingCoffeeState? state, int? attempts, String? Function()? errorCode}) => PendingCoffee(
    key: key,
    userId: userId,
    groupId: groupId,
    quantity: quantity,
    occurredAt: occurredAt,
    state: state ?? this.state,
    attempts: attempts ?? this.attempts,
    errorCode: errorCode == null ? this.errorCode : errorCode(),
  );

  Json toJson() => {
    'key': key,
    'user_id': userId,
    'group_id': groupId,
    'quantity': quantity,
    'occurred_at': occurredAt.toUtc().toIso8601String(),
    'state': state.name,
    'attempts': attempts,
    'error_code': errorCode,
  };
}
