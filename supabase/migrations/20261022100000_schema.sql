-- =============================================================================
-- Coffee Tracker — schema
--
-- Accounting model (see docs/accounting/ACCOUNTING.md):
--   * Every balance-changing event is a row in public.transactions.
--   * Posted transactions produce double-entry rows in public.ledger_entries
--     that always sum to zero. Pending/rejected/cancelled transactions have no
--     ledger entries and therefore never affect balances.
--   * Money is stored as integer cents (bigint). No floating point anywhere.
--   * Financial rows are append-only: corrections are compensating reversals.
-- =============================================================================

create schema if not exists private;
revoke all on schema private from public;
comment on schema private is
  'Internal helpers. Not exposed through the Data API. Only RLS helper functions are executable by API roles.';

-- -----------------------------------------------------------------------------
-- Enumerations
-- -----------------------------------------------------------------------------

create type public.member_role as enum ('member', 'treasurer', 'admin');
create type public.membership_status as enum ('active', 'left', 'removed');
create type public.cycle_status as enum ('open', 'closed');

create type public.txn_kind as enum (
  'coffee',              -- consumption charged to a member
  'deposit',             -- member puts cash into the physical box
  'purchase_personal',   -- member buys beans with their own money
  'purchase_box',        -- beans bought with money taken from the box
  'transfer',            -- member pays another member directly
  'reimbursement',       -- treasurer pays a member from the box
  'cash_adjustment',     -- reconciliation correction of the box
  'balance_adjustment',  -- administrative correction of a member balance
  'reversal'             -- compensating entry that cancels a posted transaction
);

create type public.txn_status as enum ('pending', 'posted', 'rejected', 'cancelled', 'disputed', 'reversed');

create type public.ledger_account as enum (
  'member',       -- per-member receivable: positive = member owes the group
  'cash_box',     -- physical cash in the box
  'consumption',  -- income from coffees consumed (credit side)
  'supplies',     -- coffee beans and supplies bought (debit side)
  'adjustments'   -- corrections, discrepancies and write-offs
);

create type public.entry_category as enum (
  'consumption', 'deposit', 'purchase_personal', 'purchase_box', 'transfer_out',
  'transfer_in', 'reimbursement', 'cash_adjustment', 'balance_adjustment'
);

-- -----------------------------------------------------------------------------
-- Profiles and preferences
-- -----------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key,
  display_name text not null,
  avatar_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint profiles_display_name_length check (char_length(btrim(display_name)) between 1 and 40),
  constraint profiles_avatar_path_owner check (avatar_path is null or avatar_path like id::text || '/%')
);
comment on table public.profiles is
  'Public profile of an account (display name only, never the email). Deliberately not foreign-keyed to '
  'auth.users: when an account is deleted the profile is anonymised so the financial history stays intact.';

create table public.user_preferences (
  user_id uuid primary key references public.profiles (id),
  theme text not null default 'system',
  locale text not null default 'system',
  show_on_leaderboard boolean not null default true,
  gamification_enabled boolean not null default true,
  notify_settlements boolean not null default true,
  notify_approvals boolean not null default true,
  notify_balance boolean not null default true,
  notify_cycles boolean not null default true,
  notify_awards boolean not null default true,
  updated_at timestamptz not null default now(),
  constraint user_preferences_theme check (theme in ('system', 'light', 'dark')),
  constraint user_preferences_locale check (locale in ('system', 'en', 'es'))
);

-- -----------------------------------------------------------------------------
-- Groups, memberships, invitations
-- -----------------------------------------------------------------------------

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  currency text not null default 'EUR',
  timezone text not null default 'Europe/Madrid',
  require_deposit_confirmation boolean not null default true,
  require_purchase_approval boolean not null default false,
  member_undo_window_minutes integer not null default 15,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint groups_name_length check (char_length(btrim(name)) between 1 and 60),
  constraint groups_currency_code check (currency ~ '^[A-Z]{3}$'),
  constraint groups_undo_window check (member_undo_window_minutes between 0 and 1440)
);

