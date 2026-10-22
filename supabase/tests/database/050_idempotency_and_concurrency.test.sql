-- Scenarios 8 and 9: duplicate submissions and competing operations.
-- True parallel requests are exercised by the HTTP integration tests
-- (integration_test/backend); here we prove the database-level guarantees.
begin;
select plan(15);

select tests.make_group('Lab', array['Alice', 'Bob', 'Charlie', 'Tess']);
select tests.login('Alice');
select public.set_member_role(tests.gid('Lab'), tests.uid('Tess'), 'treasurer');

-- ---------------------------------------------------------------------------
-- Scenario 8: a transaction is submitted twice (e.g. a retry after a timeout).
-- ---------------------------------------------------------------------------
select tests.logout();
create temporary table keys (name text primary key, key uuid not null) on commit drop;
insert into keys values ('coffee', gen_random_uuid()), ('deposit', gen_random_uuid()), ('transfer', gen_random_uuid());
grant select on keys to authenticated;

select tests.login('Bob');
select is(public.record_coffee(tests.gid('Lab'), (select key from keys where name = 'coffee'), 2) ->> 'replayed',
  'false', 'S8: first coffee submission is recorded');
select is(public.record_coffee(tests.gid('Lab'), (select key from keys where name = 'coffee'), 2) ->> 'replayed',
  'true', 'S8: the retry is recognised as a replay');
select is(tests.balance('Lab', 'Bob'), 40::bigint, 'S8: the coffees are charged only once');
select is((select count(*)::integer from public.transactions where group_id = tests.gid('Lab') and kind = 'coffee'), 1,
  'S8: only one coffee transaction exists');
select throws_ok(
  $$ select public.record_coffee(tests.gid('Lab'), (select key from keys where name = 'coffee'), 3) $$,
  'P0001', 'idempotency_conflict', 'S8: reusing a key for a different operation is rejected');

select public.submit_deposit(tests.gid('Lab'), 500, (select key from keys where name = 'deposit'));
select is(public.submit_deposit(tests.gid('Lab'), 500, (select key from keys where name = 'deposit')) ->> 'replayed',
  'true', 'S8: a duplicate deposit is a replay');
select is((select count(*)::integer from public.transactions where group_id = tests.gid('Lab') and kind = 'deposit'), 1,
  'S8: only one deposit exists');
select throws_ok(
  $$ select public.submit_deposit(tests.gid('Lab'), 700, (select key from keys where name = 'deposit')) $$,
  'P0001', 'idempotency_conflict', 'S8: same key with another amount is rejected');

select public.record_transfer(tests.gid('Lab'), tests.uid('Bob'), tests.uid('Charlie'), 100,
  (select key from keys where name = 'transfer'));
select public.record_transfer(tests.gid('Lab'), tests.uid('Bob'), tests.uid('Charlie'), 100,
  (select key from keys where name = 'transfer'));
select is((select count(*)::integer from public.transactions where group_id = tests.gid('Lab') and kind = 'transfer'), 1,
  'S8: a duplicate payment request is stored once');

-- Different users may coincidentally use the same key without clashing.
select tests.login('Charlie');
select is(public.record_coffee(tests.gid('Lab'), (select key from keys where name = 'coffee'), 1) ->> 'replayed',
  'false', 'S8: keys are scoped to the submitting user');

-- ---------------------------------------------------------------------------
-- Scenario 9: two users submit competing operations at the same time.
-- All balance-changing functions take the same per-group lock, so they run
-- one after another and each sees the result of the previous one.
-- ---------------------------------------------------------------------------
select tests.login('Alice');
select public.submit_purchase(tests.gid('Lab'), 'personal', 600, 'Beans', gen_random_uuid());
select tests.login('Bob');
select public.submit_purchase(tests.gid('Lab'), 'personal', 600, 'Beans', gen_random_uuid());
select tests.login('Tess');
select public.submit_deposit(tests.gid('Lab'), 1000, gen_random_uuid());
select is(tests.cash('Lab'), 1000::bigint, 'S9: the box holds 10.00');

-- Both creditors are owed 6.00 but the box only holds 10.00.
select public.record_reimbursement(tests.gid('Lab'), tests.uid('Alice'), 600, gen_random_uuid());
select throws_ok(
  $$ select public.record_reimbursement(tests.gid('Lab'), tests.uid('Bob'), 600, gen_random_uuid()) $$,
  'P0001', 'insufficient_cash', 'S9: the second competing reimbursement sees the reduced box and is refused');
select is(tests.cash('Lab'), 400::bigint, 'S9: the box never goes negative');

select ok(
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosrc like '%private.lock_group%'
     and p.proname in ('record_coffee', 'submit_deposit', 'submit_purchase', 'record_transfer', 'record_reimbursement',
       'respond_to_transaction', 'cancel_transaction', 'dispute_transaction', 'resolve_dispute',
       'reverse_transaction', 'record_balance_adjustment', 'reconcile_cash_box', 'close_cycle', 'undo_coffee')) = 14,
  'S9: every balance-changing function serialises on the group lock');

select tests.logout();
select is(tests.ledger_total('Lab'), 0::bigint, 'the ledger sums to zero');

select * from finish();
rollback;
