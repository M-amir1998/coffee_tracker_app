-- Scenario 15: users from different groups cannot access each other's data.
-- Also: no direct writes for API roles, admin-only data, anonymous access.
begin;
select plan(40);

select tests.make_group('Alpha', array['Alice', 'Bob']);
select tests.make_group('Beta', array['Xavier', 'Yara']);

select tests.login('Alice');
select public.record_coffee(tests.gid('Alpha'), gen_random_uuid(), 2);
select public.submit_purchase(tests.gid('Alpha'), 'personal', 700, 'Beans', gen_random_uuid());
select public.record_transfer(tests.gid('Alpha'), tests.uid('Bob'), tests.uid('Alice'), 100, gen_random_uuid());
select tests.login('Bob');
select public.record_transfer(tests.gid('Alpha'), tests.uid('Bob'), tests.uid('Alice'), 50, gen_random_uuid());

select tests.logout();
create temporary table alpha as
  select tests.gid('Alpha') as group_id,
         (select id from public.transactions where group_id = tests.gid('Alpha') order by created_at limit 1) as txn_id,
         (select id from public.accounting_cycles where group_id = tests.gid('Alpha')) as cycle_id;
grant select on alpha to authenticated, anon;

-- ---------------------------------------------------------------------------
-- Table reads are isolated by RLS.
-- ---------------------------------------------------------------------------
select tests.login('Xavier');
select is((select count(*)::integer from public.groups where id = (select group_id from alpha)), 0, 'S15: groups');
select is((select count(*)::integer from public.group_members where group_id = (select group_id from alpha)), 0,
  'S15: memberships');
select is((select count(*)::integer from public.transactions where group_id = (select group_id from alpha)), 0,
  'S15: transactions');
select is((select count(*)::integer from public.ledger_entries where group_id = (select group_id from alpha)), 0,
  'S15: ledger entries');
select is((select count(*)::integer from public.transaction_events where group_id = (select group_id from alpha)), 0,
  'S15: transaction history');
select is((select count(*)::integer from public.accounting_cycles where group_id = (select group_id from alpha)), 0,
  'S15: accounting cycles');
select is((select count(*)::integer from public.coffee_prices where group_id = (select group_id from alpha)), 0,
  'S15: prices');
select is((select count(*)::integer from public.profiles where id in (tests.uid('Alice'), tests.uid('Bob'))), 0,
  'S15: profiles of other groups'' members');
select is((select count(*)::integer from public.notifications where user_id = tests.uid('Alice')), 0,
  'S15: other people''s notifications');
select is((select count(*)::integer from public.user_preferences where user_id = tests.uid('Alice')), 0,
  'S15: other people''s preferences');
select is((select count(*)::integer from public.audit_log where group_id = (select group_id from alpha)), 0,
  'S15: audit log');
select is((select count(*)::integer from public.invitations where group_id = (select group_id from alpha)), 0,
  'S15: invitations');
select is((select count(*)::integer from public.profiles where id = tests.uid('Yara')), 1,
  'S15: own group members stay visible');

-- ---------------------------------------------------------------------------
-- Every API function checks membership.
-- ---------------------------------------------------------------------------
select throws_ok($$ select public.get_dashboard((select group_id from alpha)) $$, 'P0001', 'not_member', 'S15: dashboard');
select throws_ok($$ select public.get_group_overview((select group_id from alpha)) $$, 'P0001', 'not_member', 'S15: overview');
select throws_ok($$ select * from public.get_member_balances((select group_id from alpha)) $$, 'P0001', 'not_member',
  'S15: balances');
select throws_ok($$ select * from public.get_activity((select group_id from alpha)) $$, 'P0001', 'not_member', 'S15: activity');
select throws_ok($$ select public.get_transaction((select txn_id from alpha)) $$, 'P0001', 'not_member', 'S15: transaction');
select throws_ok($$ select public.get_leaderboard((select group_id from alpha), 'all_time') $$, 'P0001', 'not_member',
  'S15: leaderboard');