create table public.group_members (
  group_id uuid not null references public.groups (id),
  user_id uuid not null references public.profiles (id),
  role public.member_role not null default 'member',
  status public.membership_status not null default 'active',
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  primary key (group_id, user_id),
  constraint group_members_left_at check ((status = 'active') = (left_at is null))
);
create index group_members_user_active_idx on public.group_members (user_id) where status = 'active';

create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id),
  code text not null unique,
  role public.member_role not null default 'member',
  max_uses integer,
  use_count integer not null default 0,
  expires_at timestamptz,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  -- 32-character alphabet without the ambiguous I, O, 0 and 1.
  constraint invitations_code_format check (code ~ '^[A-HJ-NP-Z2-9]{8}$'),
  constraint invitations_role check (role in ('member', 'treasurer')),
  constraint invitations_max_uses check (max_uses is null or max_uses between 1 and 1000),
  constraint invitations_use_count check (use_count >= 0 and (max_uses is null or use_count <= max_uses))
);
create index invitations_group_idx on public.invitations (group_id, created_at desc);

-- -----------------------------------------------------------------------------
-- Accounting cycles and prices
-- -----------------------------------------------------------------------------

create table public.accounting_cycles (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id),
  sequence_no integer not null,
  name text not null,
  status public.cycle_status not null default 'open',
  opened_at timestamptz not null default now(),
  opened_by uuid not null references public.profiles (id),
  closed_at timestamptz,
  closed_by uuid references public.profiles (id),
  close_note text,
  constraint accounting_cycles_group_sequence unique (group_id, sequence_no),
  constraint accounting_cycles_id_group unique (id, group_id),
  constraint accounting_cycles_name_length check (char_length(btrim(name)) between 1 and 60),
  constraint accounting_cycles_sequence check (sequence_no >= 1),
  constraint accounting_cycles_closed check ((status = 'closed') = (closed_at is not null and closed_by is not null)),
  constraint accounting_cycles_note_length check (close_note is null or char_length(close_note) <= 500)
);
create unique index accounting_cycles_one_open_idx on public.accounting_cycles (group_id) where status = 'open';

create table public.coffee_prices (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id),
  price_cents integer not null,
  effective_from timestamptz not null,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  constraint coffee_prices_unique_start unique (group_id, effective_from),
  constraint coffee_prices_range check (price_cents between 1 and 10000)
);

-- -----------------------------------------------------------------------------
-- Transactions (the journal) and ledger entries (the postings)
-- -----------------------------------------------------------------------------

create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id),
  -- The cycle the transaction is (or will be) booked in. Pending items move to
  -- the next cycle when a cycle closes; posted items never move.
  cycle_id uuid not null,
  kind public.txn_kind not null,
  status public.txn_status not null,
  amount_cents bigint not null,
  quantity integer,
  unit_price_cents integer,
  -- Only for adjustments: +1 increases the member debt / box cash, -1 decreases it.
  direction smallint,
  -- Primary party: consumer, depositor, buyer, sender or reimbursed member.
  member_id uuid,
  -- Transfer recipient.
  counterparty_id uuid,
  initiated_by uuid not null,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  posted_at timestamptz,
  description text,
  evidence_path text,
  reverses_id uuid,
  idempotency_key uuid not null,
  metadata jsonb not null default '{}'::jsonb,
  constraint transactions_id_group unique (id, group_id),
  constraint transactions_id_group_cycle unique (id, group_id, cycle_id),
  constraint transactions_idempotency unique (initiated_by, idempotency_key),
  constraint transactions_cycle_fk foreign key (cycle_id, group_id)
    references public.accounting_cycles (id, group_id),
  constraint transactions_member_fk foreign key (group_id, member_id)
    references public.group_members (group_id, user_id),
  constraint transactions_counterparty_fk foreign key (group_id, counterparty_id)
    references public.group_members (group_id, user_id),
  constraint transactions_initiator_fk foreign key (group_id, initiated_by)
    references public.group_members (group_id, user_id),
  constraint transactions_reverses_fk foreign key (reverses_id, group_id)
    references public.transactions (id, group_id),
  constraint transactions_amount check (amount_cents between 1 and 100000000),
  constraint transactions_description_length check (description is null or char_length(description) <= 500),
  constraint transactions_coffee_fields check ((kind = 'coffee') = (quantity is not null and unit_price_cents is not null)),
  constraint transactions_coffee_amount check (
    kind <> 'coffee'
    or (quantity between 1 and 20 and unit_price_cents between 1 and 10000 and amount_cents = quantity * unit_price_cents)
  ),
  constraint transactions_direction check (
    (kind in ('cash_adjustment', 'balance_adjustment')) = (direction is not null)
    and (direction is null or direction in (-1, 1))
  ),
  constraint transactions_member_required check (kind in ('cash_adjustment', 'reversal') or member_id is not null),
  constraint transactions_cash_adjustment_member check (kind <> 'cash_adjustment' or member_id is null),
  constraint transactions_transfer_parties check (
    kind <> 'transfer' or (counterparty_id is not null and counterparty_id <> member_id)
  ),
  constraint transactions_counterparty_kind check (counterparty_id is null or kind in ('transfer', 'reversal')),
  constraint transactions_reversal_link check ((kind = 'reversal') = (reverses_id is not null)),
  constraint transactions_reversal_not_self check (reverses_id is null or reverses_id <> id),
  constraint transactions_posted_at check ((status in ('posted', 'reversed')) = (posted_at is not null))
);
create unique index transactions_one_reversal_idx on public.transactions (reverses_id) where reverses_id is not null;
create index transactions_feed_idx on public.transactions (group_id, created_at desc, id desc);
create index transactions_coffee_idx on public.transactions (group_id, occurred_at)
  include (member_id, quantity) where kind = 'coffee' and status = 'posted';
