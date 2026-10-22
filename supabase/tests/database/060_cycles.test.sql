-- Scenarios 11 and 12: closing cycles with everyone settled and with balances
-- carried forward. Closed cycles are immutable; history is never truncated.
begin;
select plan(33);

select tests.make_group('Lab', array['Alice', 'Bob', 'Charlie', 'Tess']);
select tests.login('Alice');
select public.set_member_role(tests.gid('Lab'), tests.uid('Tess'), 'treasurer');

create function pg_temp.cycle(p_name text) returns uuid language sql as $$
  select id from public.accounting_cycles where group_id = tests.gid('Lab') and name = p_name
$$;
grant execute on function pg_temp.cycle(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Scenario 11: a cycle closes with everyone settled.
-- ---------------------------------------------------------------------------
select tests.login('Bob');
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 5);
select public.submit_deposit(tests.gid('Lab'), 100, gen_random_uuid());
select tests.login('Charlie');
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 5);
select tests.login('Tess');
select public.respond_to_transaction(
  (select id from public.transactions where group_id = tests.gid('Lab') and kind = 'deposit'), true);
select public.submit_deposit(tests.gid('Lab'), 100, gen_random_uuid(), 'Handed over', tests.uid('Charlie'));

select tests.login('Bob');
select throws_ok($$ select public.close_cycle(tests.gid('Lab'), pg_temp.cycle('Cycle 1'), 'Cycle 1', 'Cycle 2') $$,
  'P0001', 'forbidden', 'only administrators close cycles');
select tests.login('Alice');
select throws_ok($$ select public.close_cycle(tests.gid('Lab'), pg_temp.cycle('Cycle 1'), 'cycle one', 'Cycle 2') $$,
  'P0001', 'confirmation_mismatch', 'closing requires typing the exact cycle name');
select lives_ok($$ select public.close_cycle(tests.gid('Lab'), pg_temp.cycle('Cycle 1'), 'Cycle 1', 'Cycle 2',
  'Everyone paid') $$, 'S11: the administrator closes the cycle');

select is((select status::text from public.accounting_cycles where id = pg_temp.cycle('Cycle 1')), 'closed',
  'S11: the old cycle is closed');
select is((select status::text from public.accounting_cycles where id = pg_temp.cycle('Cycle 2')), 'open',
  'S11: the next cycle is open');
select is((select count(*)::integer from public.cycle_member_balances
           where cycle_id = pg_temp.cycle('Cycle 1') and closing_cents <> 0), 0,
  'S11: every closing balance is zero');
select is((select coalesce(sum(abs(opening_cents)), 0)::bigint from public.get_member_balances(tests.gid('Lab'))), 0::bigint,
  'S11: the new cycle starts with zero personal balances');
select is((select closing_cash_cents from public.cycle_cash_snapshots where cycle_id = pg_temp.cycle('Cycle 1')),
  200::bigint, 'S11: 2.00 of physical cash is recorded at closing');
select is((public.get_group_overview(tests.gid('Lab')) ->> 'opening_cash_cents')::bigint, 200::bigint,
  'S11: the cash is carried into the new cycle');
select is(jsonb_array_length(public.get_leaderboard(tests.gid('Lab'), 'cycle') -> 'rows'), 0,
  'S11: the cycle leaderboard starts empty');
select is((public.get_leaderboard(tests.gid('Lab'), 'all_time') ->> 'total_coffees')::integer, 10,
  'S11: all-time coffee statistics are preserved');
select is(tests.notification_count('Bob', 'cycle_closed'), 1, 'S11: members are told about the closing');

-- ---------------------------------------------------------------------------
-- Scenario 12: a cycle closes with balances carried forward.
-- ---------------------------------------------------------------------------
select tests.login('Charlie');
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 3);
select public.submit_deposit(tests.gid('Lab'), 50, gen_random_uuid(), 'Not yet verified');
select tests.login('Bob');
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 2);
select public.submit_purchase(tests.gid('Lab'), 'personal', 500, 'Beans', gen_random_uuid());

select tests.login('Alice');
select public.close_cycle(tests.gid('Lab'), pg_temp.cycle('Cycle 2'), 'Cycle 2', 'Cycle 3');

select is((select closing_cents from public.cycle_member_balances
           where cycle_id = pg_temp.cycle('Cycle 2') and user_id = tests.uid('Charlie')), 60::bigint,
  'S12: Charlie closes owing 0.60');
select is((select closing_cents from public.cycle_member_balances
           where cycle_id = pg_temp.cycle('Cycle 2') and user_id = tests.uid('Bob')), -460::bigint,
  'S12: Bob closes being owed 4.60 (0.40 coffee - 5.00 beans)');
