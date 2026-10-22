-- =============================================================================
-- Coffee Tracker — ledger engine (private helpers)
--
-- All balance-changing operations go through these functions. They are only
-- callable from the SECURITY DEFINER API functions, never directly by clients.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Errors and request context
-- -----------------------------------------------------------------------------

-- Raises an application error. `message` carries a stable machine-readable key
-- that clients translate; `detail` carries an English explanation.
create function private.fail(p_key text, p_detail text default null) returns void
language plpgsql
set search_path = ''
as $$
begin
  raise exception using errcode = 'P0001', message = p_key, detail = coalesce(p_detail, p_key);
end;
$$;

create function private.current_user_id() returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    perform private.fail('not_authenticated', 'You must be signed in.');
  end if;
  return v_user;
end;
$$;

-- Passes the acting user and a note to the transaction event trigger.
create function private.set_context(p_actor uuid, p_note text) returns void
language plpgsql
set search_path = ''
as $$
begin
  perform set_config('app.actor_id', coalesce(p_actor::text, ''), true);
  perform set_config('app.transaction_note', coalesce(btrim(p_note), ''), true);
end;
$$;

create function private.require_text(p_value text, p_key text, p_min integer, p_max integer, p_label text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_value text := btrim(coalesce(p_value, ''));
begin
  if char_length(v_value) < p_min or char_length(v_value) > p_max then
    perform private.fail(p_key, format('%s must be between %s and %s characters long.', p_label, p_min, p_max));
  end if;
  return v_value;
end;
$$;

create function private.require_amount(p_amount bigint, p_max bigint default 500000) returns bigint
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_amount is null or p_amount < 1 then
    perform private.fail('invalid_amount', 'Amounts must be positive.');
  end if;
  if p_amount > p_max then
    perform private.fail('amount_too_large',
      format('Amounts above %s.%s are not accepted. Split the operation or contact an administrator.',
        p_max / 100, lpad((p_max % 100)::text, 2, '0')));
  end if;
  return p_amount;
end;
$$;

-- -----------------------------------------------------------------------------
-- Membership and authorization
-- -----------------------------------------------------------------------------

create function private.membership_role(p_group uuid, p_user uuid) returns public.member_role
language sql
stable
set search_path = ''
as $$
  select role from public.group_members
  where group_id = p_group and user_id = p_user and status = 'active'
$$;

create function private.require_member(p_group uuid) returns public.member_role
language plpgsql
stable
set search_path = ''
as $$
declare
  v_role public.member_role;
begin
  v_role := private.membership_role(p_group, private.current_user_id());
  if v_role is null then
    perform private.fail('not_member', 'You are not an active member of this group.');
  end if;
  return v_role;
end;
$$;

create function private.require_role(p_group uuid, p_roles public.member_role[]) returns public.member_role
language plpgsql
stable
set search_path = ''
as $$
declare
  v_role public.member_role := private.require_member(p_group);
begin
  if not v_role = any (p_roles) then
    perform private.fail('forbidden', 'Your role in this group does not allow this action.');
  end if;
  return v_role;
end;
$$;

-- RLS helpers. SECURITY DEFINER avoids recursive RLS evaluation on
-- group_members; each only ever returns rows related to the calling user.
create function private.my_group_ids() returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select group_id from public.group_members
  where user_id = (select auth.uid()) and status = 'active'
$$;

create function private.my_admin_group_ids() returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select group_id from public.group_members
  where user_id = (select auth.uid()) and status = 'active' and role = 'admin'
$$;

create function private.my_co_member_ids() returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select distinct gm.user_id
  from public.group_members gm
  where gm.group_id in (
    select g.group_id from public.group_members g
    where g.user_id = (select auth.uid()) and g.status = 'active'
  )
$$;

-- Serializes all balance-changing work inside one group. Checks such as
-- "the cash box may not become negative" are therefore race-free.
create function private.lock_group(p_group uuid) returns void
language plpgsql
set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(1129270113, hashtext(p_group::text));
end;
$$;

create function private.open_cycle_id(p_group uuid) returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_cycle uuid;
begin
  select id into v_cycle from public.accounting_cycles where group_id = p_group and status = 'open';
  if v_cycle is null then
    perform private.fail('no_open_cycle', 'This group has no open accounting cycle.');
  end if;
  return v_cycle;
end;
$$;

-- -----------------------------------------------------------------------------
-- Prices and balances
-- -----------------------------------------------------------------------------

create function private.price_at(p_group uuid, p_at timestamptz) returns integer
language sql
stable
set search_path = ''
as $$
  select coalesce(
    (select price_cents from public.coffee_prices
     where group_id = p_group and effective_from <= p_at
     order by effective_from desc limit 1),
    (select price_cents from public.coffee_prices
     where group_id = p_group
     order by effective_from asc limit 1)
  )
$$;

-- Positive: the member owes the group. Negative: the group owes the member.
create function private.member_balance(p_group uuid, p_user uuid) returns bigint
language sql
stable
set search_path = ''
as $$
  select coalesce(sum(amount_cents), 0)::bigint
  from public.ledger_entries
  where group_id = p_group and account = 'member' and member_id = p_user
$$;

create function private.cash_balance(p_group uuid) returns bigint
language sql
stable
set search_path = ''
as $$
  select coalesce(sum(amount_cents), 0)::bigint
  from public.ledger_entries
  where group_id = p_group and account = 'cash_box'
$$;

-- -----------------------------------------------------------------------------
-- Posting rules: the single source of truth for how each transaction kind
-- moves money between accounts. Every rule sums to zero.
-- -----------------------------------------------------------------------------

create function private.posting_rule(
  p_kind public.txn_kind,
  p_amount bigint,
  p_member uuid,
  p_counterparty uuid,
  p_direction smallint
)
returns table (account public.ledger_account, member_id uuid, category public.entry_category, amount_cents bigint)
language sql
immutable
set search_path = ''
as $$
  select r.account, r.member_id, r.category, r.amount_cents
  from (values
    -- A member drinks coffee: they owe more, the group earns consumption income.
    ('coffee'::public.txn_kind, 'member'::public.ledger_account, p_member, 'consumption'::public.entry_category, p_amount),
    ('coffee', 'consumption', null::uuid, 'consumption', -p_amount),
    -- Cash into the box: the box grows, the member owes less.
    ('deposit', 'cash_box', null, 'deposit', p_amount),
    ('deposit', 'member', p_member, 'deposit', -p_amount),
    -- Beans bought with personal money: the buyer is credited, the box is untouched.
    ('purchase_personal', 'supplies', null, 'purchase_personal', p_amount),
    ('purchase_personal', 'member', p_member, 'purchase_personal', -p_amount),
    -- Beans bought with box money: the box shrinks, nobody is credited personally.
    ('purchase_box', 'supplies', null, 'purchase_box', p_amount),
    ('purchase_box', 'cash_box', null, 'purchase_box', -p_amount),
    -- Direct payment: the sender owes less, the recipient's credit shrinks.
    ('transfer', 'member', p_member, 'transfer_out', -p_amount),
    ('transfer', 'member', p_counterparty, 'transfer_in', p_amount),
    -- Box pays a member: the box shrinks, the member's credit shrinks.
    ('reimbursement', 'member', p_member, 'reimbursement', p_amount),
    ('reimbursement', 'cash_box', null, 'reimbursement', -p_amount),
    -- Reconciliation of the physical box against the expected balance.
    ('cash_adjustment', 'cash_box', null, 'cash_adjustment', p_direction * p_amount),
    ('cash_adjustment', 'adjustments', null, 'cash_adjustment', -(p_direction * p_amount)),
    -- Administrative correction of a member balance.
    ('balance_adjustment', 'member', p_member, 'balance_adjustment', p_direction * p_amount),
    ('balance_adjustment', 'adjustments', null, 'balance_adjustment', -(p_direction * p_amount))
  ) as r (kind, account, member_id, category, amount_cents)
  where r.kind = p_kind
$$;

create function private.write_entries(p_txn_id uuid) returns void
language plpgsql
set search_path = ''
as $$
declare
  t public.transactions;
begin
  select * into t from public.transactions where id = p_txn_id;
  if t.status <> 'posted' then
    perform private.fail('invalid_state', 'Only posted transactions produce ledger entries.');
  end if;
  if exists (select 1 from public.ledger_entries where transaction_id = t.id) then
    perform private.fail('already_posted', 'This transaction already has ledger entries.');
  end if;

  if t.kind = 'reversal' then
    insert into public.ledger_entries (transaction_id, group_id, cycle_id, account, member_id, category, amount_cents, created_at)
    select t.id, t.group_id, t.cycle_id, e.account, e.member_id, e.category, -e.amount_cents, t.posted_at
    from public.ledger_entries e
    where e.transaction_id = t.reverses_id;
  else
    insert into public.ledger_entries (transaction_id, group_id, cycle_id, account, member_id, category, amount_cents, created_at)
    select t.id, t.group_id, t.cycle_id, r.account, r.member_id, r.category, r.amount_cents, t.posted_at
    from private.posting_rule(t.kind, t.amount_cents, t.member_id, t.counterparty_id, t.direction) r;
  end if;
end;
$$;

-- Post-conditions checked after every posting while the group lock is held.
create function private.check_post_conditions(t public.transactions) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_kind public.txn_kind := t.kind;
begin
  if t.kind = 'reversal' then
    select kind into v_kind from public.transactions where id = t.reverses_id;
  end if;

  if v_kind in ('deposit', 'purchase_box', 'reimbursement', 'cash_adjustment')
     and private.cash_balance(t.group_id) < 0 then
    perform private.fail('insufficient_cash',
      'The cash box does not contain enough confirmed money for this operation.');
  end if;

  if t.kind = 'reimbursement' and private.member_balance(t.group_id, t.member_id) > 0 then
    perform private.fail('reimbursement_exceeds_credit',
      'A reimbursement cannot exceed the amount the group owes this member.');
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- Transaction lifecycle
-- -----------------------------------------------------------------------------

create function private.insert_transaction(
  p_group uuid,
  p_kind public.txn_kind,
  p_status public.txn_status,
  p_amount bigint,
  p_member uuid,
  p_counterparty uuid,
  p_initiator uuid,
  p_idempotency_key uuid,
  p_occurred_at timestamptz default null,
  p_description text default null,
  p_evidence_path text default null,
  p_quantity integer default null,
  p_unit_price integer default null,
  p_direction smallint default null,
  p_reverses uuid default null,
  p_note text default null,
  p_at timestamptz default null,
  p_metadata jsonb default '{}'::jsonb
)
returns public.transactions
language plpgsql
set search_path = ''
as $$
declare
  v_at timestamptz := coalesce(p_at, clock_timestamp());
  t public.transactions;
begin
  if p_status not in ('pending', 'posted') then
    perform private.fail('invalid_state', 'New transactions are either pending or posted.');
  end if;

  perform private.set_context(p_initiator, p_note);

  insert into public.transactions (
    group_id, cycle_id, kind, status, amount_cents, quantity, unit_price_cents, direction,
    member_id, counterparty_id, initiated_by, occurred_at, created_at, posted_at,
    description, evidence_path, reverses_id, idempotency_key, metadata
  ) values (
    p_group, private.open_cycle_id(p_group), p_kind, p_status, p_amount, p_quantity, p_unit_price, p_direction,
    p_member, p_counterparty, p_initiator, coalesce(p_occurred_at, v_at), v_at,
    case when p_status = 'posted' then v_at end,
    nullif(btrim(p_description), ''), p_evidence_path, p_reverses, p_idempotency_key, coalesce(p_metadata, '{}'::jsonb)
  )
  returning * into t;

  if p_status = 'posted' then
    perform private.write_entries(t.id);
    perform private.check_post_conditions(t);
  end if;

  perform private.set_context(null, null);
  return t;
end;
$$;

-- Moves a pending (or disputed) transaction to posted in the open cycle.
create function private.post_existing(p_txn_id uuid, p_actor uuid, p_note text, p_at timestamptz default null)
returns public.transactions
language plpgsql
set search_path = ''
as $$
declare
  t public.transactions;
begin
  perform private.set_context(p_actor, p_note);

  update public.transactions
  set status = 'posted',
      posted_at = coalesce(p_at, clock_timestamp()),
      cycle_id = private.open_cycle_id(group_id)
  where id = p_txn_id and status in ('pending', 'disputed')
  returning * into t;

  if t.id is null then
    perform private.fail('invalid_state', 'This transaction is no longer awaiting a decision.');
  end if;

  perform private.write_entries(t.id);
  perform private.check_post_conditions(t);
  perform private.set_context(null, null);
  return t;
end;
$$;

create function private.change_status(p_txn_id uuid, p_status public.txn_status, p_actor uuid, p_note text)
returns public.transactions
language plpgsql
set search_path = ''
as $$
declare
  t public.transactions;
begin
  perform private.set_context(p_actor, p_note);
  update public.transactions set status = p_status where id = p_txn_id returning * into t;
  perform private.set_context(null, null);
  return t;
end;
$$;

-- Returns the transaction previously created with this idempotency key, or
-- null. A key reused for a different operation is rejected.
create function private.idempotent_replay(
  p_initiator uuid,
  p_key uuid,
  p_group uuid,
  p_kind public.txn_kind,
  p_amount bigint default null
)
returns public.transactions
language plpgsql
stable
set search_path = ''
as $$
declare
  t public.transactions;
begin
  if p_key is null then
    perform private.fail('invalid_request', 'Every operation needs an idempotency key.');
  end if;

  select * into t from public.transactions where initiated_by = p_initiator and idempotency_key = p_key;
  if t.id is null then
    return null;
  end if;

  if t.group_id <> p_group or t.kind <> p_kind or (p_amount is not null and t.amount_cents <> p_amount) then
    perform private.fail('idempotency_conflict', 'This request key was already used for a different operation.');
  end if;
  return t;
end;
$$;

create function private.reverse_internal(
  p_txn_id uuid,
  p_actor uuid,
  p_note text,
  p_idempotency_key uuid,
  p_at timestamptz default null
)
returns public.transactions
language plpgsql
set search_path = ''
as $$
declare
  o public.transactions;
  r public.transactions;
begin
  select * into o from public.transactions where id = p_txn_id for update;
  if o.id is null then
    perform private.fail('not_found', 'Transaction not found.');
  end if;
  if o.kind = 'reversal' then
    perform private.fail('cannot_reverse_reversal', 'A reversal cannot itself be reversed. Record the original again instead.');
  end if;
  if o.status = 'reversed' then
    perform private.fail('already_reversed', 'This transaction has already been reversed.');
  end if;
  if o.status <> 'posted' then
    perform private.fail('invalid_state', 'Only posted transactions can be reversed.');
  end if;

  perform private.change_status(o.id, 'reversed', p_actor, p_note);

  r := private.insert_transaction(
    o.group_id, 'reversal', 'posted', o.amount_cents, o.member_id, o.counterparty_id, p_actor, p_idempotency_key,
    p_description => p_note,
    p_reverses => o.id,
    p_note => p_note,
    p_at => p_at,
    p_metadata => jsonb_build_object('reversed_kind', o.kind)
  );
  return r;
end;
$$;

-- -----------------------------------------------------------------------------
-- Notifications and audit
-- -----------------------------------------------------------------------------

create function private.notification_category(p_kind text) returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_kind in ('transfer_requested', 'transfer_confirmed', 'transfer_rejected', 'transaction_cancelled')
      then 'settlements'
    when p_kind in ('deposit_pending', 'deposit_confirmed', 'deposit_rejected', 'deposit_recorded',
                    'purchase_pending', 'purchase_approved', 'purchase_rejected',
                    'reimbursement_requested', 'reimbursement_paid', 'reimbursement_rejected',
                    'dispute_opened', 'dispute_resolved')
      then 'approvals'
    when p_kind = 'cycle_closed' then 'cycles'
    when p_kind = 'coffee_hero' then 'awards'
    else 'balance'
  end
$$;

create function private.display_name(p_user uuid) returns text
language sql
stable
set search_path = ''
as $$
  select display_name from public.profiles where id = p_user
$$;

create function private.notify(
  p_user uuid,
  p_group uuid,
  p_kind text,
  p_txn uuid,
  p_payload jsonb,
  p_actor uuid default null
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_prefs public.user_preferences;
  v_category text := private.notification_category(p_kind);
  v_enabled boolean;
begin
  if p_user is null or p_user = p_actor then
    return;
  end if;

  select * into v_prefs from public.user_preferences where user_id = p_user;
  v_enabled := case v_category
    when 'settlements' then v_prefs.notify_settlements
    when 'approvals' then v_prefs.notify_approvals
    when 'cycles' then v_prefs.notify_cycles
    when 'awards' then v_prefs.notify_awards
    else v_prefs.notify_balance
  end;
  if v_prefs.user_id is not null and not v_enabled then
    return;
  end if;

  insert into public.notifications (user_id, group_id, kind, transaction_id, payload)
  values (p_user, p_group, p_kind, p_txn,
    coalesce(p_payload, '{}'::jsonb) || jsonb_build_object('actor_name', private.display_name(p_actor)));
end;
$$;

create function private.notify_roles(
  p_group uuid,
  p_roles public.member_role[],
  p_kind text,
  p_txn uuid,
  p_payload jsonb,
  p_actor uuid
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_user uuid;
begin
  for v_user in
    select user_id from public.group_members
    where group_id = p_group and status = 'active' and role = any (p_roles)
  loop
    perform private.notify(v_user, p_group, p_kind, p_txn, p_payload, p_actor);
  end loop;
end;
$$;

create function private.txn_payload(t public.transactions) returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'transaction_kind', t.kind,
    'amount_cents', t.amount_cents,
    'quantity', t.quantity,
    'member_id', t.member_id,
    'member_name', private.display_name(t.member_id),
    'counterparty_id', t.counterparty_id,
    'counterparty_name', private.display_name(t.counterparty_id),
    'description', t.description
  )
$$;

create function private.audit(
  p_group uuid,
  p_actor uuid,
  p_action text,
  p_target_type text,
  p_target_id text,
  p_details jsonb default '{}'::jsonb
)
returns void
language sql
set search_path = ''
as $$
  insert into public.audit_log (group_id, actor_id, action, target_type, target_id, details)
  values (p_group, p_actor, p_action, p_target_type, p_target_id, coalesce(p_details, '{}'::jsonb))
$$;

create function private.txn_result(t public.transactions, p_replayed boolean) returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'transaction_id', t.id,
    'kind', t.kind,
    'status', t.status,
    'amount_cents', t.amount_cents,
    'replayed', p_replayed
  )
$$;

-- -----------------------------------------------------------------------------
-- Cycle figures (shared by reports, dashboards and cycle closing)
-- -----------------------------------------------------------------------------

create function private.previous_cycle_id(p_cycle uuid) returns uuid
language sql
stable
set search_path = ''
as $$
  select p.id
  from public.accounting_cycles c
  join public.accounting_cycles p on p.group_id = c.group_id and p.sequence_no = c.sequence_no - 1
  where c.id = p_cycle
$$;

-- Per-member figures of one cycle computed from the ledger. Components are
-- reported in the units of the documented equation:
--   closing = opening + consumption - deposits - personal_purchases
--             - transfers_sent + transfers_received + reimbursements + adjustments
create function private.cycle_member_rows(p_group uuid, p_cycle uuid)
returns table (
  user_id uuid,
  opening_cents bigint,
  coffees integer,
  consumption_cents bigint,
  deposits_cents bigint,
  personal_purchases_cents bigint,
  transfers_sent_cents bigint,
  transfers_received_cents bigint,
  reimbursements_cents bigint,
  adjustments_cents bigint,
  closing_cents bigint
)
language sql
stable
set search_path = ''
as $$
  with opening as (
    select b.user_id, b.closing_cents
    from public.cycle_member_balances b
    where b.cycle_id = private.previous_cycle_id(p_cycle)
  ),
  moves as (
    select e.member_id as user_id,
      coalesce(sum(e.amount_cents) filter (where e.category = 'consumption'), 0) as consumption_cents,
      -coalesce(sum(e.amount_cents) filter (where e.category = 'deposit'), 0) as deposits_cents,
      -coalesce(sum(e.amount_cents) filter (where e.category = 'purchase_personal'), 0) as personal_purchases_cents,
      -coalesce(sum(e.amount_cents) filter (where e.category = 'transfer_out'), 0) as transfers_sent_cents,
      coalesce(sum(e.amount_cents) filter (where e.category = 'transfer_in'), 0) as transfers_received_cents,
      coalesce(sum(e.amount_cents) filter (where e.category = 'reimbursement'), 0) as reimbursements_cents,
      coalesce(sum(e.amount_cents) filter (where e.category = 'balance_adjustment'), 0) as adjustments_cents
    from public.ledger_entries e
    where e.group_id = p_group and e.cycle_id = p_cycle and e.account = 'member'
    group by e.member_id
  ),
  coffees as (
    select t.member_id as user_id, sum(t.quantity)::integer as coffees
    from public.transactions t
    where t.group_id = p_group and t.cycle_id = p_cycle and t.kind = 'coffee' and t.status = 'posted'
    group by t.member_id
  ),
  people as (
    select gm.user_id from public.group_members gm where gm.group_id = p_group and gm.status = 'active'
    union select o.user_id from opening o
    union select m.user_id from moves m
    union select c.user_id from coffees c
  )
  select p.user_id,
    coalesce(o.closing_cents, 0)::bigint,
    coalesce(c.coffees, 0),
    coalesce(m.consumption_cents, 0)::bigint,
    coalesce(m.deposits_cents, 0)::bigint,
    coalesce(m.personal_purchases_cents, 0)::bigint,
    coalesce(m.transfers_sent_cents, 0)::bigint,
    coalesce(m.transfers_received_cents, 0)::bigint,
    coalesce(m.reimbursements_cents, 0)::bigint,
    coalesce(m.adjustments_cents, 0)::bigint,
    (coalesce(o.closing_cents, 0) + coalesce(m.consumption_cents, 0) - coalesce(m.deposits_cents, 0)
      - coalesce(m.personal_purchases_cents, 0) - coalesce(m.transfers_sent_cents, 0)
      + coalesce(m.transfers_received_cents, 0) + coalesce(m.reimbursements_cents, 0)
      + coalesce(m.adjustments_cents, 0))::bigint
  from people p
  left join opening o on o.user_id = p.user_id
  left join moves m on m.user_id = p.user_id
  left join coffees c on c.user_id = p.user_id
$$;

create function private.cycle_cash_row(p_group uuid, p_cycle uuid)
returns table (
  opening_cash_cents bigint,
  deposits_cents bigint,
  box_purchases_cents bigint,
  reimbursements_cents bigint,
  cash_adjustments_cents bigint,
  closing_cash_cents bigint
)
language sql
stable
set search_path = ''
as $$
  with opening as (
    select coalesce((
      select s.closing_cash_cents from public.cycle_cash_snapshots s
      where s.cycle_id = private.previous_cycle_id(p_cycle)
    ), 0)::bigint as cents
  ),
  moves as (
    select
      coalesce(sum(e.amount_cents) filter (where e.category = 'deposit'), 0) as deposits,
      -coalesce(sum(e.amount_cents) filter (where e.category = 'purchase_box'), 0) as box_purchases,
      -coalesce(sum(e.amount_cents) filter (where e.category = 'reimbursement'), 0) as reimbursements,
      coalesce(sum(e.amount_cents) filter (where e.category = 'cash_adjustment'), 0) as adjustments,
      coalesce(sum(e.amount_cents), 0) as total
    from public.ledger_entries e
    where e.group_id = p_group and e.cycle_id = p_cycle and e.account = 'cash_box'
  )
  select o.cents, m.deposits::bigint, m.box_purchases::bigint, m.reimbursements::bigint, m.adjustments::bigint,
    (o.cents + m.total)::bigint
  from opening o cross join moves m
$$;

-- Closes the open cycle and opens the next one. Callers hold the group lock
-- and have validated authorization.
create function private.close_cycle_internal(
  p_group uuid,
  p_cycle uuid,
  p_actor uuid,
  p_next_name text,
  p_note text,
  p_at timestamptz default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_at timestamptz := coalesce(p_at, clock_timestamp());
  v_cycle public.accounting_cycles;
  v_new uuid;
  v_item record;
begin
  select * into v_cycle from public.accounting_cycles where id = p_cycle and group_id = p_group for update;
  if v_cycle.status <> 'open' then
    perform private.fail('cycle_closed', 'This accounting cycle is already closed.');
  end if;

  insert into public.cycle_member_balances (
    cycle_id, group_id, user_id, opening_cents, coffees, consumption_cents, deposits_cents,
    personal_purchases_cents, transfers_sent_cents, transfers_received_cents, reimbursements_cents,
    adjustments_cents, closing_cents)
  select p_cycle, p_group, r.user_id, r.opening_cents, r.coffees, r.consumption_cents, r.deposits_cents,
    r.personal_purchases_cents, r.transfers_sent_cents, r.transfers_received_cents, r.reimbursements_cents,
    r.adjustments_cents, r.closing_cents
  from private.cycle_member_rows(p_group, p_cycle) r;

  insert into public.cycle_cash_snapshots (
    cycle_id, group_id, opening_cash_cents, deposits_cents, box_purchases_cents, reimbursements_cents,
    cash_adjustments_cents, closing_cash_cents)
  select p_cycle, p_group, c.opening_cash_cents, c.deposits_cents, c.box_purchases_cents, c.reimbursements_cents,
    c.cash_adjustments_cents, c.closing_cash_cents
  from private.cycle_cash_row(p_group, p_cycle) c;

  update public.accounting_cycles
  set status = 'closed', closed_at = v_at, closed_by = p_actor, close_note = nullif(btrim(p_note), '')
  where id = p_cycle;

  insert into public.accounting_cycles (group_id, sequence_no, name, status, opened_at, opened_by)
  values (p_group, v_cycle.sequence_no + 1, btrim(p_next_name), 'open', v_at, p_actor)
  returning id into v_new;

  -- Open items are not lost: they move to the new cycle with an audit event.
  for v_item in
    update public.transactions set cycle_id = v_new
    where group_id = p_group and cycle_id = p_cycle and status in ('pending', 'disputed')
    returning id, status
  loop
    insert into public.transaction_events (transaction_id, group_id, from_status, to_status, actor_id, note, created_at)
    values (v_item.id, p_group, v_item.status, v_item.status, p_actor,
      format('Carried forward to %s', btrim(p_next_name)), v_at);
  end loop;

  for v_item in
    select b.user_id, b.closing_cents
    from public.cycle_member_balances b
    join public.group_members gm on gm.group_id = p_group and gm.user_id = b.user_id and gm.status = 'active'
    where b.cycle_id = p_cycle
  loop
    perform private.notify(v_item.user_id, p_group, 'cycle_closed', null,
      jsonb_build_object('cycle_name', v_cycle.name, 'next_cycle_name', btrim(p_next_name),
        'closing_cents', v_item.closing_cents),
      p_actor);
  end loop;

  perform private.audit(p_group, p_actor, 'cycle_closed', 'accounting_cycle', p_cycle::text,
    jsonb_build_object('name', v_cycle.name, 'next_cycle_id', v_new, 'next_cycle_name', btrim(p_next_name)));
  return v_new;
end;
$$;