create index transactions_open_items_idx on public.transactions (group_id, status) where status in ('pending', 'disputed');
create index transactions_member_idx on public.transactions (member_id, created_at desc);
create index transactions_counterparty_idx on public.transactions (counterparty_id) where counterparty_id is not null;
create index transactions_cycle_idx on public.transactions (cycle_id);

create table public.ledger_entries (
  id bigint generated always as identity primary key,
  transaction_id uuid not null,
  group_id uuid not null,
  cycle_id uuid not null,
  account public.ledger_account not null,
  member_id uuid,
  category public.entry_category not null,
  amount_cents bigint not null,
  created_at timestamptz not null default now(),
  -- Composite key: entries can never drift to another group or cycle than their transaction.
  constraint ledger_entries_txn_fk foreign key (transaction_id, group_id, cycle_id)
    references public.transactions (id, group_id, cycle_id),
  constraint ledger_entries_member_fk foreign key (group_id, member_id)
    references public.group_members (group_id, user_id),
  constraint ledger_entries_nonzero check (amount_cents <> 0),
  constraint ledger_entries_member_account check ((account = 'member') = (member_id is not null))
);
create index ledger_entries_balance_idx on public.ledger_entries (group_id, account, member_id, cycle_id)
  include (category, amount_cents);
create index ledger_entries_txn_idx on public.ledger_entries (transaction_id);
create index ledger_entries_cash_timeline_idx on public.ledger_entries (group_id, created_at) where account = 'cash_box';

create table public.transaction_events (
  id bigint generated always as identity primary key,
  transaction_id uuid not null,
  group_id uuid not null,
  from_status public.txn_status,
  to_status public.txn_status not null,
  actor_id uuid references public.profiles (id),
  note text,
  created_at timestamptz not null default now(),
  constraint transaction_events_txn_fk foreign key (transaction_id, group_id)
    references public.transactions (id, group_id)
);
create index transaction_events_txn_idx on public.transaction_events (transaction_id, id);

-- -----------------------------------------------------------------------------
-- Cycle snapshots (immutable, written when a cycle closes)
-- -----------------------------------------------------------------------------

create table public.cycle_member_balances (
  cycle_id uuid not null,
  group_id uuid not null,
  user_id uuid not null,
  opening_cents bigint not null,
  coffees integer not null,
  consumption_cents bigint not null,
  deposits_cents bigint not null,
  personal_purchases_cents bigint not null,
  transfers_sent_cents bigint not null,
  transfers_received_cents bigint not null,
  reimbursements_cents bigint not null,
  adjustments_cents bigint not null,
  closing_cents bigint not null,
  primary key (cycle_id, user_id),
  constraint cycle_member_balances_cycle_fk foreign key (cycle_id, group_id)
    references public.accounting_cycles (id, group_id),
  constraint cycle_member_balances_member_fk foreign key (group_id, user_id)
    references public.group_members (group_id, user_id),
  -- The documented balance equation, enforced for every snapshot row.
  constraint cycle_member_balances_equation check (
    closing_cents = opening_cents + consumption_cents - deposits_cents - personal_purchases_cents
      - transfers_sent_cents + transfers_received_cents + reimbursements_cents + adjustments_cents
  )
);

