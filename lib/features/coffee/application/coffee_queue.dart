import 'dart:async';

import 'package:coffee_tracker/app/core_providers.dart';
import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/core/data/rpc.dart';
import 'package:coffee_tracker/core/errors/app_failure.dart';
import 'package:coffee_tracker/features/accounting/domain/ledger_models.dart';
import 'package:coffee_tracker/features/coffee/data/coffee_queue_store.dart';
import 'package:coffee_tracker/features/coffee/domain/pending_coffee.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Emits when connectivity changes to "some network available".
/// Overridable in tests.
final networkAvailableProvider = Provider<Stream<bool>>((ref) {
  return Connectivity().onConnectivityChanged.map((results) => results.any((r) => r != ConnectivityResult.none));
});

final coffeeQueueStoreProvider = Provider<CoffeeQueueStore>(
  (ref) => CoffeeQueueStore(ref.watch(sharedPreferencesProvider)),
);

sealed class CoffeeOutcome {
  const CoffeeOutcome();
}

/// The server recorded the coffee.
class CoffeeRecorded extends CoffeeOutcome {
  const CoffeeRecorded(this.result);
  final TransactionResult result;
}

/// No connection: the coffee is saved on the device and will be sent later.
class CoffeeQueued extends CoffeeOutcome {
  const CoffeeQueued(this.key);
  final String key;
}

/// The server refused the coffee.
class CoffeeRejected extends CoffeeOutcome {
  const CoffeeRejected(this.failure);
  final AppFailure failure;
}

class CoffeeQueueState {
  const CoffeeQueueState({this.items = const [], this.syncing = false});

  final List<PendingCoffee> items;
  final bool syncing;

  Iterable<PendingCoffee> forGroup(String groupId) => items.where((item) => item.groupId == groupId);

  int waitingCoffees(String groupId) => forGroup(
    groupId,
  ).where((item) => item.state == PendingCoffeeState.waiting).fold(0, (sum, item) => sum + item.quantity);

  List<PendingCoffee> failed(String groupId) =>
      forGroup(groupId).where((item) => item.state == PendingCoffeeState.failed).toList();
}

final coffeeQueueProvider = NotifierProvider<CoffeeQueue, CoffeeQueueState>(CoffeeQueue.new);

/// Offline-capable coffee logging. Only coffee consumption is queued; every
/// other financial operation needs the server to confirm it first.
class CoffeeQueue extends Notifier<CoffeeQueueState> {
  static const maxQueueLength = 50;
  static const _backoff = [Duration(seconds: 5), Duration(seconds: 15), Duration(seconds: 30), Duration(minutes: 1)];

  Timer? _retryTimer;
  Future<void>? _activeSync;

  CoffeeQueueStore get _store => ref.read(coffeeQueueStoreProvider);

  DateTime _now() => ref.read(clockProvider)();

  @override
  CoffeeQueueState build() {
    final subscription = ref.watch(networkAvailableProvider).listen((online) {
      if (online) unawaited(syncAll());
    });
    ref.onDispose(() {
      unawaited(subscription.cancel());
      _retryTimer?.cancel();
    });
    final items = _store.load();
    if (items.any((item) => item.state == PendingCoffeeState.waiting)) _scheduleRetry(0);
    return CoffeeQueueState(items: items);
  }

  /// Records [quantity] coffees for the signed-in member. Returns once the
  /// server answered or the coffee was safely queued on the device.
  Future<CoffeeOutcome> record(String groupId, {int quantity = 1}) async {
    if (state.items.length >= maxQueueLength) {
      return const CoffeeRejected(RuleFailure('queue_full'));
    }
    final item = PendingCoffee(key: newIdempotencyKey(), groupId: groupId, quantity: quantity, occurredAt: _now());
    await _replace([...state.items, item]);
    return _send(item);
  }

  /// Removes a coffee that has not reached the server yet ("undo" while
  /// offline). Returns false when it was already sent.
  Future<bool> removeQueued(String key) async {
    final exists = state.items.any((item) => item.key == key);
    if (!exists) return false;
    await _replace(state.items.where((item) => item.key != key).toList());
    return true;
  }

  Future<void> retry(String key) async {
    final item = state.items.where((i) => i.key == key).firstOrNull;
    if (item == null) return;
    final reset = item.copyWith(state: PendingCoffeeState.waiting, errorCode: () => null);
    await _update(reset);
    await _send(reset);
  }

  /// Sends every waiting coffee, oldest first. Safe to call often.
  Future<void> syncAll() => _activeSync ??= _syncAll().whenComplete(() => _activeSync = null);

  Future<void> _syncAll() async {
    final waiting = state.items.where((item) => item.state == PendingCoffeeState.waiting).toList()
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    if (waiting.isEmpty) return;
    state = CoffeeQueueState(items: state.items, syncing: true);
    try {
      for (final item in waiting) {
        final outcome = await _send(item, bumpRevision: false);
        if (outcome is CoffeeQueued) break; // still offline; keep the order
      }
    } finally {
      if (ref.mounted) {
        state = CoffeeQueueState(items: state.items);
        ref.read(dataRevisionProvider.notifier).bump();
      }
    }
  }

  Future<CoffeeOutcome> _send(PendingCoffee item, {bool bumpRevision = true}) async {
    if (item.isExpired(_now())) {
      await _update(item.copyWith(state: PendingCoffeeState.failed, errorCode: () => 'occurred_at_out_of_range'));
      return const CoffeeRejected(RuleFailure('occurred_at_out_of_range'));
    }
    try {
      final result = await ref
          .read(ledgerRepositoryProvider)
          .recordCoffee(
            groupId: item.groupId,
            idempotencyKey: item.key,
            quantity: item.quantity,
            occurredAt: item.occurredAt,
          );
      if (!ref.mounted) return CoffeeRecorded(result);
      await _replace(state.items.where((i) => i.key != item.key).toList());
      if (bumpRevision) ref.read(dataRevisionProvider.notifier).bump();
      return CoffeeRecorded(result);
    } on AppFailure catch (failure) {
      if (!ref.mounted) return CoffeeQueued(item.key);
      if (failure.isRetryable || failure is SessionExpiredFailure) {
        final attempts = item.attempts + 1;
        await _update(item.copyWith(attempts: attempts));
        _scheduleRetry(attempts);
        return CoffeeQueued(item.key);
      }
      final code = failure is RuleFailure ? failure.code : 'unexpected';
      await _update(item.copyWith(state: PendingCoffeeState.failed, errorCode: () => code));
      return CoffeeRejected(failure);
    }
  }

  void _scheduleRetry(int attempts) {
    _retryTimer?.cancel();
    final delay = _backoff[attempts.clamp(0, _backoff.length - 1)];
    _retryTimer = Timer(delay, () {
      if (ref.mounted) unawaited(syncAll());
    });
  }

  Future<void> _update(PendingCoffee updated) =>
      _replace([for (final item in state.items) item.key == updated.key ? updated : item]);

  Future<void> _replace(List<PendingCoffee> items) async {
    state = CoffeeQueueState(items: items, syncing: state.syncing);
    await _store.save(items);
  }
}
