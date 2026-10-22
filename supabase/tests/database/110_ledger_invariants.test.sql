-- Ledger invariants on a realistic mixed history, with every figure derived by
-- hand in the comments. Proves that debts, credits, net position, cash and
-- pending money are distinct and consistent.
begin;
select plan(31);

-- Every posting rule balances, for both adjustment directions.
select is((select count(*)::integer from unnest(enum_range(null::public.txn_kind)) k, (values (1), (-1)) d (direction)
           where k <> 'reversal'
             and (select coalesce(sum(r.amount_cents), 0) from private.posting_rule(k, 123, gen_random_uuid(),
                    gen_random_uuid(), d.direction::smallint) r) <> 0), 0,
  'every posting rule sums to zero');
select is((select count(*)::integer from unnest(enum_range(null::public.txn_kind)) k
           where k <> 'reversal'
             and not exists (select 1 from private.posting_rule(k, 1, gen_random_uuid(), gen_random_uuid(), 1::smallint))),
  0, 'every transaction kind has a posting rule');

select tests.make_group('Lab', array['Alice', 'Bob', 'Charlie', 'Dana', 'Tess']);
select tests.login('Alice');
select public.set_member_role(tests.gid('Lab'), tests.uid('Tess'), 'treasurer');

-- 1. Coffees: Alice 10 (2.00), Bob 15 (3.00), Charlie 30 (6.00), Dana 5 (1.00).
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 10);
select tests.login('Bob');
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 15);
-- 2. Bob buys beans with his own money: 12.00.
select public.submit_purchase(tests.gid('Lab'), 'personal', 1200, 'Beans', gen_random_uuid());
select tests.login('Charlie');
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 20);
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 10);
-- 4. Charlie deposits 4.00 (confirmed below).
select public.submit_deposit(tests.gid('Lab'), 400, gen_random_uuid());
select tests.login('Dana');
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 5);
-- 3. Tess (treasurer) deposits 5.00 and confirms Charlie's deposit.
select tests.login('Tess');
select public.submit_deposit(tests.gid('Lab'), 500, gen_random_uuid());
select public.respond_to_transaction(
  (select id from public.transactions where group_id = tests.gid('Lab') and status = 'pending'), true);
-- 5. Dana buys beans with 3.00 from the box.
select tests.login('Dana');
select public.submit_purchase(tests.gid('Lab'), 'cash_box', 300, 'Beans from the box', gen_random_uuid());
-- 6. Alice pays Bob 2.00 directly; Bob confirms.
select tests.login('Alice');
select public.record_transfer(tests.gid('Lab'), tests.uid('Alice'), tests.uid('Bob'), 200, gen_random_uuid());
select tests.login('Bob');
select public.respond_to_transaction(tests.last_txn('Lab'), true);
-- 7. Tess reimburses Bob 5.00 from the box.
select tests.login('Tess');
select public.record_reimbursement(tests.gid('Lab'), tests.uid('Bob'), 500, gen_random_uuid());
-- 8. Dana deposits 1.00, still unverified.
select tests.login('Dana');
select public.submit_deposit(tests.gid('Lab'), 100, gen_random_uuid());
-- 9. Tess counts 0.90 instead of the expected 1.00.
select tests.login('Tess');
select public.reconcile_cash_box(tests.gid('Lab'), 90, gen_random_uuid(), 'Ten cents missing');
-- 10. Alice charges Charlie 0.50 for a broken cup.
select tests.login('Alice');
select public.record_balance_adjustment(tests.gid('Lab'), tests.uid('Charlie'), 1::smallint, 50, 'Broken cup',
  gen_random_uuid());

-- Member balances
select is(tests.balance('Lab', 'Alice'), 0::bigint, 'Alice: 2.00 coffee - 2.00 paid to Bob = 0.00');
select is(tests.balance('Lab', 'Bob'), -200::bigint,
  'Bob: 3.00 coffee - 12.00 beans + 2.00 received + 5.00 reimbursed = -2.00');
select is(tests.balance('Lab', 'Charlie'), 250::bigint, 'Charlie: 6.00 coffee - 4.00 deposit + 0.50 charge = 2.50');
select is(tests.balance('Lab', 'Dana'), 100::bigint, 'Dana: 1.00 coffee; box purchase and pending deposit do not count');
select is(tests.balance('Lab', 'Tess'), -500::bigint, 'Tess: deposited 5.00');
select is(tests.cash('Lab'), 90::bigint, 'cash: 5.00 + 4.00 - 3.00 - 5.00 - 0.10 = 0.90');