create table public.cycle_cash_snapshots (
  cycle_id uuid primary key,
  group_id uuid not null,
  opening_cash_cents bigint not null,
  deposits_cents bigint not null,
  box_purchases_cents bigint not null,
  reimbursements_cents bigint not null,
  cash_adjustments_cents bigint not null,
  closing_cash_cents bigint not null,
  constraint cycle_cash_snapshots_cycle_fk foreign key (cycle_id, group_id)
    references public.accounting_cycles (id, group_id),
  constraint cycle_cash_snapshots_equation check (
    closing_cash_cents = opening_cash_cents + deposits_cents - box_purchases_cents - reimbursements_cents
      + cash_adjustments_cents
  ),
  constraint cycle_cash_snapshots_non_negative check (closing_cash_cents >= 0)
);

-- -----------------------------------------------------------------------------
-- Cash-box reconciliation
-- -----------------------------------------------------------------------------

create table public.cash_reconciliations (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null,
  cycle_id uuid not null,
  expected_cents bigint not null,
  counted_cents bigint not null,
  note text,
  adjustment_transaction_id uuid,
  idempotency_key uuid not null,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  constraint cash_reconciliations_idempotency unique (created_by, idempotency_key),
  constraint cash_reconciliations_cycle_fk foreign key (cycle_id, group_id)
    references public.accounting_cycles (id, group_id),
  constraint cash_reconciliations_creator_fk foreign key (group_id, created_by)
    references public.group_members (group_id, user_id),
  constraint cash_reconciliations_adjustment_fk foreign key (adjustment_transaction_id, group_id)
    references public.transactions (id, group_id),
  constraint cash_reconciliations_counted check (counted_cents between 0 and 100000000),
  constraint cash_reconciliations_note check (
    counted_cents = expected_cents or (note is not null and char_length(btrim(note)) between 3 and 500)
  ),
  constraint cash_reconciliations_adjustment check (adjustment_transaction_id is null or counted_cents <> expected_cents)
);
create index cash_reconciliations_group_idx on public.cash_reconciliations (group_id, created_at desc);

-- -----------------------------------------------------------------------------
-- Notifications, audit log, monthly awards
-- -----------------------------------------------------------------------------

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id),
  group_id uuid references public.groups (id),
  kind text not null,
  transaction_id uuid references public.transactions (id),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint notifications_kind check (kind in (
    'transfer_requested', 'transfer_confirmed', 'transfer_rejected',
    'deposit_pending', 'deposit_confirmed', 'deposit_rejected', 'deposit_recorded',
    'purchase_pending', 'purchase_approved', 'purchase_rejected',
    'reimbursement_requested', 'reimbursement_paid', 'reimbursement_rejected',
    'transaction_cancelled', 'transaction_reversed', 'dispute_opened', 'dispute_resolved',
    'balance_adjusted', 'coffee_recorded_for_you', 'price_changed',
    'cycle_closed', 'role_changed', 'member_joined', 'coffee_hero'
  ))
);
create index notifications_user_idx on public.notifications (user_id, created_at desc);
create index notifications_unread_idx on public.notifications (user_id) where read_at is null;

