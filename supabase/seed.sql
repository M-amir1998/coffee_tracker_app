-- =============================================================================
-- Coffee Tracker — demo data for LOCAL DEVELOPMENT ONLY
--
-- Runs automatically on `supabase db reset` (local stack). It is never applied
-- to a hosted project by `supabase db push`. All demo accounts use the
-- password  coffee-demo-1  and confirmed emails such as alice@example.com.
--
-- Data goes through the same ledger engine as the app (private.insert_
-- transaction, post_existing, close_cycle_internal), so every accounting
-- invariant holds. Dates are relative to "now" so that week/month statistics
-- always have data.
-- =============================================================================

create function pg_temp.seed_user(p_email text, p_name text) returns uuid
language plpgsql
as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change,
    email_change_token_current, phone_change, phone_change_token, reauthentication_token)
  values (
    '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', p_email,
    extensions.crypt('coffee-demo-1', extensions.gen_salt('bf')), now(),
    '{"provider": "email", "providers": ["email"]}', jsonb_build_object('display_name', p_name),
    now() - interval '60 days', now(), '', '', '', '', '', '', '', '');
  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), v_id, v_id::text,
    jsonb_build_object('sub', v_id::text, 'email', p_email, 'email_verified', true), 'email', now(), now(), now());
  return v_id;
end;
$$;

-- Local time in the group's time zone.
create function pg_temp.at(p_day date, p_time time) returns timestamptz
language sql
immutable
as $$ select (p_day + p_time) at time zone 'Europe/Madrid' $$;

create function pg_temp.coffee(p_group uuid, p_user uuid, p_at timestamptz, p_quantity integer default 1) returns void
language plpgsql
as $$
begin
  perform private.insert_transaction(p_group, 'coffee', 'posted', (20 * p_quantity)::bigint, p_user, null, p_user,
    gen_random_uuid(), p_occurred_at => p_at, p_quantity => p_quantity, p_unit_price => 20, p_at => p_at);
end;
$$;

do $$
declare
  v_alice uuid := pg_temp.seed_user('alice@example.com', 'Alice');
  v_bob uuid := pg_temp.seed_user('bob@example.com', 'Bob');
  v_charlie uuid := pg_temp.seed_user('charlie@example.com', 'Charlie');
  v_diana uuid := pg_temp.seed_user('diana@example.com', 'Diana');
  v_emma uuid := pg_temp.seed_user('emma@example.com', 'Emma');
  v_group uuid := gen_random_uuid();
  v_start date := (now() at time zone 'Europe/Madrid')::date - 42;
  v_switch date := (now() at time zone 'Europe/Madrid')::date - 14;
  v_today date := (now() at time zone 'Europe/Madrid')::date;
  v_cycle1 uuid := gen_random_uuid();
  v_cycle2 uuid;
  v_day date;
  v_txn public.transactions;
  v_now timestamptz := now() - interval '20 minutes';
