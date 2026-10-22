-- Cash-box reconciliation and in-app notifications.
begin;
select plan(21);

select tests.make_group('Lab', array['Alice', 'Bob', 'Tess']);
select tests.login('Alice');
select public.set_member_role(tests.gid('Lab'), tests.uid('Tess'), 'treasurer');
select tests.login('Tess');
select public.submit_deposit(tests.gid('Lab'), 1000, gen_random_uuid(), 'Opening float');

-- ---------------------------------------------------------------------------
-- Reconciliation: expected 10.00, counted 9.50.
-- ---------------------------------------------------------------------------
select is((public.get_cash_box(tests.gid('Lab')) ->> 'expected_cents')::bigint, 1000::bigint,
  'the system expects 10.00 in the box');
select throws_ok($$ select public.reconcile_cash_box(tests.gid('Lab'), 950, gen_random_uuid()) $$,
  'P0001', 'note_required', 'a difference needs an explanation');

create temporary table rec as
  select public.reconcile_cash_box(tests.gid('Lab'), 950, gen_random_uuid(), 'Counted twice, 0.50 missing') as result;
grant select on rec to authenticated;
select is(((select result from rec) ->> 'difference_cents')::bigint, -50::bigint, 'the difference is -0.50');
select is(tests.cash('Lab'), 950::bigint, 'an audited adjustment brings the expected cash to the counted 9.50');
select is((select kind::text from public.transactions where id = ((select result from rec) ->> 'adjustment_transaction_id')::uuid),
  'cash_adjustment', 'the correction is a cash adjustment transaction');
select is((select direction from public.transactions
           where id = ((select result from rec) ->> 'adjustment_transaction_id')::uuid), -1::smallint,
  'the adjustment decreases the box');
select is((select sum(amount_cents)::bigint from public.ledger_entries
           where transaction_id = ((select result from rec) ->> 'adjustment_transaction_id')::uuid
             and account = 'adjustments'), 50::bigint, 'the shortfall is booked to the adjustments account');
select is(tests.balance('Lab', 'Tess'), -1000::bigint, 'a cash adjustment never changes member balances');

select is((public.reconcile_cash_box(tests.gid('Lab'), 950, gen_random_uuid()) ->> 'adjustment_transaction_id'), null,
  'a matching count records history without an adjustment');
select is(jsonb_array_length(public.get_cash_box(tests.gid('Lab')) -> 'reconciliations'), 2,
  'reconciliation history is preserved');
select is((public.reconcile_cash_box(tests.gid('Lab'), 1200, gen_random_uuid(), 'Found coins under the machine', false)
           ->> 'adjustment_transaction_id'), null, 'a discrepancy can be recorded without adjusting');
select is(tests.cash('Lab'), 950::bigint, 'recording without adjusting leaves the expected cash unchanged');

select tests.login('Bob');
select throws_ok($$ select public.reconcile_cash_box(tests.gid('Lab'), 0, gen_random_uuid(), 'I counted') $$,
  'P0001', 'forbidden', 'members cannot reconcile the box');

-- ---------------------------------------------------------------------------
-- Notifications
-- ---------------------------------------------------------------------------
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 5);
select public.record_transfer(tests.gid('Lab'), tests.uid('Bob'), tests.uid('Alice'), 100, gen_random_uuid());

select tests.login('Alice');
select is((select count(*)::integer from public.notifications where kind = 'transfer_requested'), 1,
  'the recipient sees the request in their notification centre');
select is((select payload ->> 'actor_name' from public.notifications where kind = 'transfer_requested'), 'Bob',
  'the notification names who sent it');
select is((select (payload ->> 'amount_cents')::bigint from public.notifications where kind = 'transfer_requested'),
  100::bigint, 'the notification carries the amount');
select is(public.mark_notifications_read(), 3,
  'marking all as read updates only the caller''s unread items (two "member joined" and the request)');
select is((select count(*)::integer from public.notifications where read_at is null), 0, 'nothing is unread any more');

-- Preferences are respected.
select public.update_preferences(p_notify_settlements => false);
select tests.login('Bob');
select public.record_transfer(tests.gid('Lab'), tests.uid('Bob'), tests.uid('Alice'), 100, gen_random_uuid());
select is(tests.notification_count('Alice', 'transfer_requested'), 1,
  'no new settlement notification after Alice switched them off');
select is((public.get_pending_actions(tests.gid('Lab')) -> 'counts' ->> 'my_submissions')::integer, 2,
  'pending items stay visible in the to-do list regardless of notification settings');

select tests.login('Alice');
select is((public.get_pending_actions(tests.gid('Lab')) -> 'counts' ->> 'to_review')::integer, 2,
  'the recipient has two payments to confirm');

select * from finish();
rollback;