create table public.audit_log (
  id bigint generated always as identity primary key,
  group_id uuid references public.groups (id),
  actor_id uuid references public.profiles (id),
  action text not null,
  target_type text,
  target_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index audit_log_group_idx on public.audit_log (group_id, id desc);

create table public.monthly_awards (
  group_id uuid not null references public.groups (id),
  month date not null,
  user_id uuid not null,
  coffees integer not null,
  created_at timestamptz not null default now(),
  primary key (group_id, month, user_id),
  constraint monthly_awards_member_fk foreign key (group_id, user_id)
    references public.group_members (group_id, user_id),
  constraint monthly_awards_month check (month = date_trunc('month', month)::date),
  constraint monthly_awards_coffees check (coffees > 0)
);

-- Marks months whose award has been computed (also months without winners).
create table public.monthly_award_runs (
  group_id uuid not null references public.groups (id),
  month date not null,
  computed_at timestamptz not null default now(),
  primary key (group_id, month)
);

-- -----------------------------------------------------------------------------
-- Integrity guards
-- -----------------------------------------------------------------------------

create function private.forbid_change() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = 'P0001',
    message = 'append_only',
    detail = format('Rows in %s.%s cannot be %s; record a correction instead.',
      tg_table_schema, tg_table_name, lower(tg_op) || 'd');
end;
$$;

create function private.touch_updated_at() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create function private.transactions_guard() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status in ('cancelled', 'reversed') then
    raise exception using errcode = 'P0001', message = 'immutable_transaction',
      detail = 'Cancelled and reversed transactions are final.';
  end if;

  if (new.id, new.group_id, new.kind, new.amount_cents, new.initiated_by, new.idempotency_key,
      new.occurred_at, new.created_at)
     is distinct from
     (old.id, old.group_id, old.kind, old.amount_cents, old.initiated_by, old.idempotency_key,
      old.occurred_at, old.created_at)
     or new.quantity is distinct from old.quantity
     or new.unit_price_cents is distinct from old.unit_price_cents
     or new.direction is distinct from old.direction
     or new.member_id is distinct from old.member_id
     or new.counterparty_id is distinct from old.counterparty_id
     or new.description is distinct from old.description
     or new.evidence_path is distinct from old.evidence_path
     or new.reverses_id is distinct from old.reverses_id
     or new.metadata is distinct from old.metadata then
    raise exception using errcode = 'P0001', message = 'immutable_transaction',
      detail = 'Only the status of a transaction can change after it was recorded.';
  end if;

  if new.cycle_id <> old.cycle_id and old.status not in ('pending', 'rejected', 'disputed') then
    raise exception using errcode = 'P0001', message = 'immutable_transaction',
      detail = 'The accounting cycle of a posted transaction cannot change.';
  end if;

  if new.posted_at is distinct from old.posted_at
     and not (old.posted_at is null and new.status = 'posted') then
    raise exception using errcode = 'P0001', message = 'immutable_transaction',
      detail = 'The posting time of a transaction cannot change.';
  end if;

  if new.status <> old.status and not (
       (old.status = 'pending' and new.status in ('posted', 'rejected', 'cancelled'))
    or (old.status = 'rejected' and new.status = 'disputed')
    or (old.status = 'disputed' and new.status in ('posted', 'rejected'))
    or (old.status = 'posted' and new.status = 'reversed')
  ) then
    raise exception using errcode = 'P0001', message = 'invalid_transition',
      detail = format('A %s transaction cannot become %s.', old.status, new.status);
  end if;

  return new;
end;
$$;

-- Status history is written by a trigger so that no code path can skip it.
-- The acting user and an optional note are passed through transaction-local
-- settings (see private.set_context).
create function private.transactions_log_event() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := coalesce(nullif(current_setting('app.actor_id', true), '')::uuid, auth.uid());
  v_note text := nullif(current_setting('app.transaction_note', true), '');
begin
  if tg_op = 'INSERT' then
    insert into public.transaction_events (transaction_id, group_id, from_status, to_status, actor_id, note)
    values (new.id, new.group_id, null, new.status, coalesce(v_actor, new.initiated_by), v_note);
  elsif new.status is distinct from old.status then
    insert into public.transaction_events (transaction_id, group_id, from_status, to_status, actor_id, note)
    values (new.id, new.group_id, old.status, new.status, v_actor, v_note);
  end if;
  return null;
end;
$$;

create function private.ledger_entries_check_balanced() returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_sum bigint;
begin
  select coalesce(sum(amount_cents), 0) into v_sum
  from public.ledger_entries
  where transaction_id = new.transaction_id;

  if v_sum <> 0 then
    raise exception using errcode = 'P0001', message = 'unbalanced_ledger',
      detail = format('Ledger entries of transaction %s sum to %s instead of zero.', new.transaction_id, v_sum);
  end if;
  return null;
end;
$$;

create function private.accounting_cycles_guard() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status = 'closed' then
    raise exception using errcode = 'P0001', message = 'cycle_closed',
      detail = 'Closed accounting cycles cannot be changed.';
  end if;
  if (new.id, new.group_id, new.sequence_no, new.name, new.opened_at, new.opened_by)
     is distinct from (old.id, old.group_id, old.sequence_no, old.name, old.opened_at, old.opened_by) then
    raise exception using errcode = 'P0001', message = 'append_only',
      detail = 'Only closing an accounting cycle is allowed.';
  end if;
  return new;
end;
$$;

create function private.coffee_prices_guard() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and old.effective_from > now() then
    return old; -- a scheduled price that never applied may be withdrawn
  end if;
  raise exception using errcode = 'P0001', message = 'append_only',
    detail = 'Coffee prices that already applied are part of the history and cannot be changed.';
end;
$$;

create trigger transactions_guard before update on public.transactions
  for each row execute function private.transactions_guard();
create trigger transactions_no_delete before delete on public.transactions
  for each row execute function private.forbid_change();
create trigger transactions_log_event after insert or update of status on public.transactions
  for each row execute function private.transactions_log_event();

create trigger ledger_entries_append_only before update or delete on public.ledger_entries
  for each row execute function private.forbid_change();
create constraint trigger ledger_entries_balanced after insert on public.ledger_entries
  deferrable initially deferred
  for each row execute function private.ledger_entries_check_balanced();

create trigger accounting_cycles_guard before update on public.accounting_cycles
  for each row execute function private.accounting_cycles_guard();
create trigger coffee_prices_guard before update or delete on public.coffee_prices
  for each row execute function private.coffee_prices_guard();

do $$
declare
  v_table text;
begin
  -- Append-only history tables.
  foreach v_table in array array[
    'transaction_events', 'cycle_member_balances', 'cycle_cash_snapshots',
    'cash_reconciliations', 'audit_log', 'monthly_awards', 'monthly_award_runs'
  ] loop
    execute format(
      'create trigger %I before update or delete on public.%I for each row execute function private.forbid_change()',
      v_table || '_append_only', v_table);
  end loop;

  -- Records that may change state but are never deleted.
  foreach v_table in array array['profiles', 'groups', 'group_members', 'accounting_cycles', 'invitations'] loop
    execute format(
      'create trigger %I before delete on public.%I for each row execute function private.forbid_change()',
      v_table || '_no_delete', v_table);
  end loop;

  -- Resetting balances must never be done by truncating history.
  foreach v_table in array array[
    'profiles', 'groups', 'group_members', 'accounting_cycles', 'coffee_prices', 'transactions',
    'ledger_entries', 'transaction_events', 'cycle_member_balances', 'cycle_cash_snapshots',
    'cash_reconciliations', 'audit_log', 'monthly_awards', 'monthly_award_runs', 'invitations'
  ] loop
    execute format(
      'create trigger %I before truncate on public.%I for each statement execute function private.forbid_change()',
      v_table || '_no_truncate', v_table);
  end loop;
end;
$$;

create trigger profiles_touch before update on public.profiles
  for each row execute function private.touch_updated_at();
create trigger groups_touch before update on public.groups
  for each row execute function private.touch_updated_at();
create trigger user_preferences_touch before update on public.user_preferences
  for each row execute function private.touch_updated_at();

-- -----------------------------------------------------------------------------
-- Account lifecycle (auth.users -> profiles)
-- -----------------------------------------------------------------------------

create function private.handle_new_user() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := left(btrim(coalesce(
    nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'Coffee lover'
  )), 40);
begin
  insert into public.profiles (id, display_name) values (new.id, v_name)
  on conflict (id) do nothing;
  insert into public.user_preferences (user_id) values (new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

create function private.handle_deleted_user() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles
  set display_name = 'Former member', avatar_path = null, deleted_at = coalesce(deleted_at, now())
  where id = old.id;
  update public.group_members
  set status = 'left', left_at = now()
  where user_id = old.id and status = 'active';
  return old;
end;
$$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function private.handle_new_user();
create trigger on_auth_user_deleted after delete on auth.users
  for each row execute function private.handle_deleted_user();