begin
  perform setseed(0.42);

  -- Group, members, price and first cycle (what create_group does, back-dated).
  insert into public.groups (id, name, timezone, created_by, created_at)
  values (v_group, 'Demo Research Lab', 'Europe/Madrid', v_alice, pg_temp.at(v_start, '07:30'));
  insert into public.group_members (group_id, user_id, role, joined_at) values
    (v_group, v_alice, 'admin', pg_temp.at(v_start, '07:30')),
    (v_group, v_bob, 'treasurer', pg_temp.at(v_start, '08:30')),
    (v_group, v_charlie, 'member', pg_temp.at(v_start, '09:00')),
    (v_group, v_emma, 'member', pg_temp.at(v_start + 1, '10:00'));
  insert into public.coffee_prices (group_id, price_cents, effective_from, created_by)
  values (v_group, 20, pg_temp.at(v_start, '07:30'), v_alice);
  insert into public.accounting_cycles (id, group_id, sequence_no, name, opened_at, opened_by)
  values (v_cycle1, v_group, 1, initcap(to_char(v_start, 'FMMonth YYYY')), pg_temp.at(v_start, '07:30'), v_alice);
  insert into public.invitations (group_id, code, role, created_by, created_at, expires_at)
  values (v_group, 'LABCAFE2', 'member', v_alice, now() - interval '1 day', now() + interval '30 days');

  -- -------------------------------------------------------------------------
  -- Cycle 1: four weeks. Bob is the heavy drinker, Charlie the night owl.
  -- -------------------------------------------------------------------------
  v_day := v_start;
  while v_day < v_switch loop
    if extract(isodow from v_day) < 6 then
      perform pg_temp.coffee(v_group, v_alice, pg_temp.at(v_day, '07:45'));
      if random() < 0.7 then perform pg_temp.coffee(v_group, v_alice, pg_temp.at(v_day, '14:10')); end if;
      perform pg_temp.coffee(v_group, v_bob, pg_temp.at(v_day, '09:05'));
      perform pg_temp.coffee(v_group, v_bob, pg_temp.at(v_day, '11:30'));
      if random() < 0.8 then perform pg_temp.coffee(v_group, v_bob, pg_temp.at(v_day, '16:00')); end if;
      if random() < 0.8 then perform pg_temp.coffee(v_group, v_charlie, pg_temp.at(v_day, '10:20')); end if;
      if random() < 0.3 then perform pg_temp.coffee(v_group, v_charlie, pg_temp.at(v_day, '20:40')); end if;
      if v_day > v_start and random() < 0.6 then perform pg_temp.coffee(v_group, v_emma, pg_temp.at(v_day, '13:15')); end if;
    end if;

    -- Money events of the first cycle.
    if v_day = v_start + 1 then
      perform private.insert_transaction(v_group, 'deposit', 'posted', 2000, v_bob, null, v_bob, gen_random_uuid(),
        p_description => 'Opening float for the box', p_at => pg_temp.at(v_day, '09:30'));
    elsif v_day = v_start + 4 then
      perform private.insert_transaction(v_group, 'purchase_personal', 'posted', 1850, v_alice, null, v_alice,
        gen_random_uuid(), p_description => '1 kg espresso beans', p_occurred_at => pg_temp.at(v_day, '18:00'),
        p_at => pg_temp.at(v_day, '18:05'));
    elsif v_day = v_start + 8 then
      v_txn := private.insert_transaction(v_group, 'deposit', 'pending', 1000, v_charlie, null, v_charlie,
        gen_random_uuid(), p_description => 'Coins in the box', p_at => pg_temp.at(v_day, '10:25'));
      perform private.post_existing(v_txn.id, v_bob, 'Counted and confirmed', pg_temp.at(v_day, '12:00'));
    elsif v_day = v_start + 11 then
      perform private.insert_transaction(v_group, 'purchase_box', 'posted', 1500, v_bob, null, v_bob,
        gen_random_uuid(), p_description => 'Beans paid from the box', p_at => pg_temp.at(v_day, '17:30'));
    elsif v_day = v_start + 15 then
      v_txn := private.insert_transaction(v_group, 'transfer', 'pending', 500, v_emma, v_alice, v_emma,
        gen_random_uuid(), p_description => 'Cash in the kitchen', p_at => pg_temp.at(v_day, '13:20'));
      perform private.post_existing(v_txn.id, v_alice, null, pg_temp.at(v_day, '15:00'));
    elsif v_day = v_start + 21 then
      perform private.insert_transaction(v_group, 'reimbursement', 'posted', 600, v_alice, null, v_bob,
        gen_random_uuid(), p_description => 'Part of the bean money', p_at => pg_temp.at(v_day, '12:10'));
    elsif v_day = v_start + 25 then
      insert into public.cash_reconciliations (group_id, cycle_id, expected_cents, counted_cents, idempotency_key,
        created_by, created_at)
      values (v_group, v_cycle1, private.cash_balance(v_group), private.cash_balance(v_group), gen_random_uuid(), v_bob,
        pg_temp.at(v_day, '17:00'));
    end if;
    v_day := v_day + 1;
  end loop;

  v_cycle2 := private.close_cycle_internal(v_group, v_cycle1, v_alice, initcap(to_char(v_switch, 'FMMonth YYYY'))
    || case when to_char(v_switch, 'MM') = to_char(v_start, 'MM') then ' (2)' else '' end,
    'Monthly closing', pg_temp.at(v_switch, '07:00'));

  -- Diana joins in the second cycle; her balance starts at zero.
  insert into public.group_members (group_id, user_id, role, joined_at)
  values (v_group, v_diana, 'member', pg_temp.at(v_switch, '09:00'));

  -- -------------------------------------------------------------------------
  -- Cycle 2: the current two weeks. Emma takes the lead this week.
  -- -------------------------------------------------------------------------
  v_day := v_switch;
  while v_day <= v_today loop
    if extract(isodow from v_day) < 6 then
      if pg_temp.at(v_day, '07:50') < v_now then perform pg_temp.coffee(v_group, v_alice, pg_temp.at(v_day, '07:50')); end if;
      if pg_temp.at(v_day, '09:10') < v_now then perform pg_temp.coffee(v_group, v_bob, pg_temp.at(v_day, '09:10')); end if;
      if pg_temp.at(v_day, '10:30') < v_now and random() < 0.7 then
        perform pg_temp.coffee(v_group, v_charlie, pg_temp.at(v_day, '10:30'));
      end if;
      if pg_temp.at(v_day, '11:00') < v_now then
        perform pg_temp.coffee(v_group, v_emma, pg_temp.at(v_day, '11:00'), case when v_day > v_today - 7 then 2 else 1 end);
      end if;
      if pg_temp.at(v_day, '15:30') < v_now and random() < 0.6 then
        perform pg_temp.coffee(v_group, v_diana, pg_temp.at(v_day, '15:30'));
      end if;
    end if;

    if v_day = v_switch + 1 then
      perform private.insert_transaction(v_group, 'purchase_personal', 'posted', 1200, v_charlie, null, v_charlie,
        gen_random_uuid(), p_description => 'Colombian beans', p_at => pg_temp.at(v_day, '18:00'));
    elsif v_day = v_switch + 3 then
      perform private.insert_transaction(v_group, 'deposit', 'posted', 1500, v_bob, null, v_bob, gen_random_uuid(),
        p_at => pg_temp.at(v_day, '09:20'));
    elsif v_day = v_switch + 7 then
      perform private.insert_transaction(v_group, 'purchase_box', 'posted', 990, v_emma, null, v_emma,
        gen_random_uuid(), p_description => 'Decaf for the afternoon', p_at => pg_temp.at(v_day, '16:40'));
      v_txn := private.insert_transaction(v_group, 'deposit', 'pending', 5000, v_emma, null, v_emma, gen_random_uuid(),
        p_description => 'Typed 50 instead of 5', p_at => pg_temp.at(v_day, '16:45'));
      perform private.change_status(v_txn.id, 'rejected', v_bob, 'The box only had a 5 euro note');
    end if;
    v_day := v_day + 1;
  end loop;

  -- Open items waiting for decisions (visible on the dashboards).
  v_txn := private.insert_transaction(v_group, 'deposit', 'pending', 500, v_diana, null, v_diana, gen_random_uuid(),
    p_description => 'First contribution', p_at => v_now - interval '2 hours');
  perform private.notify(v_bob, v_group, 'deposit_pending', v_txn.id, private.txn_payload(v_txn), v_diana);
  perform private.notify(v_alice, v_group, 'deposit_pending', v_txn.id, private.txn_payload(v_txn), v_diana);
  v_txn := private.insert_transaction(v_group, 'transfer', 'pending', 300, v_emma, v_bob, v_emma,
    gen_random_uuid(), p_description => 'For last week', p_at => v_now - interval '90 minutes');
  perform private.notify(v_bob, v_group, 'transfer_requested', v_txn.id, private.txn_payload(v_txn), v_emma);
  -- Charlie bought beans in both cycles and is always owed more than 11.80 here,
  -- so the request is valid and the box (about 14.10) can pay it.
  v_txn := private.insert_transaction(v_group, 'reimbursement', 'pending', 400, v_charlie, null, v_charlie,
    gen_random_uuid(), p_description => 'Part of the Colombian beans', p_at => v_now - interval '1 hour');
  perform private.notify(v_bob, v_group, 'reimbursement_requested', v_txn.id, private.txn_payload(v_txn), v_charlie);
  perform private.notify(v_alice, v_group, 'reimbursement_requested', v_txn.id, private.txn_payload(v_txn), v_charlie);

  perform private.audit(v_group, v_alice, 'group_created', 'group', v_group::text, '{"seed": true}'::jsonb);
end;
$$;
