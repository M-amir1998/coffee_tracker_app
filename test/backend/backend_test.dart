// Backend tests against a real Supabase stack (local or CI): the public API,
// Auth, RLS, Realtime and concurrent requests, exactly as the app uses them.
//
//   npx supabase start -x studio,imgproxy,edge-runtime,logflare,vector,supavisor,postgres-meta
//   SUPABASE_URL=http://127.0.0.1:54321 SUPABASE_PUBLISHABLE_KEY=... SUPABASE_SECRET_KEY=... \
//     flutter test test/backend/backend_test.dart
//
// Without those variables every test is skipped. The secret key is only used
// to create confirmed users; every other call is made by a signed-in member.
// Never point this at a production project.
import 'dart:async';
import 'dart:io';

import 'package:coffee_tracker/core/data/rpc.dart';
import 'package:coffee_tracker/core/errors/app_failure.dart';
import 'package:coffee_tracker/core/utils/json.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _env = Platform.environment;
final _url = _env['SUPABASE_URL'] ?? '';
final _publishable = _env['SUPABASE_PUBLISHABLE_KEY'] ?? '';
final _secret = _env['SUPABASE_SECRET_KEY'] ?? '';
final _skip = _url.isEmpty || _publishable.isEmpty || _secret.isEmpty
    ? 'Set SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY and SUPABASE_SECRET_KEY to run against a local stack.'
    : null;

final _run = DateTime.now().millisecondsSinceEpoch;
const _password = 'integration-test-1';
const _noRefresh = AuthClientOptions(autoRefreshToken: false);

SupabaseClient _client() => SupabaseClient(_url, _publishable, authOptions: _noRefresh);

Future<SupabaseClient> _member(String name) async {
  final email = '${name.toLowerCase()}-$_run@example.com';
  final admin = SupabaseClient(_url, _secret, authOptions: _noRefresh);
  await admin.auth.admin.createUser(
    AdminUserAttributes(email: email, password: _password, emailConfirm: true, userMetadata: {'display_name': name}),
  );
  await admin.dispose();
  final client = _client();
  await client.auth.signInWithPassword(email: email, password: _password);
  return client;
}

String _id(SupabaseClient client) => client.auth.currentUser!.id;

Future<int> _balance(SupabaseClient client, String groupId, String userId) async {
  final rows = await client.callList('get_member_balances', {'p_group_id': groupId, 'p_all_time': true});
  return rows.firstWhere((row) => row['user_id'] == userId).integer('net_cents');
}

Future<int> _cash(SupabaseClient client, String groupId) async =>
    (await client.callJson('get_cash_box', {'p_group_id': groupId})).integer('expected_cents');

Matcher _rule(String code) => throwsA(isA<RuleFailure>().having((f) => f.code, 'code', code));

final _denied = throwsA(isA<PermissionFailure>());

Future<void> _subscribe(RealtimeChannel channel) {
  final done = Completer<void>();
  channel.subscribe((status, error) {
    if (done.isCompleted) return;
    if (status == RealtimeSubscribeStatus.subscribed) {
      done.complete();
    } else if (status != RealtimeSubscribeStatus.closed) {
      done.completeError(StateError('Realtime subscription failed: $status $error'));
    }
  });
  return done.future.timeout(const Duration(seconds: 20));
}

Future<bool> _allWithin(Duration limit, List<Completer<void>> completers) async {
  try {
    await Future.wait(completers.map((c) => c.future)).timeout(limit);
    return true;
  } on TimeoutException {
    return false;
  }
}

