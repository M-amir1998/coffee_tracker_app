-- Scenarios 5 and 6: direct person-to-person settlements, rejection and disputes.
begin;
select plan(27);

select tests.make_group('Lab', array['Alice', 'Bob', 'Charlie', 'Dana', 'Tess']);
select tests.login('Alice');
select public.set_member_role(tests.gid('Lab'), tests.uid('Tess'), 'treasurer');

-- Bob is owed 10.00 (beans), Charlie owes 5.00 (coffee).
select tests.login('Bob');
select public.submit_purchase(tests.gid('Lab'), 'personal', 1000, 'Beans', gen_random_uuid());
select tests.login('Charlie');
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 20);
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 5);
select is(tests.balance('Lab', 'Charlie'), 500::bigint, 'Charlie owes 5.00');

-- ---------------------------------------------------------------------------
-- Scenario 5: one user pays another directly.
-- ---------------------------------------------------------------------------
select is(public.record_transfer(tests.gid('Lab'), tests.uid('Charlie'), tests.uid('Bob'), 500, gen_random_uuid(),
  'Cash in the kitchen') ->> 'status', 'pending', 'S5: a payment recorded by the sender waits for the recipient');
select is(tests.balance('Lab', 'Charlie'), 500::bigint, 'S5: the pending payment does not change the sender');
select is(tests.balance('Lab', 'Bob'), -1000::bigint, 'S5: the pending payment does not change the recipient');
select is(tests.notification_count('Bob', 'transfer_requested'), 1, 'S5: the recipient is asked to confirm');

select throws_ok(format($$ select public.respond_to_transaction(%L, true) $$, tests.last_txn('Lab')),
  'P0001', 'forbidden', 'S5: the sender cannot confirm their own payment');
select tests.login('Dana');
select throws_ok(format($$ select public.respond_to_transaction(%L, true) $$, tests.last_txn('Lab')),
  'P0001', 'forbidden', 'S5: an unrelated member cannot confirm the payment');

select tests.login('Bob');
select is(public.respond_to_transaction(tests.last_txn('Lab'), true) ->> 'status', 'posted',
  'S5: the recipient confirms');
select is(tests.balance('Lab', 'Charlie'), 0::bigint, 'S5: Charlie is settled');
select is(tests.balance('Lab', 'Bob'), -500::bigint, 'S5: the group now owes Bob 5.00');
select is(tests.cash('Lab'), 0::bigint, 'S5: a direct payment never touches the cash box');

-- A payment recorded by the recipient only lowers their own claim, so it is final.
select is(public.record_transfer(tests.gid('Lab'), tests.uid('Dana'), tests.uid('Bob'), 200, gen_random_uuid()) ->> 'status',
  'posted', 'a payment acknowledged by the recipient is posted immediately');
select is(tests.balance('Lab', 'Dana'), -200::bigint, 'the sender is credited');
select is(tests.balance('Lab', 'Bob'), -300::bigint, 'the recipient''s claim shrinks');

select throws_ok(
  $$ select public.record_transfer(tests.gid('Lab'), tests.uid('Bob'), tests.uid('Bob'), 100, gen_random_uuid()) $$,
  'P0001', 'self_transfer', 'nobody can pay themselves');
select throws_ok(
  $$ select public.record_transfer(tests.gid('Lab'), tests.uid('Charlie'), tests.uid('Dana'), 100, gen_random_uuid()) $$,
  'P0001', 'forbidden', 'members only record payments they made or received');

-- ---------------------------------------------------------------------------
-- Scenario 6: a settlement is rejected, disputed and resolved.
-- ---------------------------------------------------------------------------
select tests.login('Charlie');
select public.record_transfer(tests.gid('Lab'), tests.uid('Charlie'), tests.uid('Dana'), 300, gen_random_uuid(), 'Paid in coins');
select tests.login('Dana');
select is(public.respond_to_transaction(tests.last_txn('Lab'), false, 'I never received it') ->> 'status', 'rejected',
  'S6: the recipient rejects the payment');
select is(tests.balance('Lab', 'Charlie'), 0::bigint, 'S6: a rejected payment does not change the sender');
select is(tests.balance('Lab', 'Dana'), -200::bigint, 'S6: a rejected payment does not change the recipient');
select is(tests.notification_payload('Charlie', 'transfer_rejected') ->> 'note', 'I never received it',
  'S6: the sender sees the reason');

select tests.login('Charlie');
select is(public.dispute_transaction(tests.last_txn('Lab'), 'I left it on her desk') ->> 'status', 'disputed',
  'S6: the sender disputes the rejection');
select throws_ok(format($$ select public.resolve_dispute(%L, true, 'ok') $$, tests.last_txn('Lab')),
  'P0001', 'forbidden', 'S6: only administrators resolve disputes');

select tests.login('Alice');
select is(public.resolve_dispute(tests.last_txn('Lab'), true, 'Found the coins on the desk') ->> 'status', 'posted',
  'S6: the administrator resolves the dispute in favour of the sender');
select is(tests.balance('Lab', 'Dana'), 100::bigint, 'S6: Dana''s credit of 2.00 shrinks by 3.00 -> owes 1.00');
select is(tests.balance('Lab', 'Charlie'), -300::bigint, 'S6: Charlie is credited 3.00');

select tests.login('Charlie');
select throws_ok(format($$ select public.dispute_transaction(%L, 'again') $$, tests.last_txn('Lab')),
  'P0001', 'invalid_state', 'a resolved transaction cannot be disputed again');

select tests.logout();
select is(tests.ledger_total('Lab'), 0::bigint, 'the ledger sums to zero');

select * from finish();
rollback;