select throws_ok($$ select public.get_analytics((select group_id from alpha), current_date - 7, current_date) $$,
  'P0001', 'not_member', 'S15: analytics');
select throws_ok($$ select public.get_cycle_report((select cycle_id from alpha)) $$, 'P0001', 'not_member', 'S15: reports');
select throws_ok($$ select public.get_settlement_inputs((select group_id from alpha)) $$, 'P0001', 'not_member',
  'S15: settlement inputs');
select throws_ok($$ select public.record_coffee((select group_id from alpha), gen_random_uuid()) $$, 'P0001', 'not_member',
  'S15: recording coffee');
select throws_ok($$ select public.submit_deposit((select group_id from alpha), 100, gen_random_uuid()) $$, 'P0001',
  'not_member', 'S15: deposits');
select throws_ok($$ select public.respond_to_transaction(
    (select id from public.transactions where status = 'pending' limit 1), true) $$,
  'P0001', 'not_found', 'S15: cannot even locate a pending transaction of another group');

-- ---------------------------------------------------------------------------
-- API roles cannot write tables directly, not even in their own group.
-- ---------------------------------------------------------------------------
select tests.login('Alice');
select throws_ok($$ insert into public.transactions (group_id, cycle_id, kind, status, amount_cents, member_id,
    initiated_by, idempotency_key)
  values ((select group_id from alpha), (select cycle_id from alpha), 'deposit', 'posted', 100000, tests.uid('Alice'),
    tests.uid('Alice'), gen_random_uuid()) $$, '42501', null, 'direct inserts into transactions are denied');
select throws_ok($$ update public.transactions set amount_cents = 1 $$, '42501', null, 'direct updates are denied');
select throws_ok($$ delete from public.ledger_entries $$, '42501', null, 'direct deletes are denied');
select throws_ok($$ insert into public.ledger_entries (transaction_id, group_id, cycle_id, account, member_id, category,
    amount_cents) values ((select txn_id from alpha), (select group_id from alpha), (select cycle_id from alpha),
    'member', tests.uid('Alice'), 'deposit', -100000) $$, '42501', null, 'ledger entries cannot be forged');
select throws_ok($$ update public.group_members set role = 'admin' $$, '42501', null,
  'members cannot promote themselves');
select throws_ok($$ update public.profiles set display_name = 'Hacker' where id = tests.uid('Bob') $$, '42501', null,
  'profiles change only through the API');

-- ---------------------------------------------------------------------------
-- Role-restricted data inside a group.
-- ---------------------------------------------------------------------------
select public.create_invitation((select group_id from alpha));
select is((select count(*)::integer from public.invitations where group_id = (select group_id from alpha)), 2,
  'administrators see invitations (the one used by Bob and the new one)');
select is((select count(*)::integer from public.audit_log where group_id = (select group_id from alpha)) > 0, true,
  'administrators see the audit log');
select tests.login('Bob');
select is((select count(*)::integer from public.invitations where group_id = (select group_id from alpha)), 0,
  'members do not see invitation codes');
select is((select count(*)::integer from public.audit_log where group_id = (select group_id from alpha)), 0,
  'members do not see the audit log');
select throws_ok($$ select * from public.get_audit_log((select group_id from alpha)) $$, 'P0001', 'forbidden',
  'members cannot call the audit API');
select throws_ok($$ select * from public.export_transactions((select group_id from alpha)) $$, 'P0001', 'forbidden',
  'members cannot export');

-- ---------------------------------------------------------------------------
-- Anonymous users get nothing.
-- ---------------------------------------------------------------------------
select tests.logout();
set local role anon;
select throws_ok($$ select count(*) from public.transactions $$, '42501', null, 'anon cannot read tables');
select throws_ok($$ select public.get_my_groups() $$, '42501', null, 'anon cannot call the API');
select throws_ok($$ select public.join_group('ABCDEFGH') $$, '42501', null, 'anon cannot join groups');
reset role;

select * from finish();
rollback;
