-- Scenario 13: a previously approved transaction is reversed, plus audited
-- administrative corrections. History is never edited in place.
begin;
select plan(23);

select tests.make_group('Lab', array['Alice', 'Bob', 'Charlie', 'Tess']);
select tests.login('Alice');
select public.set_member_role(tests.gid('Lab'), tests.uid('Tess'), 'treasurer');

-- Bob's 5.00 deposit is approved, then found to be a mistake.
select tests.login('Bob');
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 10);
select public.submit_deposit(tests.gid('Lab'), 500, gen_random_uuid(), 'Note in the box');
select tests.login('Tess');
select public.respond_to_transaction(tests.last_txn('Lab'), true);
select is(tests.balance('Lab', 'Bob'), -300::bigint, 'before: Bob is owed 3.00');
select is(tests.cash('Lab'), 500::bigint, 'before: the box holds 5.00');

create temporary table t13 as select tests.last_txn('Lab') as deposit_id;
grant select on t13 to authenticated;

select throws_ok($$ select public.reverse_transaction((select deposit_id from t13), 'Mistake', gen_random_uuid()) $$,
  'P0001', 'forbidden', 'S13: treasurers cannot reverse transactions');
select tests.login('Alice');
select throws_ok($$ select public.reverse_transaction((select deposit_id from t13), '', gen_random_uuid()) $$,
  'P0001', 'note_required', 'S13: a reversal needs a reason');
select is(public.reverse_transaction((select deposit_id from t13), 'The note was counterfeit', gen_random_uuid()) ->> 'kind',
  'reversal', 'S13: the administrator reverses the deposit');

select is((select status::text from public.transactions where id = (select deposit_id from t13)), 'reversed',
  'S13: the original stays in the history, marked reversed');
select is((select amount_cents from public.transactions where id = (select deposit_id from t13)), 500::bigint,
  'S13: the original amount is untouched');
select is(tests.balance('Lab', 'Bob'), 200::bigint, 'S13: Bob owes his 2.00 of coffee again');
select is(tests.cash('Lab'), 0::bigint, 'S13: the box no longer counts the 5.00');
select is((select count(*)::integer from public.ledger_entries
           where transaction_id = (select deposit_id from t13)), 2, 'S13: the original ledger entries remain');
select is(tests.notification_count('Bob', 'transaction_reversed'), 1, 'S13: Bob is informed');
select ok(exists (select 1 from public.audit_log where group_id = tests.gid('Lab') and action = 'transaction_reversed'),
  'S13: the reversal is in the audit log');

select throws_ok($$ select public.reverse_transaction((select deposit_id from t13), 'Again', gen_random_uuid()) $$,
  'P0001', 'already_reversed', 'S13: a transaction can only be reversed once');
select throws_ok($$ select public.reverse_transaction(tests.last_txn('Lab'), 'Undo the undo', gen_random_uuid()) $$,
  'P0001', 'cannot_reverse_reversal', 'S13: reversals cannot be reversed');

-- Reversing money that the box no longer holds is refused.
select tests.login('Tess');
select public.submit_deposit(tests.gid('Lab'), 1000, gen_random_uuid());
select tests.login('Charlie');
select public.submit_purchase(tests.gid('Lab'), 'cash_box', 800, 'Beans', gen_random_uuid());
select tests.login('Alice');
select throws_ok(
  format($$ select public.reverse_transaction(%L, 'Wrong amount', gen_random_uuid()) $$,
    (select id from public.transactions where group_id = tests.gid('Lab') and kind = 'deposit' and status = 'posted')),
  'P0001', 'insufficient_cash', 'a deposit that was already spent cannot be reversed without reconciling first');

-- Administrative balance adjustment (e.g. writing off a small debt).
select is(public.record_balance_adjustment(tests.gid('Lab'), tests.uid('Bob'), -1::smallint, 200,
  'Write-off agreed in the group meeting', gen_random_uuid()) ->> 'status', 'posted', 'an administrator writes off Bob''s debt');
select is(tests.balance('Lab', 'Bob'), 0::bigint, 'Bob is settled by the write-off');
select tests.login('Tess');
select throws_ok($$ select public.record_balance_adjustment(tests.gid('Lab'), tests.uid('Bob'), 1::smallint, 100,
  'Charge', gen_random_uuid()) $$, 'P0001', 'forbidden', 'only administrators adjust balances');

-- Even the database owner cannot edit or delete financial history.
select tests.logout();
select throws_ok($$ update public.transactions set amount_cents = 1 where id = (select deposit_id from t13) $$,
  'P0001', 'immutable_transaction', 'amounts of recorded transactions cannot be edited');
select throws_ok($$ update public.ledger_entries set amount_cents = amount_cents + 1 $$,
  'P0001', 'append_only', 'ledger entries cannot be edited');
select throws_ok($$ delete from public.transactions where id = (select deposit_id from t13) $$,
  'P0001', 'append_only', 'transactions cannot be deleted');
select throws_ok(
  format($$ update public.transactions set status = 'pending' where id = %L $$,
    (select id from public.transactions where group_id = tests.gid('Lab') and kind = 'deposit' and status = 'posted')),
  'P0001', 'invalid_transition', 'posted transactions cannot return to pending');

select is(tests.ledger_total('Lab'), 0::bigint, 'the ledger sums to zero');

select * from finish();
rollback;