-- Group overview keeps the different quantities apart.
create temporary table ov as select public.get_group_overview(tests.gid('Lab')) as o;
grant select on ov to authenticated;
select is(((select o from ov) ->> 'coffees')::integer, 60, 'overview: 60 coffees');
select is(((select o from ov) ->> 'consumption_cents')::bigint, 1200::bigint, 'overview: consumption 12.00');
select is(((select o from ov) ->> 'deposits_cents')::bigint, 900::bigint, 'overview: confirmed deposits 9.00');
select is(((select o from ov) ->> 'personal_purchases_cents')::bigint, 1200::bigint, 'overview: personal purchases 12.00');
select is(((select o from ov) ->> 'box_purchases_cents')::bigint, 300::bigint, 'overview: box purchases 3.00');
select is(((select o from ov) ->> 'cash_reimbursements_cents')::bigint, 500::bigint, 'overview: reimbursements 5.00');
select is(((select o from ov) ->> 'cash_adjustments_cents')::bigint, -10::bigint, 'overview: cash adjustments -0.10');
select is(((select o from ov) ->> 'cash_box_cents')::bigint, 90::bigint, 'overview: cash in the box 0.90');
select is(((select o from ov) ->> 'debts_cents')::bigint, 350::bigint, 'overview: members owe 3.50 (Charlie + Dana)');
select is(((select o from ov) ->> 'credits_cents')::bigint, 700::bigint, 'overview: the group owes 7.00 (Bob + Tess)');
select is(((select o from ov) ->> 'net_position_cents')::bigint, -350::bigint, 'overview: net member position -3.50');
select is(((select o from ov) -> 'pending' ->> 'deposits_cents')::bigint, 100::bigint,
  'overview: 1.00 of unverified deposits is reported separately');
select is(((select o from ov) ->> 'members_owing')::integer, 2, 'overview: two members owe money');
select is((select contributions_cents from public.get_member_balances(tests.gid('Lab')) where user_id = tests.uid('Bob')),
  1200::bigint, 'balances table: contributions = deposits + personal purchases');

-- Global accounting identity: members + cash = consumption - supplies - adjustments.
create temporary table fig as select (public.verify_ledger_integrity(tests.gid('Lab'))) as r;
grant select on fig to authenticated;
select is(((select r from fig) ->> 'ok')::boolean, true, 'all integrity checks pass');
select is(((select r from fig) -> 'figures' ->> 'consumption_cents')::bigint, 1200::bigint, 'figures: consumption 12.00');
select is(((select r from fig) -> 'figures' ->> 'supplies_cents')::bigint, 1500::bigint, 'figures: supplies 15.00');
select is(((select r from fig) -> 'figures' ->> 'adjustments_cents')::bigint, -40::bigint,
  'figures: adjustments +0.10 shortfall - 0.50 charge = -0.40');
select is(((select r from fig) -> 'figures' ->> 'members_net_cents')::bigint
          + ((select r from fig) -> 'figures' ->> 'cash_box_cents')::bigint,
          ((select r from fig) -> 'figures' ->> 'consumption_cents')::bigint
          - ((select r from fig) -> 'figures' ->> 'supplies_cents')::bigint
          - ((select r from fig) -> 'figures' ->> 'adjustments_cents')::bigint,
  'identity: -3.50 + 0.90 = 12.00 - 15.00 + 0.40');

-- The identity survives closing the cycle.
select public.close_cycle(tests.gid('Lab'),
  (select id from public.accounting_cycles where group_id = tests.gid('Lab') and status = 'open'), 'Cycle 1', 'Cycle 2');
select tests.logout();
select is((select sum(closing_cents)::bigint from public.cycle_member_balances b
           join public.accounting_cycles c on c.id = b.cycle_id where c.group_id = tests.gid('Lab')), -350::bigint,
  'snapshot: closing balances sum to the net position');
select is((select closing_cash_cents from public.cycle_cash_snapshots s
           join public.accounting_cycles c on c.id = s.cycle_id where c.group_id = tests.gid('Lab')), 90::bigint,
  'snapshot: closing cash 0.90');
set constraints all immediate;
select pass('deferred balance checks pass for every transaction');
select is(tests.ledger_total('Lab'), 0::bigint, 'the whole ledger sums to zero');

select * from finish();
rollback;
