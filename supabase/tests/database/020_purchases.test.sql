-- Scenarios 3 and 4: beans bought with personal money versus box money.
begin;
select plan(19);

select tests.make_group('Lab', array['Alice', 'Bob', 'Charlie', 'Tess']);
select tests.login('Alice');
select public.set_member_role(tests.gid('Lab'), tests.uid('Tess'), 'treasurer');

-- ---------------------------------------------------------------------------
-- Scenario 3: personal funds. Bob owes 6.00, buys 15.00 of beans -> -9.00.
-- ---------------------------------------------------------------------------
select tests.login('Bob');
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 20);
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 10);
select is(tests.balance('Lab', 'Bob'), 600::bigint, 'S3: thirty coffees -> Bob owes 6.00');

select is(public.submit_purchase(tests.gid('Lab'), 'personal', 1500, '1 kg espresso beans', gen_random_uuid()) ->> 'status',
  'posted', 'S3: personal purchases post immediately when no approval is required');
select is(tests.balance('Lab', 'Bob'), -900::bigint, 'S3: Bob''s net position is -9.00 (the group owes him 9.00)');
select is(tests.cash('Lab'), 0::bigint, 'S3: a personally funded purchase does not touch the cash box');

-- ---------------------------------------------------------------------------
-- Scenario 4: box funds. The box holds 20.00, Charlie takes 15.00 for beans.
-- ---------------------------------------------------------------------------
select tests.login('Tess');
select public.submit_deposit(tests.gid('Lab'), 2000, gen_random_uuid(), 'Collected cash');
select is(tests.cash('Lab'), 2000::bigint, 'S4: the box holds 20.00');

select tests.login('Charlie');
select is(public.submit_purchase(tests.gid('Lab'), 'cash_box', 1500, 'Beans paid from the box', gen_random_uuid()) ->> 'status',
  'posted', 'S4: the box purchase is recorded');
select is(tests.cash('Lab'), 500::bigint, 'S4: the box decreases by 15.00');
select is(tests.balance('Lab', 'Charlie'), 0::bigint, 'S4: the buyer is not credited personally');
select is((select count(*)::integer from public.ledger_entries
           where transaction_id = tests.last_txn('Lab') and account = 'member'), 0,
  'S4: a box purchase has no member entry, so it cannot also count as a personal contribution');
select is((select sum(amount_cents)::bigint from public.ledger_entries
           where transaction_id = tests.last_txn('Lab') and account = 'supplies'), 1500::bigint,
  'S4: the purchase is booked as supplies');

select throws_ok(
  $$ select public.submit_purchase(tests.gid('Lab'), 'cash_box', 600, 'More beans', gen_random_uuid()) $$,
  'P0001', 'insufficient_cash', 'S4: a box purchase cannot spend more than the box holds');
select is(tests.cash('Lab'), 500::bigint, 'S4: the failed purchase left the box untouched');
select throws_ok(
  $$ select public.submit_purchase(tests.gid('Lab'), 'card', 100, 'Beans', gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'the funding source must be personal or cash_box');
select throws_ok(
  $$ select public.submit_purchase(tests.gid('Lab'), 'personal', 100, '   ', gen_random_uuid()) $$,
  'P0001', 'description_required', 'purchases need a description');

-- ---------------------------------------------------------------------------
-- Approval workflow
-- ---------------------------------------------------------------------------
select tests.login('Alice');
select public.update_group_settings(tests.gid('Lab'), p_require_purchase_approval => true);

select tests.login('Charlie');
select is(public.submit_purchase(tests.gid('Lab'), 'personal', 800, 'Decaf beans', gen_random_uuid()) ->> 'status',
  'pending', 'with approval enabled a member purchase waits');
select is(tests.balance('Lab', 'Charlie'), 0::bigint, 'a pending purchase does not credit the buyer');

select tests.login('Tess');
select public.respond_to_transaction(tests.last_txn('Lab'), true, 'Receipt checked');
select is(tests.balance('Lab', 'Charlie'), -800::bigint, 'after approval the buyer is credited 8.00');

select tests.login('Charlie');
select public.submit_purchase(tests.gid('Lab'), 'personal', 300, 'Milk', gen_random_uuid());
select tests.login('Alice');
select public.respond_to_transaction(tests.last_txn('Lab'), false, 'Milk is not part of the coffee fund');
select is(tests.balance('Lab', 'Charlie'), -800::bigint, 'a rejected purchase never credits the buyer');

select tests.logout();
select is(tests.ledger_total('Lab'), 0::bigint, 'the ledger sums to zero');

select * from finish();
rollback;
