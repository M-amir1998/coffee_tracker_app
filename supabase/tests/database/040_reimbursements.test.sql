-- Scenario 7: reimbursement from the physical cash box (the example from the
-- requirements: A bought 20.00 of beans and drank 10.00; B pays 10.00 into the
-- box; the treasurer hands A 10.00 from the box).
begin;
select plan(20);

select tests.make_group('Lab', array['Alice', 'Bob', 'Charlie', 'Tess']);
select tests.login('Alice');
select public.set_member_role(tests.gid('Lab'), tests.uid('Tess'), 'treasurer');

-- A: 20.00 of beans, 10.00 of coffee.
select public.submit_purchase(tests.gid('Lab'), 'personal', 2000, '2 kg beans', gen_random_uuid());
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 20);
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 20);
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 10);
select is(tests.balance('Lab', 'Alice'), -1000::bigint, 'S7: the group owes A 10.00');

-- B drank 10.00 and deposits 10.00.
select tests.login('Bob');
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 20);
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 20);
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 10);
select public.submit_deposit(tests.gid('Lab'), 1000, gen_random_uuid());
select tests.login('Tess');
select public.respond_to_transaction(tests.last_txn('Lab'), true);
select is(tests.cash('Lab'), 1000::bigint, 'S7: the box contains 10.00');
select is(tests.balance('Lab', 'Bob'), 0::bigint, 'S7: B is settled');
select is(tests.balance('Lab', 'Alice'), -1000::bigint, 'S7: A is still owed 10.00');

-- Treasurer gives 10.00 from the box to A.
select is(public.record_reimbursement(tests.gid('Lab'), tests.uid('Alice'), 1000, gen_random_uuid(), 'Cash from the box') ->> 'status',
  'posted', 'S7: the treasurer records the reimbursement');
select is(tests.cash('Lab'), 0::bigint, 'S7: the box decreases by 10.00');
select is(tests.balance('Lab', 'Alice'), 0::bigint, 'S7: A becomes settled');
select is((select kind::text from public.transactions where id = tests.last_txn('Lab')), 'reimbursement',
  'S7: a reimbursement is its own transaction type, not a member-to-member payment');
select is(tests.notification_count('Alice', 'reimbursement_paid'), 1, 'S7: A is notified');

-- ---------------------------------------------------------------------------
-- Double reimbursement and cash limits
-- ---------------------------------------------------------------------------
select tests.login('Charlie');
select public.submit_purchase(tests.gid('Lab'), 'personal', 800, 'Beans', gen_random_uuid());
select tests.login('Tess');
select public.submit_deposit(tests.gid('Lab'), 2000, gen_random_uuid(), 'Treasurer float');
select is(tests.cash('Lab'), 2000::bigint, 'the box holds 20.00 again');

select throws_ok(
  $$ select public.record_reimbursement(tests.gid('Lab'), tests.uid('Alice'), 100, gen_random_uuid()) $$,
  'P0001', 'reimbursement_exceeds_credit', 'a settled member cannot be reimbursed again');
select throws_ok(
  $$ select public.record_reimbursement(tests.gid('Lab'), tests.uid('Charlie'), 900, gen_random_uuid()) $$,
  'P0001', 'reimbursement_exceeds_credit', 'a reimbursement cannot exceed the member''s credit of 8.00');
select is(tests.cash('Lab'), 2000::bigint, 'failed reimbursements leave the box untouched');

-- Member-initiated request, paid out later by the treasurer.
select tests.login('Charlie');
select is(public.record_reimbursement(tests.gid('Lab'), null, 500, gen_random_uuid(), 'Please pay me back') ->> 'status',
  'pending', 'a member can request a reimbursement');
select throws_ok(
  $$ select public.record_reimbursement(tests.gid('Lab'), null, 400, gen_random_uuid()) $$,
  'P0001', 'reimbursement_exceeds_credit', 'requests already waiting count against the credit (5.00 + 4.00 > 8.00)');
select throws_ok(
  $$ select public.record_reimbursement(tests.gid('Lab'), tests.uid('Bob'), 100, gen_random_uuid()) $$,
  'P0001', 'forbidden', 'members cannot request reimbursements for others');

select tests.login('Tess');
select public.respond_to_transaction(tests.last_txn('Lab'), true, 'Paid in cash');
select is(tests.balance('Lab', 'Charlie'), -300::bigint, 'the approved request reduces the credit to 3.00');
select is(tests.cash('Lab'), 1500::bigint, 'the box pays out 5.00');

-- The box can never go negative: empty it first.
select public.record_reimbursement(tests.gid('Lab'), tests.uid('Tess'), 1500, gen_random_uuid(), 'Float back');
select throws_ok(
  $$ select public.record_reimbursement(tests.gid('Lab'), tests.uid('Charlie'), 300, gen_random_uuid()) $$,
  'P0001', 'insufficient_cash', 'a reimbursement cannot spend money the box does not hold');

select tests.logout();
select is(tests.ledger_total('Lab'), 0::bigint, 'the ledger sums to zero');

select * from finish();
rollback;