select is((select personal_purchases_cents from public.cycle_member_balances
           where cycle_id = pg_temp.cycle('Cycle 2') and user_id = tests.uid('Bob')), 500::bigint,
  'S12: the snapshot keeps the breakdown');
select is((select opening_cents from public.get_member_balances(tests.gid('Lab')) where user_id = tests.uid('Charlie')),
  60::bigint, 'S12: Charlie''s debt is carried forward as opening balance');
select is((select opening_cents from public.get_member_balances(tests.gid('Lab')) where user_id = tests.uid('Bob')),
  -460::bigint, 'S12: Bob''s credit is carried forward as opening balance');
select is((select net_cents from public.get_member_balances(tests.gid('Lab')) where user_id = tests.uid('Bob')),
  -460::bigint, 'S12: closing a cycle never changes anyone''s balance');
select is((select closing_cash_cents from public.cycle_cash_snapshots where cycle_id = pg_temp.cycle('Cycle 2')),
  200::bigint, 'S12: the unverified deposit is not counted as cash at closing');

select is((select cycle_id from public.transactions where group_id = tests.gid('Lab') and status = 'pending'),
  pg_temp.cycle('Cycle 3'), 'S12: the pending deposit moves to the new cycle');
select ok(exists (select 1 from public.transaction_events e
                  join public.transactions t on t.id = e.transaction_id
                  where t.status = 'pending' and t.group_id = tests.gid('Lab') and e.note = 'Carried forward to Cycle 3'),
  'S12: the carry-forward is recorded in the transaction history');

select tests.login('Tess');
select public.respond_to_transaction(
  (select id from public.transactions where group_id = tests.gid('Lab') and status = 'pending'), true);
select is((select net_cents from public.get_member_balances(tests.gid('Lab')) where user_id = tests.uid('Charlie')),
  10::bigint, 'S12: confirming the carried deposit in the new cycle leaves Charlie owing 0.10');
select is((select cycle_id from public.transactions where group_id = tests.gid('Lab') and kind = 'deposit'
           order by created_at desc limit 1), pg_temp.cycle('Cycle 3'), 'S12: it is booked in the open cycle');

select is((public.get_cycle_report(pg_temp.cycle('Cycle 2')) ->> 'is_final')::boolean, true,
  'historical cycles remain accessible as final reports');
select is((select (m ->> 'closing_cents')::bigint from jsonb_array_elements(
             public.get_cycle_report(pg_temp.cycle('Cycle 2')) -> 'members') m
           where m ->> 'display_name' = 'Charlie'), 60::bigint, 'the report shows the frozen closing balance');

-- ---------------------------------------------------------------------------
-- Closed periods are protected.
-- ---------------------------------------------------------------------------
select tests.login('Alice');
select throws_ok($$ select public.close_cycle(tests.gid('Lab'), pg_temp.cycle('Cycle 2'), 'Cycle 2', 'Again') $$,
  'P0001', 'stale_cycle', 'a closed cycle cannot be closed twice');
select throws_ok($$ select public.close_cycle(tests.gid('Lab'), pg_temp.cycle('Cycle 3'), 'Cycle 3', 'Cycle 3') $$,
  'P0001', 'invalid_name', 'the next cycle needs a new name');

select tests.login('Bob');
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 1);
select tests.login('Alice');
select public.close_cycle(tests.gid('Lab'), pg_temp.cycle('Cycle 3'), 'Cycle 3', 'Cycle 4');
select tests.login('Bob');
select throws_ok(
  format($$ select public.undo_coffee(%L) $$,
    (select id from public.transactions where group_id = tests.gid('Lab') and kind = 'coffee'
     order by created_at desc limit 1)),
  'P0001', 'cycle_closed', 'coffees from a closed cycle cannot be undone by members');

select tests.logout();
select throws_ok(format($$ update public.accounting_cycles set close_note = 'edited' where id = %L $$,
  pg_temp.cycle('Cycle 1')), 'P0001', 'cycle_closed', 'closed cycles cannot be edited, even by the database owner');
select throws_ok(format($$ update public.transactions set cycle_id = %L where kind = 'coffee' and group_id = %L $$,
  pg_temp.cycle('Cycle 4'), tests.gid('Lab')), 'P0001', 'immutable_transaction', 'posted transactions never move to another cycle');
set constraints all immediate; -- flush the deferred balance checks first
select throws_ok($$ truncate public.transactions cascade $$, 'P0001', 'append_only',
  'balances are never reset by truncating history');
select throws_ok($$ delete from public.ledger_entries $$, 'P0001', 'append_only', 'ledger entries cannot be deleted');

select tests.login('Alice');
select is((public.verify_ledger_integrity(tests.gid('Lab')) ->> 'ok')::boolean, true,
  'all ledger invariants hold after three closings');

select * from finish();
rollback;
