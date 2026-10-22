-- Scenarios 1, 2 and 10: paying exactly, overpaying, and a price change in the
-- middle of a cycle. Also coffee validation, on-behalf recording and undo.
begin;
select plan(34);

select tests.make_group('Lab', array['Alice', 'Bob', 'Charlie', 'Tess', 'Mallory']);
select tests.login('Alice');
select public.set_member_role(tests.gid('Lab'), tests.uid('Tess'), 'treasurer');

-- ---------------------------------------------------------------------------
-- Scenario 1: one user drinks coffee and pays exactly the amount owed.
-- ---------------------------------------------------------------------------
select tests.login('Charlie');
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 3);
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 2);
select is(tests.balance('Lab', 'Charlie'), 100::bigint, 'S1: five coffees at 0.20 -> Charlie owes 1.00');

select is(public.submit_deposit(tests.gid('Lab'), 100, gen_random_uuid(), 'Coins in the box') ->> 'status',
  'pending', 'S1: a member deposit waits for treasurer confirmation');
select is(tests.balance('Lab', 'Charlie'), 100::bigint, 'S1: an unconfirmed deposit does not change the balance');
select is(tests.cash('Lab'), 0::bigint, 'S1: an unconfirmed deposit is not counted as cash');

select tests.login('Bob');
select throws_ok(
  format($$ select public.respond_to_transaction(%L, true) $$, tests.last_txn('Lab')),
  'P0001', 'forbidden', 'S1: an ordinary member cannot confirm deposits');

select tests.login('Tess');
select is(public.respond_to_transaction(tests.last_txn('Lab'), true) ->> 'status', 'posted',
  'S1: the treasurer confirms the deposit');
select is(tests.balance('Lab', 'Charlie'), 0::bigint, 'S1: Charlie is settled');
select is(tests.cash('Lab'), 100::bigint, 'S1: the box holds 1.00');

-- ---------------------------------------------------------------------------
-- Scenario 2: a user pays more than owed.
-- ---------------------------------------------------------------------------
select tests.login('Bob');
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 2);
select public.submit_deposit(tests.gid('Lab'), 500, gen_random_uuid(), 'A five euro note');
select tests.login('Tess');
select public.respond_to_transaction(tests.last_txn('Lab'), true);
select is(tests.balance('Lab', 'Bob'), -460::bigint, 'S2: Bob paid 5.00 for 0.40 of coffee -> group owes him 4.60');
select is(tests.cash('Lab'), 600::bigint, 'S2: the box holds 6.00');

-- Treasurer deposits are final immediately (they hold the box).
select is(public.submit_deposit(tests.gid('Lab'), 200, gen_random_uuid()) ->> 'status', 'posted',
  'treasurer deposits are posted immediately');
select is(tests.balance('Lab', 'Tess'), -200::bigint, 'the treasurer is credited 2.00');
select is(tests.cash('Lab'), 800::bigint, 'the box holds 8.00');

-- Treasurer records cash handed over by a member.
select is(public.submit_deposit(tests.gid('Lab'), 50, gen_random_uuid(), 'Given to me', tests.uid('Charlie')) ->> 'status',
  'posted', 'a treasurer can record a deposit on behalf of a member');
select is(tests.balance('Lab', 'Charlie'), -50::bigint, 'the member is credited');

-- A rejected deposit never touches balances.
select tests.login('Mallory');
select public.submit_deposit(tests.gid('Lab'), 1000, gen_random_uuid(), 'I promise');
select tests.login('Tess');
select throws_ok(
  format($$ select public.respond_to_transaction(%L, false) $$, tests.last_txn('Lab')),
  'P0001', 'note_required', 'rejections need an explanation');
select is(public.respond_to_transaction(tests.last_txn('Lab'), false, 'Box was empty when counted') ->> 'status',
  'rejected', 'the treasurer rejects the deposit');
select is(tests.balance('Lab', 'Mallory'), 0::bigint, 'a rejected deposit does not change the balance');
select is(tests.cash('Lab'), 850::bigint, 'a rejected deposit is not cash');

-- ---------------------------------------------------------------------------
-- Scenario 10: the coffee price changes in the middle of a cycle.
-- ---------------------------------------------------------------------------
select tests.login('Charlie');
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 1);
select tests.login('Alice');
select public.set_coffee_price(tests.gid('Lab'), 25);
select tests.login('Charlie');
select is((public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 2) ->> 'unit_price_cents')::integer, 25,
  'S10: new coffees use the new price');
select is(tests.balance('Lab', 'Charlie'), (-50 + 20 + 50)::bigint,
  'S10: one coffee at 0.20 and two at 0.25 on top of a 0.50 credit -> owes 0.20');
select is((select count(*)::integer from public.transactions
           where group_id = tests.gid('Lab') and kind = 'coffee' and unit_price_cents = 20), 4,
  'S10: earlier coffees keep their recorded price of 0.20');
select is((select sum(amount_cents)::bigint from public.transactions
           where group_id = tests.gid('Lab') and kind = 'coffee' and member_id = tests.uid('Charlie')), 170::bigint,
  'S10: Charlie''s coffee charges total 1.70 (6 x 0.20 + 2 x 0.25)');

-- A coffee queued offline before the price change keeps the old price.
select is((public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 1, now() - interval '1 hour') ->> 'unit_price_cents')::integer,
  20, 'S10: an offline coffee from before the change is charged the old price');
select throws_ok(
  $$ select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 1, now() - interval '8 days') $$,
  'P0001', 'occurred_at_out_of_range', 'coffees older than 7 days are refused');
select throws_ok(
  $$ select public.set_coffee_price(tests.gid('Lab'), 30) $$,
  'P0001', 'forbidden', 'only administrators change the price');

-- ---------------------------------------------------------------------------
-- Validation, on-behalf recording and undo
-- ---------------------------------------------------------------------------
select throws_ok($$ select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 0) $$,
  'P0001', 'invalid_quantity', 'zero coffees are refused');
select throws_ok($$ select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 1, null, tests.uid('Bob')) $$,
  'P0001', 'forbidden', 'members cannot record coffees for others');

select tests.login('Alice');
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 1, null, tests.uid('Bob'));
select is(tests.notification_count('Bob', 'coffee_recorded_for_you'), 1,
  'an administrator can record a coffee for a member, who is notified');

select tests.login('Bob');
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 1);
select is(public.undo_coffee(tests.last_txn('Lab')) ->> 'kind', 'reversal', 'a member can undo their own coffee');
select is((select status::text from public.transactions
           where id = (select reverses_id from public.transactions where id = tests.last_txn('Lab'))),
  'reversed', 'the original coffee is kept and marked reversed');
select is(tests.balance('Lab', 'Bob'), (-460 + 25)::bigint, 'the undo restores the balance (only the on-behalf coffee remains)');
select throws_ok(
  format($$ select public.undo_coffee(%L) $$,
    (select id from public.transactions where group_id = tests.gid('Lab') and kind = 'coffee'
       and member_id = tests.uid('Bob') and initiated_by = tests.uid('Alice'))),
  'P0001', 'forbidden', 'coffees recorded by someone else cannot be undone by the member');

select tests.logout();
select is(tests.ledger_total('Lab'), 0::bigint, 'the ledger sums to zero');

select * from finish();
rollback;