void main() {
  late SupabaseClient alice;
  late SupabaseClient bob;
  late SupabaseClient charlie;
  late SupabaseClient mallory;
  late String groupId;
  late String otherGroupId;

  setUpAll(() async {
    if (_skip != null) return;
    alice = await _member('Alice');
    bob = await _member('Bob');
    charlie = await _member('Charlie');
    mallory = await _member('Mallory');

    groupId =
        (await alice.call('create_group', {
              'p_name': 'Integration Lab $_run',
              'p_first_cycle_name': 'Cycle 1',
              'p_coffee_price_cents': 20,
            }))!
            as String;
    final code = (await alice.callJson('create_invitation', {'p_group_id': groupId})).str('code');
    await bob.call('join_group', {'p_code': code});
    await charlie.call('join_group', {'p_code': code});
    await alice.call('set_member_role', {'p_group_id': groupId, 'p_user_id': _id(bob), 'p_role': 'treasurer'});

    otherGroupId =
        (await mallory.call('create_group', {'p_name': 'Other Lab $_run', 'p_first_cycle_name': 'Cycle 1'}))! as String;
  });

  tearDownAll(() async {
    if (_skip != null) return;
    for (final client in [alice, bob, charlie, mallory]) {
      await client.dispose();
    }
  });

  test('a coffee recorded through the API is charged at the group price', () async {
    final result = await charlie.callJson('record_coffee', {
      'p_group_id': groupId,
      'p_idempotency_key': newIdempotencyKey(),
      'p_quantity': 3,
    });
    expect(result.integer('unit_price_cents'), 20);
    expect(result.integer('balance_cents'), 60);
    expect(await _balance(charlie, groupId, _id(charlie)), 60);
  }, skip: _skip);

  test('ten parallel retries of one submission are recorded once', () async {
    final key = newIdempotencyKey();
    final before = await _balance(alice, groupId, _id(alice));
    final results = await Future.wait([
      for (var i = 0; i < 10; i++) alice.callJson('record_coffee', {'p_group_id': groupId, 'p_idempotency_key': key}),
    ]);
    expect(results.map((r) => r.str('transaction_id')).toSet(), hasLength(1));
    expect(results.where((r) => r['replayed'] == false), hasLength(1));
    expect(await _balance(alice, groupId, _id(alice)), before + 20);
  }, skip: _skip);

  test('competing reimbursements cannot spend more than the box holds', () async {
    // The treasurer puts 10.00 in the box; Alice and Charlie are each owed 6.00.
    await bob.callJson('submit_deposit', {
      'p_group_id': groupId,
      'p_amount_cents': 1000,
      'p_idempotency_key': newIdempotencyKey(),
    });
    for (final client in [alice, charlie]) {
      await client.callJson('submit_purchase', {
        'p_group_id': groupId,
        'p_funding': 'personal',
        'p_amount_cents': 600 + await _balance(client, groupId, _id(client)),
        'p_description': 'Beans',
        'p_idempotency_key': newIdempotencyKey(),
      });
    }
    expect(await _balance(alice, groupId, _id(alice)), -600);
    expect(await _balance(charlie, groupId, _id(charlie)), -600);
    expect(await _cash(bob, groupId), 1000);

    final outcomes = await Future.wait([
      for (final member in [alice, charlie])
        bob
            .callJson('record_reimbursement', {
              'p_group_id': groupId,
              'p_member_id': _id(member),
              'p_amount_cents': 600,
              'p_idempotency_key': newIdempotencyKey(),
            })
            .then<Object>((value) => value)
            .catchError((Object error) => error),
    ]);
    expect(outcomes.whereType<Json>(), hasLength(1), reason: 'exactly one reimbursement fits in the box');
    expect(outcomes.whereType<RuleFailure>().map((f) => f.code).toList(), ['insufficient_cash']);
    expect(await _cash(bob, groupId), 400);
  }, skip: _skip);

  test('a member deposit counts only after a treasurer confirms it', () async {
    final balanceBefore = await _balance(charlie, groupId, _id(charlie));
    final cashBefore = await _cash(bob, groupId);
    final deposit = await charlie.callJson('submit_deposit', {
      'p_group_id': groupId,
      'p_amount_cents': 500,
      'p_idempotency_key': newIdempotencyKey(),
    });
    expect(deposit.str('status'), 'pending');
    expect(await _balance(charlie, groupId, _id(charlie)), balanceBefore);
    expect(await _cash(bob, groupId), cashBefore);

    final id = deposit.str('transaction_id');
    await expectLater(
      charlie.callJson('respond_to_transaction', {'p_transaction_id': id, 'p_approve': true}),
      _rule('forbidden'),
    );
    final confirmed = await bob.callJson('respond_to_transaction', {'p_transaction_id': id, 'p_approve': true});
    expect(confirmed.str('status'), 'posted');
    expect(await _balance(charlie, groupId, _id(charlie)), balanceBefore - 500);
    expect(await _cash(bob, groupId), cashBefore + 500);
  }, skip: _skip);

  test('a transfer between members counts only after the recipient confirms it', () async {
    final aliceBefore = await _balance(alice, groupId, _id(alice));
    final bobBefore = await _balance(bob, groupId, _id(bob));
    final cashBefore = await _cash(bob, groupId);
    final transfer = await alice.callJson('record_transfer', {
      'p_group_id': groupId,
      'p_from_member_id': _id(alice),
      'p_to_member_id': _id(bob),
      'p_amount_cents': 300,
      'p_idempotency_key': newIdempotencyKey(),
    });
    expect(transfer.str('status'), 'pending');
    expect(await _balance(alice, groupId, _id(alice)), aliceBefore);

    final id = transfer.str('transaction_id');
    await expectLater(
      charlie.callJson('respond_to_transaction', {'p_transaction_id': id, 'p_approve': true}),
      _rule('forbidden'),
    );
    await bob.callJson('respond_to_transaction', {'p_transaction_id': id, 'p_approve': true});
    expect(await _balance(alice, groupId, _id(alice)), aliceBefore - 300);
    expect(await _balance(bob, groupId, _id(bob)), bobBefore + 300);
    expect(await _cash(bob, groupId), cashBefore, reason: 'transfers never touch the cash box');
  }, skip: _skip);

  test('members of other groups see nothing and cannot act', () async {
    expect(await mallory.from('transactions').select().eq('group_id', groupId), isEmpty);
    expect(await mallory.from('ledger_entries').select().eq('group_id', groupId), isEmpty);
    expect(await mallory.from('group_members').select().eq('group_id', groupId), isEmpty);
    await expectLater(mallory.callJson('get_dashboard', {'p_group_id': groupId}), _rule('not_member'));
    await expectLater(
      mallory.callJson('record_coffee', {'p_group_id': groupId, 'p_idempotency_key': newIdempotencyKey()}),
      _rule('not_member'),
    );
    await expectLater(mallory.call('join_group', {'p_code': 'NOTACODE'}), throwsA(isA<RuleFailure>()));
  }, skip: _skip);

  test('signed-out clients cannot read or call anything', () async {
    final anonymous = _client();
    addTearDown(anonymous.dispose);
    await expectLater(guard(() async => anonymous.from('transactions').select().limit(1)), _denied);
    await expectLater(guard(() async => anonymous.from('profiles').select().limit(1)), _denied);
    await expectLater(anonymous.callJson('get_my_groups'), _denied);
  }, skip: _skip);

  test('members cannot write financial tables directly', () async {
    final before = await _balance(charlie, groupId, _id(charlie));
    final cycleId = (await charlie.from('accounting_cycles').select('id').eq('group_id', groupId).single())['id'];
    final someTransaction = await charlie.from('transactions').select('id').eq('group_id', groupId).limit(1).single();

    await expectLater(
      guard(
        () async => charlie.from('ledger_entries').insert({
          'transaction_id': someTransaction['id'],
          'group_id': groupId,
          'cycle_id': cycleId,
          'account': 'member',
          'member_id': _id(charlie),
          'category': 'deposit',
          'amount_cents': -100000,
        }),
      ),
      _denied,
    );
    await expectLater(
      guard(() async => charlie.from('transactions').update({'amount_cents': 1}).eq('group_id', groupId)),
      _denied,
    );
    await expectLater(guard(() async => charlie.from('transactions').delete().eq('group_id', groupId)), _denied);
    await expectLater(
      guard(() async => charlie.from('group_members').update({'role': 'admin'}).eq('user_id', _id(charlie))),
      _denied,
    );
    expect(await _balance(charlie, groupId, _id(charlie)), before);
  }, skip: _skip);

  test(
    'realtime delivers changes to members and nothing to outsiders',
    () async {
      final memberSaw = Completer<void>();
      final outsiderSawOwnGroup = Completer<void>();
      var leaked = false;

      PostgresChangeFilter inGroup(String id) =>
          PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'group_id', value: id);
      void complete(Completer<void> completer) {
        if (!completer.isCompleted) completer.complete();
      }

      final memberChannel = bob.channel('it-member-$_run')
        ..onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'transactions',
          filter: inGroup(groupId),
          callback: (_) => complete(memberSaw),
        );
      // The outsider listens to their own group as a control, so a silent
      // subscription cannot pass the leak check by accident.
      final outsiderChannel = mallory.channel('it-outsider-$_run')
        ..onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'transactions',
          filter: inGroup(otherGroupId),
          callback: (_) => complete(outsiderSawOwnGroup),
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'transactions',
          filter: inGroup(groupId),
          callback: (_) => leaked = true,
        );
      addTearDown(() async {
        await bob.removeChannel(memberChannel);
        await mallory.removeChannel(outsiderChannel);
      });
      await Future.wait([_subscribe(memberChannel), _subscribe(outsiderChannel)]);

      // Subscriptions become active shortly after joining: keep producing
      // changes in both groups until both listeners have received one.
      var delivered = false;
      for (var attempt = 0; attempt < 6 && !delivered; attempt++) {
        await charlie.callJson('record_coffee', {'p_group_id': groupId, 'p_idempotency_key': newIdempotencyKey()});
        await mallory.callJson('record_coffee', {'p_group_id': otherGroupId, 'p_idempotency_key': newIdempotencyKey()});
        delivered = await _allWithin(const Duration(seconds: 5), [memberSaw, outsiderSawOwnGroup]);
      }
      expect(delivered, isTrue, reason: 'both subscribers receive the changes of their own group');
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(leaked, isFalse, reason: 'row level security also applies to realtime');
    },
    skip: _skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('the ledger of both groups is consistent after all of the above', () async {
    for (final (client, group) in [(alice, groupId), (mallory, otherGroupId)]) {
      final integrity = await client.callJson('verify_ledger_integrity', {'p_group_id': group});
      expect(integrity['ok'], isTrue, reason: integrity.toString());
    }
  }, skip: _skip);
}
