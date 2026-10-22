import 'dart:async';

import 'package:coffee_tracker/core/errors/app_failure.dart';
import 'package:coffee_tracker/features/coffee/application/coffee_queue.dart';
import 'package:coffee_tracker/features/coffee/data/coffee_queue_store.dart';
import 'package:coffee_tracker/features/coffee/domain/pending_coffee.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

void main() {
  late FakeLedgerRepository ledger;
  late TestClock clock;
  late StreamController<bool> network;

  setUp(() {
    ledger = FakeLedgerRepository();
    clock = TestClock(DateTime.utc(2026, 10, 22, 9));
    network = StreamController<bool>.broadcast();
  });

  tearDown(() => network.close());

  Future<ProviderContainer> container({Map<String, Object> stored = const {}}) async {
    final preferences = await inMemoryPreferences(stored);
    final c = ProviderContainer.test(
      overrides: queueOverrides(preferences: preferences, ledger: ledger, clock: clock, network: network),
    );
    return c;
  }

  test('records immediately when online', () async {
    final c = await container();
    final outcome = await c.read(coffeeQueueProvider.notifier).record('g1');
    expect(outcome, isA<CoffeeRecorded>());
    expect((outcome as CoffeeRecorded).result.balanceCents, 20);
    expect(c.read(coffeeQueueProvider).items, isEmpty);
    expect(ledger.calls.single.occurredAt, clock.now);
  });

  test('keeps the coffee when offline and sends it once the network returns', () async {
    final c = await container();
    ledger.failWith = const NetworkFailure();
    final outcome = await c.read(coffeeQueueProvider.notifier).record('g1', quantity: 2);
    expect(outcome, isA<CoffeeQueued>());
    expect(c.read(coffeeQueueProvider).waitingCoffees('g1'), 2);

    ledger.failWith = null;
    network.add(true);
    await pumpEventQueue();
    expect(c.read(coffeeQueueProvider).items, isEmpty);
    // Both attempts used the same idempotency key, so the server records it once.
    expect(ledger.calls.map((call) => call.key).toSet(), hasLength(1));
    expect(ledger.balanceCents, 40);
    // The original time is kept so the price of that moment applies.
    expect(ledger.calls.last.occurredAt, DateTime.utc(2026, 10, 22, 9));
  });

  test('a refusal is kept visible instead of being dropped silently', () async {
    final c = await container();
    ledger.failWith = const RuleFailure('not_member');
    final outcome = await c.read(coffeeQueueProvider.notifier).record('g1');
    expect(outcome, isA<CoffeeRejected>());
    final failed = c.read(coffeeQueueProvider).failed('g1').single;
    expect(failed.errorCode, 'not_member');

    ledger.failWith = null;
    await c.read(coffeeQueueProvider.notifier).retry(failed.key);
    expect(c.read(coffeeQueueProvider).items, isEmpty);
  });

  test('undo while offline removes the coffee before it reaches the server', () async {
    final c = await container();
    ledger.failWith = const NetworkFailure();
    final outcome = await c.read(coffeeQueueProvider.notifier).record('g1') as CoffeeQueued;
    expect(await c.read(coffeeQueueProvider.notifier).removeQueued(outcome.key), isTrue);
    expect(c.read(coffeeQueueProvider).items, isEmpty);
    expect(await c.read(coffeeQueueProvider.notifier).removeQueued(outcome.key), isFalse);
  });

  test('coffees older than seven days are not sent', () async {
    final c = await container();
    ledger.failWith = const NetworkFailure();
    await c.read(coffeeQueueProvider.notifier).record('g1');
    final attempts = ledger.calls.length;

    clock.now = clock.now.add(const Duration(days: 8));
    ledger.failWith = null;
    await c.read(coffeeQueueProvider.notifier).syncAll();
    expect(ledger.calls.length, attempts, reason: 'expired coffees are not sent to the server');
    expect(c.read(coffeeQueueProvider).failed('g1').single.errorCode, 'occurred_at_out_of_range');
  });

  test('the queue survives an app restart', () async {
    final first = await container();
    ledger.failWith = const NetworkFailure();
    await first.read(coffeeQueueProvider.notifier).record('g1');
    final stored = first.read(coffeeQueueStoreProvider).load();
    expect(stored, hasLength(1));

    final second = await container(stored: {CoffeeQueueStore.storageKey: _encode(stored)});
    expect(second.read(coffeeQueueProvider).items.single.key, stored.single.key);
  });

  test('sync sends the oldest coffee first and stops while offline', () async {
    final c = await container();
    ledger.failWith = const NetworkFailure();
    await c.read(coffeeQueueProvider.notifier).record('g1');
    clock.now = clock.now.add(const Duration(minutes: 5));
    await c.read(coffeeQueueProvider.notifier).record('g1');
    final keys = c.read(coffeeQueueProvider).items.map((i) => i.key).toList();
    ledger.calls.clear();

    await c.read(coffeeQueueProvider.notifier).syncAll();
    expect(ledger.calls.map((call) => call.key), [keys.first], reason: 'stops after the first network failure');

    ledger.failWith = null;
    await c.read(coffeeQueueProvider.notifier).syncAll();
    expect(ledger.calls.skip(1).map((call) => call.key), keys);
    expect(c.read(coffeeQueueProvider).items, isEmpty);
  });

  test('pending coffees serialise faithfully', () {
    final item = PendingCoffee(
      key: 'k',
      groupId: 'g',
      quantity: 3,
      occurredAt: DateTime.utc(2026, 1, 2, 3, 4),
      state: PendingCoffeeState.failed,
      attempts: 2,
      errorCode: 'x',
    );
    final copy = PendingCoffee.fromJson(item.toJson());
    expect(
      (copy.key, copy.groupId, copy.quantity, copy.occurredAt, copy.state, copy.attempts, copy.errorCode),
      (item.key, item.groupId, item.quantity, item.occurredAt, item.state, item.attempts, item.errorCode),
    );
  });
}

String _encode(List<PendingCoffee> items) =>
    '[${items.map((i) => '{"key":"${i.key}","group_id":"${i.groupId}","quantity":${i.quantity},'
        '"occurred_at":"${i.occurredAt.toUtc().toIso8601String()}","state":"${i.state.name}","attempts":${i.attempts}}').join(',')}]';
