import 'dart:async';

import 'package:coffee_tracker/app/core_providers.dart';
import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/core/errors/app_failure.dart';
import 'package:coffee_tracker/features/accounting/data/ledger_repository.dart';
import 'package:coffee_tracker/features/accounting/domain/ledger_models.dart';
import 'package:coffee_tracker/features/auth/application/auth_providers.dart';
import 'package:coffee_tracker/features/coffee/application/coffee_queue.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Records calls and answers like the database would, with a switch to
/// simulate being offline or a refusal.
class FakeLedgerRepository implements LedgerRepository {
  final calls = <({String key, int quantity, DateTime? occurredAt})>[];
  final undone = <String>[];
  final _recorded = <String>{};
  AppFailure? failWith;
  int balanceCents = 0;

  @override
  Future<TransactionResult> recordCoffee({
    required String groupId,
    required String idempotencyKey,
    int quantity = 1,
    DateTime? occurredAt,
    String? forMemberId,
  }) async {
    calls.add((key: idempotencyKey, quantity: quantity, occurredAt: occurredAt));
    final failure = failWith;
    if (failure != null) throw failure;
    // Like the database: a key that was already recorded is a replay.
    final replayed = !_recorded.add(idempotencyKey);
    if (!replayed) balanceCents += 20 * quantity;
    return TransactionResult(
      transactionId: 'txn-$idempotencyKey',
      status: TransactionStatus.posted,
      replayed: replayed,
      amountCents: 20 * quantity,
      unitPriceCents: 20,
      balanceCents: balanceCents,
    );
  }

  @override
  Future<TransactionResult> undoCoffee(String transactionId) async {
    undone.add(transactionId);
    balanceCents -= 20;
    return TransactionResult(transactionId: 'rev-$transactionId', status: TransactionStatus.posted, replayed: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A clock the test can move forward.
class TestClock {
  TestClock(this.now);

  DateTime now;

  DateTime call() => now;
}

Future<SharedPreferencesWithCache> inMemoryPreferences([Map<String, Object> initial = const {}]) async {
  SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.withData(initial);
  return SharedPreferencesWithCache.create(cacheOptions: const SharedPreferencesWithCacheOptions());
}

/// Overrides shared by unit and widget tests that exercise the coffee queue.
List<Override> queueOverrides({
  required SharedPreferencesWithCache preferences,
  required FakeLedgerRepository ledger,
  required TestClock clock,
  required StreamController<bool> network,
  Override? currentUser,
}) => [
  sharedPreferencesProvider.overrideWithValue(preferences),
  ledgerRepositoryProvider.overrideWithValue(ledger),
  clockProvider.overrideWithValue(clock.call),
  networkAvailableProvider.overrideWithValue(network.stream),
  currentUser ?? currentUserIdProvider.overrideWithValue('alice'),
];
