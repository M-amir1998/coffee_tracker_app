-- =============================================================================
-- Coffee Tracker — read models
--
-- Aggregations run in the database so clients never download full histories.
-- Every function verifies group membership before reading anything.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Shared helpers
-- -----------------------------------------------------------------------------

create function private.group_timezone(p_group uuid) returns text
language sql
stable
set search_path = ''
as $$
  select timezone from public.groups where id = p_group
$$;

create function private.require_cycle_of_group(p_group uuid, p_cycle uuid) returns public.accounting_cycles
language plpgsql
stable
set search_path = ''
as $$
declare
  v_cycle public.accounting_cycles;
begin
  if p_cycle is null then
    select * into v_cycle from public.accounting_cycles where group_id = p_group and status = 'open';
  else
    select * into v_cycle from public.accounting_cycles where id = p_cycle and group_id = p_group;
  end if;
  if v_cycle.id is null then
    perform private.fail('not_found', 'Accounting cycle not found.');
  end if;
  return v_cycle;
end;
$$;

create function private.all_time_member_rows(p_group uuid)
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
  with moves as (
    select e.member_id as user_id,
      coalesce(sum(e.amount_cents) filter (where e.category = 'consumption'), 0) as consumption_cents,
      -coalesce(sum(e.amount_cents) filter (where e.category = 'deposit'), 0) as deposits_cents,
      -coalesce(sum(e.amount_cents) filter (where e.category = 'purchase_personal'), 0) as personal_purchases_cents,
      -coalesce(sum(e.amount_cents) filter (where e.category = 'transfer_out'), 0) as transfers_sent_cents,
      coalesce(sum(e.amount_cents) filter (where e.category = 'transfer_in'), 0) as transfers_received_cents,
      coalesce(sum(e.amount_cents) filter (where e.category = 'reimbursement'), 0) as reimbursements_cents,
      coalesce(sum(e.amount_cents) filter (where e.category = 'balance_adjustment'), 0) as adjustments_cents,
      coalesce(sum(e.amount_cents), 0) as net_cents
    from public.ledger_entries e
    where e.group_id = p_group and e.account = 'member'
    group by e.member_id
  ),
  coffees as (
    select t.member_id as user_id, sum(t.quantity)::integer as coffees
    from public.transactions t
    where t.group_id = p_group and t.kind = 'coffee' and t.status = 'posted'
    group by t.member_id
  ),
  people as (
    select gm.user_id from public.group_members gm where gm.group_id = p_group and gm.status = 'active'
    union select m.user_id from moves m
    union select c.user_id from coffees c
  )
  select p.user_id, 0::bigint, coalesce(c.coffees, 0),
    coalesce(m.consumption_cents, 0)::bigint, coalesce(m.deposits_cents, 0)::bigint,
    coalesce(m.personal_purchases_cents, 0)::bigint, coalesce(m.transfers_sent_cents, 0)::bigint,
    coalesce(m.transfers_received_cents, 0)::bigint, coalesce(m.reimbursements_cents, 0)::bigint,
    coalesce(m.adjustments_cents, 0)::bigint, coalesce(m.net_cents, 0)::bigint
  from people p
  left join moves m on m.user_id = p.user_id
  left join coffees c on c.user_id = p.user_id
$$;

-- Member figures for a scope: the open cycle (live), a closed cycle (frozen
-- snapshot) or the whole history.
create function private.balance_rows(p_group uuid, p_cycle uuid, p_all_time boolean)
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
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_all_time then
    return query select * from private.all_time_member_rows(p_group);
  elsif exists (select 1 from public.accounting_cycles where id = p_cycle and status = 'closed') then
    return query
      select b.user_id, b.opening_cents, b.coffees, b.consumption_cents, b.deposits_cents,
        b.personal_purchases_cents, b.transfers_sent_cents, b.transfers_received_cents, b.reimbursements_cents,
        b.adjustments_cents, b.closing_cents
      from public.cycle_member_balances b
      where b.cycle_id = p_cycle;
  else
    return query select * from private.cycle_member_rows(p_group, p_cycle);
  end if;
end;
$$;

create function private.cash_rows(p_group uuid, p_cycle uuid, p_all_time boolean)
returns table (
  opening_cash_cents bigint,
  deposits_cents bigint,
  box_purchases_cents bigint,
  reimbursements_cents bigint,
  cash_adjustments_cents bigint,
  closing_cash_cents bigint
)
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_all_time then
    return query
      select 0::bigint,
        coalesce(sum(e.amount_cents) filter (where e.category = 'deposit'), 0)::bigint,
        -coalesce(sum(e.amount_cents) filter (where e.category = 'purchase_box'), 0)::bigint,
        -coalesce(sum(e.amount_cents) filter (where e.category = 'reimbursement'), 0)::bigint,
        coalesce(sum(e.amount_cents) filter (where e.category = 'cash_adjustment'), 0)::bigint,
        coalesce(sum(e.amount_cents), 0)::bigint
      from public.ledger_entries e
      where e.group_id = p_group and e.account = 'cash_box';
  elsif exists (select 1 from public.accounting_cycles where id = p_cycle and status = 'closed') then
    return query
      select s.opening_cash_cents, s.deposits_cents, s.box_purchases_cents, s.reimbursements_cents,
        s.cash_adjustments_cents, s.closing_cash_cents
      from public.cycle_cash_snapshots s
      where s.cycle_id = p_cycle;
  else
    return query select * from private.cycle_cash_row(p_group, p_cycle);
  end if;
end;
$$;

create function private.cycle_json(c public.accounting_cycles) returns jsonb
language sql
stable
set search_path = ''
as $$
  select case when c.id is null then null else jsonb_build_object(
    'id', c.id,
    'sequence_no', c.sequence_no,
    'name', c.name,
    'status', c.status,
    'opened_at', c.opened_at,
    'closed_at', c.closed_at,
    'opened_by_name', private.display_name(c.opened_by),
    'closed_by_name', private.display_name(c.closed_by),
    'close_note', c.close_note
  ) end
$$;

-- Transactions that wait for a decision by p_user.
create function private.awaiting_decision(p_group uuid, p_user uuid, p_role public.member_role)
returns setof public.transactions
language sql
stable
set search_path = ''
as $$
  select t.*
  from public.transactions t
  where t.group_id = p_group
    and t.status in ('pending', 'disputed')
    and (
      (t.status = 'pending' and private.can_decide(t, p_user, p_role))
      or (t.status = 'disputed' and p_role = 'admin'
          and (p_user not in (t.initiated_by, t.member_id, coalesce(t.counterparty_id, t.member_id))
               or not exists (
                 select 1 from public.group_members gm
                 where gm.group_id = t.group_id and gm.status = 'active' and gm.role = 'admin'
                   and gm.user_id not in (t.initiated_by, t.member_id, coalesce(t.counterparty_id, t.member_id)))))
    )
$$;

-- -----------------------------------------------------------------------------
-- Groups and members
-- -----------------------------------------------------------------------------

create function public.get_my_groups()
returns table (
  group_id uuid,
  name text,
  role public.member_role,
  member_count integer,
  cycle_name text,
  currency text,
  joined_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select g.id, g.name, gm.role,
    (select count(*)::integer from public.group_members x where x.group_id = g.id and x.status = 'active'),
    (select c.name from public.accounting_cycles c where c.group_id = g.id and c.status = 'open'),
    g.currency, gm.joined_at
  from public.group_members gm
  join public.groups g on g.id = gm.group_id
  where gm.user_id = auth.uid() and gm.status = 'active'
  order by gm.joined_at
$$;

create function public.get_members(p_group_id uuid, p_include_inactive boolean default false)
returns table (
  user_id uuid,
  display_name text,
  avatar_path text,
  role public.member_role,
  status public.membership_status,
  joined_at timestamptz,
  left_at timestamptz,
  is_me boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_member(p_group_id);
  return query
    select gm.user_id, p.display_name, p.avatar_path, gm.role, gm.status, gm.joined_at, gm.left_at,
      gm.user_id = auth.uid()
    from public.group_members gm
    join public.profiles p on p.id = gm.user_id
    where gm.group_id = p_group_id and (p_include_inactive or gm.status = 'active')
    order by gm.status, lower(p.display_name);
end;
$$;

-- -----------------------------------------------------------------------------
-- Balances and overview
-- -----------------------------------------------------------------------------

create function public.get_member_balances(
  p_group_id uuid,
  p_cycle_id uuid default null,
  p_all_time boolean default false
)
returns table (
  user_id uuid,
  display_name text,
  avatar_path text,
  role public.member_role,
  membership_status public.membership_status,
  coffees integer,
  opening_cents bigint,
  consumption_cents bigint,
  deposits_cents bigint,
  personal_purchases_cents bigint,
  contributions_cents bigint,
  transfers_sent_cents bigint,
  transfers_received_cents bigint,
  reimbursements_cents bigint,
  adjustments_cents bigint,
  net_cents bigint,
  balance_status text,
  is_me boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cycle public.accounting_cycles;
begin
  perform private.require_member(p_group_id);
  v_cycle := private.require_cycle_of_group(p_group_id, p_cycle_id);
  return query
    select r.user_id, p.display_name, p.avatar_path, gm.role, gm.status, r.coffees, r.opening_cents,
      r.consumption_cents, r.deposits_cents, r.personal_purchases_cents,
      (r.deposits_cents + r.personal_purchases_cents)::bigint,
      r.transfers_sent_cents, r.transfers_received_cents, r.reimbursements_cents, r.adjustments_cents,
      r.closing_cents,
      case when r.closing_cents > 0 then 'owes' when r.closing_cents < 0 then 'owed' else 'settled' end,
      r.user_id = auth.uid()
    from private.balance_rows(p_group_id, v_cycle.id, p_all_time) r
    join public.profiles p on p.id = r.user_id
    join public.group_members gm on gm.group_id = p_group_id and gm.user_id = r.user_id
    where gm.status = 'active' or r.closing_cents <> 0 or r.coffees <> 0 or r.opening_cents <> 0
    order by lower(p.display_name);
end;
$$;

create function private.pending_summary(p_group uuid) returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'count', count(*),
    'deposits_cents', coalesce(sum(amount_cents) filter (where kind = 'deposit'), 0),
    'purchases_cents', coalesce(sum(amount_cents) filter (where kind in ('purchase_personal', 'purchase_box')), 0),
    'box_purchases_cents', coalesce(sum(amount_cents) filter (where kind = 'purchase_box'), 0),
    'transfers_cents', coalesce(sum(amount_cents) filter (where kind = 'transfer'), 0),
    'reimbursements_cents', coalesce(sum(amount_cents) filter (where kind = 'reimbursement'), 0)
  )
  from public.transactions
  where group_id = p_group and status in ('pending', 'disputed')
$$;

create function public.get_group_overview(
  p_group_id uuid,
  p_cycle_id uuid default null,
  p_all_time boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cycle public.accounting_cycles;
  v_members jsonb;
  v_cash jsonb;
begin
  perform private.require_member(p_group_id);
  v_cycle := private.require_cycle_of_group(p_group_id, p_cycle_id);

  select jsonb_build_object(
    'coffees', coalesce(sum(r.coffees), 0),
    'consumption_cents', coalesce(sum(r.consumption_cents), 0),
    'deposits_cents', coalesce(sum(r.deposits_cents), 0),
    'personal_purchases_cents', coalesce(sum(r.personal_purchases_cents), 0),
    'transfers_cents', coalesce(sum(r.transfers_sent_cents), 0),
    'reimbursements_cents', coalesce(sum(r.reimbursements_cents), 0),
    'balance_adjustments_cents', coalesce(sum(r.adjustments_cents), 0),
    'opening_member_cents', coalesce(sum(r.opening_cents), 0),
    'debts_cents', coalesce(sum(r.closing_cents) filter (where r.closing_cents > 0), 0),
    'credits_cents', coalesce(-sum(r.closing_cents) filter (where r.closing_cents < 0), 0),
    'net_position_cents', coalesce(sum(r.closing_cents), 0),
    'members_owing', count(*) filter (where r.closing_cents > 0),
    'members_owed', count(*) filter (where r.closing_cents < 0),
    'members_settled', count(*) filter (where r.closing_cents = 0)
  ) into v_members
  from private.balance_rows(p_group_id, v_cycle.id, p_all_time) r;

  select jsonb_build_object(
    'opening_cash_cents', c.opening_cash_cents,
    'box_purchases_cents', c.box_purchases_cents,
    'cash_reimbursements_cents', c.reimbursements_cents,
    'cash_adjustments_cents', c.cash_adjustments_cents,
    'cash_deposits_cents', c.deposits_cents,
    'cash_box_cents', c.closing_cash_cents
  ) into v_cash
  from private.cash_rows(p_group_id, v_cycle.id, p_all_time) c;

  return v_members || v_cash || jsonb_build_object(
    'scope', case when p_all_time then 'all_time' else 'cycle' end,
    'cycle', private.cycle_json(v_cycle),
    'active_members', (select count(*) from public.group_members where group_id = p_group_id and status = 'active'),
    'pending', private.pending_summary(p_group_id)
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- Activity feed (cursor pagination)
-- -----------------------------------------------------------------------------

create function public.get_activity(
  p_group_id uuid,
  p_limit integer default 30,
  p_before_at timestamptz default null,
  p_before_id uuid default null,
  p_member_id uuid default null,
  p_types text[] default null,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_cycle_id uuid default null,
  p_statuses public.txn_status[] default null
)
returns table (
  item_type text,
  id uuid,
  kind public.txn_kind,
  status public.txn_status,
  amount_cents bigint,
  quantity integer,
  unit_price_cents integer,
  direction smallint,
  member_id uuid,
  member_name text,
  counterparty_id uuid,
  counterparty_name text,
  initiated_by uuid,
  initiator_name text,
  occurred_at timestamptz,
  created_at timestamptz,
  description text,
  reverses_id uuid,
  reversed_kind public.txn_kind,
  cycle_id uuid,
  cycle_name text,
  has_evidence boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_kinds public.txn_kind[];
  v_cycles boolean := p_types is null or 'cycle' = any (p_types);
  v_limit integer := least(greatest(coalesce(p_limit, 30), 1), 100);
begin
  perform private.require_member(p_group_id);
  if p_types is not null then
    select coalesce(array_agg(k), '{}') into v_kinds
    from unnest(enum_range(null::public.txn_kind)) k
    where (k = 'coffee' and 'coffee' = any (p_types))
       or (k = 'deposit' and 'deposit' = any (p_types))
       or (k in ('purchase_personal', 'purchase_box') and 'purchase' = any (p_types))
       or (k = 'transfer' and 'transfer' = any (p_types))
       or (k = 'reimbursement' and 'reimbursement' = any (p_types))
       or (k in ('cash_adjustment', 'balance_adjustment') and 'adjustment' = any (p_types))
       or (k = 'reversal' and 'reversal' = any (p_types));
  end if;
  v_cycles := v_cycles and p_member_id is null and p_statuses is null;

  return query
  select * from (
    select 'transaction'::text, t.id, t.kind, t.status, t.amount_cents, t.quantity, t.unit_price_cents, t.direction,
      t.member_id, pm.display_name, t.counterparty_id, pc.display_name, t.initiated_by, pi.display_name,
      t.occurred_at, t.created_at, t.description, t.reverses_id, o.kind, t.cycle_id, c.name,
      t.evidence_path is not null
    from public.transactions t
    join public.accounting_cycles c on c.id = t.cycle_id
    left join public.profiles pm on pm.id = t.member_id
    left join public.profiles pc on pc.id = t.counterparty_id
    left join public.profiles pi on pi.id = t.initiated_by
    left join public.transactions o on o.id = t.reverses_id
    where t.group_id = p_group_id
      and (v_kinds is null or t.kind = any (v_kinds))
      and (p_member_id is null or p_member_id in (t.member_id, t.counterparty_id, t.initiated_by))
      and (p_from is null or t.created_at >= p_from)
      and (p_to is null or t.created_at < p_to)
      and (p_cycle_id is null or t.cycle_id = p_cycle_id)
      and (p_statuses is null or t.status = any (p_statuses))
      and (p_before_at is null or (t.created_at, t.id) < (p_before_at, coalesce(p_before_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    union all
    select 'cycle_opened'::text, c.id, null, null, null, null, null, null, null, null, null, null,
      c.opened_by, private.display_name(c.opened_by), c.opened_at, c.opened_at, null, null, null, c.id, c.name, false
    from public.accounting_cycles c
    where v_cycles and c.group_id = p_group_id
      and (p_from is null or c.opened_at >= p_from)
      and (p_to is null or c.opened_at < p_to)
      and (p_cycle_id is null or c.id = p_cycle_id)
      and (p_before_at is null or (c.opened_at, c.id) < (p_before_at, coalesce(p_before_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    union all
    select 'cycle_closed'::text, c.id, null, null, null, null, null, null, null, null, null, null,
      c.closed_by, private.display_name(c.closed_by), c.closed_at, c.closed_at, c.close_note, null, null, c.id, c.name, false
    from public.accounting_cycles c
    where v_cycles and c.group_id = p_group_id and c.status = 'closed'
      and (p_from is null or c.closed_at >= p_from)
      and (p_to is null or c.closed_at < p_to)
      and (p_cycle_id is null or c.id = p_cycle_id)
      and (p_before_at is null or (c.closed_at, c.id) < (p_before_at, coalesce(p_before_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
  ) as items (item_type, id, kind, status, amount_cents, quantity, unit_price_cents, direction, member_id,
              member_name, counterparty_id, counterparty_name, initiated_by, initiator_name, occurred_at,
              created_at, description, reverses_id, reversed_kind, cycle_id, cycle_name, has_evidence)
  order by items.created_at desc, items.id desc
  limit v_limit;
end;
$$;

create function public.get_transaction(p_transaction_id uuid) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_role public.member_role;
  v_window integer;
  t public.transactions;
  v_reversal public.transactions;
  v_original public.transactions;
  v_disputed_before boolean;
begin
  select * into t from public.transactions where id = p_transaction_id;
  if t.id is null then
    perform private.fail('not_found', 'Transaction not found.');
  end if;
  v_role := private.require_member(t.group_id);
  select * into v_reversal from public.transactions where reverses_id = t.id;
  select * into v_original from public.transactions where id = t.reverses_id;
  select member_undo_window_minutes into v_window from public.groups where id = t.group_id;
  v_disputed_before := exists (select 1 from public.transaction_events e
                               where e.transaction_id = t.id and e.to_status = 'disputed');

  return jsonb_build_object(
    'transaction', to_jsonb(t) || jsonb_build_object(
      'member_name', private.display_name(t.member_id),
      'counterparty_name', private.display_name(t.counterparty_id),
      'initiator_name', private.display_name(t.initiated_by),
      'cycle_name', (select name from public.accounting_cycles where id = t.cycle_id),
      'cycle_status', (select status from public.accounting_cycles where id = t.cycle_id)),
    'events', coalesce((
      select jsonb_agg(jsonb_build_object(
        'from_status', e.from_status, 'to_status', e.to_status, 'actor_id', e.actor_id,
        'actor_name', private.display_name(e.actor_id), 'note', e.note, 'created_at', e.created_at) order by e.id)
      from public.transaction_events e where e.transaction_id = t.id), '[]'::jsonb),
    'reversal', case when v_reversal.id is null then null else jsonb_build_object(
      'id', v_reversal.id, 'created_at', v_reversal.created_at, 'description', v_reversal.description,
      'initiator_name', private.display_name(v_reversal.initiated_by)) end,
    'reverses', case when v_original.id is null then null else jsonb_build_object(
      'id', v_original.id, 'kind', v_original.kind, 'amount_cents', v_original.amount_cents,
      'created_at', v_original.created_at, 'member_name', private.display_name(v_original.member_id)) end,
    'permissions', jsonb_build_object(
      'can_decide', private.can_decide(t, v_actor, v_role),
      'can_cancel', t.status = 'pending' and t.initiated_by = v_actor,
      'can_dispute', t.status = 'rejected' and t.initiated_by = v_actor and not v_disputed_before,
      'can_resolve', exists (select 1 from private.awaiting_decision(t.group_id, v_actor, v_role) a
                             where a.id = t.id and a.status = 'disputed'),
      'can_reverse', v_role = 'admin' and t.status = 'posted' and t.kind <> 'reversal',
      'can_undo', t.kind = 'coffee' and t.status = 'posted' and t.member_id = v_actor
        and t.initiated_by = v_actor and t.created_at >= now() - make_interval(mins => v_window)
        and exists (select 1 from public.accounting_cycles c where c.id = t.cycle_id and c.status = 'open')
    )
  );
end;
$$;

create function private.activity_json(t public.transactions) returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'item_type', 'transaction',
    'id', t.id, 'kind', t.kind, 'status', t.status, 'amount_cents', t.amount_cents,
    'quantity', t.quantity, 'unit_price_cents', t.unit_price_cents, 'direction', t.direction,
    'member_id', t.member_id, 'member_name', private.display_name(t.member_id),
    'counterparty_id', t.counterparty_id, 'counterparty_name', private.display_name(t.counterparty_id),
    'initiated_by', t.initiated_by, 'initiator_name', private.display_name(t.initiated_by),
    'occurred_at', t.occurred_at, 'created_at', t.created_at, 'description', t.description,
    'reverses_id', t.reverses_id, 'cycle_id', t.cycle_id,
    'cycle_name', (select name from public.accounting_cycles where id = t.cycle_id),
    'has_evidence', t.evidence_path is not null
  )
$$;

create function public.get_pending_actions(p_group_id uuid) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_role public.member_role := private.require_member(p_group_id);
  v_review jsonb;
  v_mine jsonb;
begin
  select coalesce(jsonb_agg(private.activity_json(a) order by a.created_at), '[]'::jsonb) into v_review
  from private.awaiting_decision(p_group_id, v_actor, v_role) a;

  select coalesce(jsonb_agg(private.activity_json(t) order by t.created_at), '[]'::jsonb) into v_mine
  from public.transactions t
  where t.group_id = p_group_id and t.initiated_by = v_actor and t.status in ('pending', 'disputed');

  return jsonb_build_object('to_review', v_review, 'my_submissions', v_mine,
    'counts', jsonb_build_object('to_review', jsonb_array_length(v_review), 'my_submissions', jsonb_array_length(v_mine)));
end;
$$;

-- -----------------------------------------------------------------------------
-- Personal dashboard
-- -----------------------------------------------------------------------------

create function public.get_dashboard(p_group_id uuid) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_role public.member_role := private.require_member(p_group_id);
  v_group public.groups;
  v_cycle public.accounting_cycles;
  v_member public.group_members;
  v_me record;
  v_next record;
  v_tz text;
begin
  select * into v_group from public.groups where id = p_group_id;
  v_tz := v_group.timezone;
  select * into v_cycle from public.accounting_cycles where group_id = p_group_id and status = 'open';
  select * into v_member from public.group_members where group_id = p_group_id and user_id = v_actor;
  select * into v_me from private.cycle_member_rows(p_group_id, v_cycle.id) r where r.user_id = v_actor;
  select price_cents, effective_from into v_next from public.coffee_prices
  where group_id = p_group_id and effective_from > now() order by effective_from limit 1;

  return jsonb_build_object(
    'group', jsonb_build_object(
      'id', v_group.id, 'name', v_group.name, 'currency', v_group.currency, 'timezone', v_group.timezone,
      'require_deposit_confirmation', v_group.require_deposit_confirmation,
      'require_purchase_approval', v_group.require_purchase_approval,
      'member_undo_window_minutes', v_group.member_undo_window_minutes),
    'me', jsonb_build_object(
      'user_id', v_actor, 'display_name', private.display_name(v_actor), 'role', v_role,
      'joined_at', v_member.joined_at),
    'cycle', private.cycle_json(v_cycle),
    'price_cents', private.price_at(p_group_id, now()),
    'next_price', case when v_next.price_cents is null then null else jsonb_build_object(
      'price_cents', v_next.price_cents, 'effective_from', v_next.effective_from) end,
    'balance', jsonb_build_object(
      'opening_cents', coalesce(v_me.opening_cents, 0),
      'coffees', coalesce(v_me.coffees, 0),
      'consumption_cents', coalesce(v_me.consumption_cents, 0),
      'deposits_cents', coalesce(v_me.deposits_cents, 0),
      'personal_purchases_cents', coalesce(v_me.personal_purchases_cents, 0),
      'transfers_sent_cents', coalesce(v_me.transfers_sent_cents, 0),
      'transfers_received_cents', coalesce(v_me.transfers_received_cents, 0),
      'reimbursements_cents', coalesce(v_me.reimbursements_cents, 0),
      'adjustments_cents', coalesce(v_me.adjustments_cents, 0),
      'net_cents', coalesce(v_me.closing_cents, 0)),
    'today_coffees', (
      select coalesce(sum(t.quantity), 0) from public.transactions t
      where t.group_id = p_group_id and t.kind = 'coffee' and t.status = 'posted' and t.member_id = v_actor
        and t.occurred_at >= (date_trunc('day', now() at time zone v_tz) at time zone v_tz)),
    'all_time', jsonb_build_object(
      'coffees', (select coalesce(sum(t.quantity), 0) from public.transactions t
                  where t.group_id = p_group_id and t.kind = 'coffee' and t.status = 'posted'
                    and t.member_id = v_actor),
      'net_cents', private.member_balance(p_group_id, v_actor)),
    'pending', jsonb_build_object(
      'to_review', (select count(*) from private.awaiting_decision(p_group_id, v_actor, v_role)),
      'my_submissions', (select count(*) from public.transactions t
                         where t.group_id = p_group_id and t.initiated_by = v_actor
                           and t.status in ('pending', 'disputed'))),
    'unread_notifications', (select count(*) from public.notifications n
                             where n.user_id = v_actor and n.read_at is null),
    'recent', coalesce((
      select jsonb_agg(private.activity_json(t) order by t.created_at desc)
      from public.transactions t
      where t.id in (
        select x.id from public.transactions x
        where x.group_id = p_group_id
          and v_actor in (x.member_id, x.counterparty_id, x.initiated_by)
        order by x.created_at desc
        limit 6)), '[]'::jsonb)
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- Coffee Heroes
-- -----------------------------------------------------------------------------

create function private.visible_on_leaderboard(p_user uuid) returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce((select show_on_leaderboard from public.user_preferences where user_id = p_user), true)
$$;

create function public.get_leaderboard(p_group_id uuid, p_period text default 'cycle', p_cycle_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_tz text;
  v_start timestamptz;
  v_cycle public.accounting_cycles;
  v_rows jsonb;
  v_total bigint;
begin
  perform private.require_member(p_group_id);
  v_tz := private.group_timezone(p_group_id);
  if p_period = 'week' then
    v_start := date_trunc('week', now() at time zone v_tz) at time zone v_tz;
  elsif p_period = 'month' then
    v_start := date_trunc('month', now() at time zone v_tz) at time zone v_tz;
  elsif p_period = 'cycle' then
    v_cycle := private.require_cycle_of_group(p_group_id, p_cycle_id);
  elsif p_period is distinct from 'all_time' then
    perform private.fail('invalid_request', 'Choose week, month, cycle or all_time.');
  end if;

  with counts as (
    select t.member_id as user_id, sum(t.quantity)::integer as coffees
    from public.transactions t
    where t.group_id = p_group_id and t.kind = 'coffee' and t.status = 'posted'
      and (v_start is null or t.occurred_at >= v_start)
      and (v_cycle.id is null or t.cycle_id = v_cycle.id)
    group by t.member_id
  )
  select coalesce(sum(c.coffees), 0),
    coalesce(jsonb_agg(jsonb_build_object(
      'user_id', c.user_id, 'display_name', p.display_name, 'avatar_path', p.avatar_path,
      'coffees', c.coffees, 'is_me', c.user_id = v_actor,
      'is_hidden', not private.visible_on_leaderboard(c.user_id))
      order by c.coffees desc, lower(p.display_name))
      filter (where private.visible_on_leaderboard(c.user_id) or c.user_id = v_actor), '[]'::jsonb)
  into v_total, v_rows
  from counts c
  join public.profiles p on p.id = c.user_id;

  return jsonb_build_object(
    'period', p_period,
    'period_start', v_start,
    'cycle', private.cycle_json(v_cycle),
    'total_coffees', v_total,
    'rows', v_rows
  );
end;
$$;

create function private.ensure_monthly_awards(p_group uuid) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_tz text := private.group_timezone(p_group);
  v_this_month date := date_trunc('month', now() at time zone v_tz)::date;
  v_first date;
  v_month date;
  v_winners jsonb;
  v_user uuid;
begin
  select greatest(date_trunc('month', created_at at time zone v_tz)::date, (v_this_month - interval '12 months')::date)
  into v_first
  from public.groups where id = p_group;

  if not exists (
    select 1 from generate_series(v_first, (v_this_month - interval '1 month')::date, interval '1 month') m
    where not exists (select 1 from public.monthly_award_runs r where r.group_id = p_group and r.month = m::date)
  ) then
    return;
  end if;

  perform private.lock_group(p_group);
  for v_month in
    select m::date from generate_series(v_first, (v_this_month - interval '1 month')::date, interval '1 month') m
    where not exists (select 1 from public.monthly_award_runs r where r.group_id = p_group and r.month = m::date)
    order by 1
  loop
    with counts as (
      select t.member_id as user_id, sum(t.quantity)::integer as coffees
      from public.transactions t
      where t.group_id = p_group and t.kind = 'coffee' and t.status = 'posted'
        and t.occurred_at >= (v_month::timestamp at time zone v_tz)
        and t.occurred_at < ((v_month + interval '1 month')::timestamp at time zone v_tz)
        and private.visible_on_leaderboard(t.member_id)
      group by t.member_id
    ),
    inserted as (
      insert into public.monthly_awards (group_id, month, user_id, coffees)
      select p_group, v_month, c.user_id, c.coffees from counts c
      where c.coffees = (select max(coffees) from counts)
      returning user_id, coffees
    )
    select coalesce(jsonb_agg(jsonb_build_object('user_id', i.user_id, 'display_name', private.display_name(i.user_id),
      'coffees', i.coffees)), '[]'::jsonb)
    into v_winners from inserted i;

    insert into public.monthly_award_runs (group_id, month) values (p_group, v_month);

    -- Only announce the most recent completed month; older back-filled months stay quiet.
    if jsonb_array_length(v_winners) > 0 and v_month = (v_this_month - interval '1 month')::date then
      for v_user in select user_id from public.group_members where group_id = p_group and status = 'active' loop
        perform private.notify(v_user, p_group, 'coffee_hero', null,
          jsonb_build_object('month', v_month, 'winners', v_winners), null);
      end loop;
    end if;
  end loop;
end;
$$;

create function public.get_monthly_awards(p_group_id uuid, p_limit integer default 6) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_member(p_group_id);
  perform private.ensure_monthly_awards(p_group_id);
  return coalesce((
    select jsonb_agg(m.award order by m.month desc)
    from (
      select a.month, jsonb_build_object('month', a.month, 'winners', jsonb_agg(jsonb_build_object(
        'user_id', a.user_id, 'display_name', p.display_name, 'avatar_path', p.avatar_path, 'coffees', a.coffees)
        order by lower(p.display_name))) as award
      from public.monthly_awards a
      join public.profiles p on p.id = a.user_id
      where a.group_id = p_group_id
      group by a.month
      order by a.month desc
      limit least(greatest(coalesce(p_limit, 6), 1), 24)
    ) m), '[]'::jsonb);
end;
$$;

-- Facts for achievements, streaks and fun statistics of the caller.
create function public.get_my_stats(p_group_id uuid) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_tz text;
  v_cycle uuid;
  v_week_start timestamptz;
  v_month_start timestamptz;
  v_result jsonb;
begin
  perform private.require_member(p_group_id);
  v_tz := private.group_timezone(p_group_id);
  v_cycle := private.open_cycle_id(p_group_id);
  v_week_start := date_trunc('week', now() at time zone v_tz) at time zone v_tz;
  v_month_start := date_trunc('month', now() at time zone v_tz) at time zone v_tz;

  with mine as (
    select t.quantity, t.cycle_id, t.occurred_at, (t.occurred_at at time zone v_tz) as local_at
    from public.transactions t
    where t.group_id = p_group_id and t.kind = 'coffee' and t.status = 'posted' and t.member_id = v_actor
  ),
  grp as (
    select t.member_id, t.quantity, t.occurred_at, (t.occurred_at at time zone v_tz) as local_at
    from public.transactions t
    where t.group_id = p_group_id and t.kind = 'coffee' and t.status = 'posted' and t.occurred_at >= v_month_start
  )
  select jsonb_build_object(
    'total_coffees', (select coalesce(sum(quantity), 0) from mine),
    'cycle_coffees', (select coalesce(sum(quantity), 0) from mine where cycle_id = v_cycle),
    'distinct_days', (select count(distinct local_at::date) from mine),
    'early_bird_coffees', (select coalesce(sum(quantity), 0) from mine
                           where extract(hour from local_at) >= 4 and extract(hour from local_at) < 8),
    'night_owl_coffees', (select coalesce(sum(quantity), 0) from mine
                          where extract(hour from local_at) >= 20 or extract(hour from local_at) < 4),
    'coffee_dates', coalesce((select jsonb_agg(d order by d) from (
                       select distinct local_at::date as d from mine
                       where local_at::date > (now() at time zone v_tz)::date - 120) days), '[]'::jsonb),
    'favorite_hour', (select extract(hour from local_at)::integer from mine
                      group by 1 order by sum(quantity) desc, 1 limit 1),
    'week_coffees', (select coalesce(sum(quantity), 0) from mine where occurred_at >= v_week_start),
    'month_coffees', (select coalesce(sum(quantity), 0) from mine where occurred_at >= v_month_start),
    'group_week_coffees', (select coalesce(sum(quantity), 0) from grp where occurred_at >= v_week_start),
    'group_month_coffees', (select coalesce(sum(quantity), 0) from grp),
    'group_week_busiest_hour', (select extract(hour from local_at)::integer from grp
                                where occurred_at >= v_week_start
                                group by 1 order by sum(quantity) desc, 1 limit 1),
    'group_month_busiest_weekday', (select extract(isodow from local_at)::integer from grp
                                    group by 1 order by sum(quantity) desc, 1 limit 1),
    'bean_purchases', (select count(*) from public.transactions t
                       where t.group_id = p_group_id and t.member_id = v_actor and t.status = 'posted'
                         and t.kind in ('purchase_personal', 'purchase_box')),
    'personal_purchases', (select count(*) from public.transactions t
                           where t.group_id = p_group_id and t.member_id = v_actor and t.status = 'posted'
                             and t.kind = 'purchase_personal'),
    'personal_purchase_cents', (select coalesce(sum(t.amount_cents), 0) from public.transactions t
                                where t.group_id = p_group_id and t.member_id = v_actor and t.status = 'posted'
                                  and t.kind = 'purchase_personal'),
    'settlements', (select count(*) from public.transactions t
                    where t.group_id = p_group_id and t.status = 'posted'
                      and t.kind in ('deposit', 'transfer', 'reimbursement')
                      and v_actor in (t.member_id, t.counterparty_id)),
    'balance_cents', private.member_balance(p_group_id, v_actor),
    'joined_at', (select joined_at from public.group_members where group_id = p_group_id and user_id = v_actor),
    'timezone', v_tz
  ) into v_result;
  return v_result;
end;
$$;

-- -----------------------------------------------------------------------------
-- Analytics
-- -----------------------------------------------------------------------------

create function public.get_analytics(p_group_id uuid, p_from date, p_to date) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_tz text;
  v_from_at timestamptz;
  v_to_at timestamptz;
  v_open public.accounting_cycles;
  v_previous public.accounting_cycles;
  v_result jsonb;
begin
  perform private.require_member(p_group_id);
  if p_from is null or p_to is null or p_to < p_from then
    perform private.fail('invalid_request', 'Choose a valid date range.');
  end if;
  if p_to - p_from > 731 then
    perform private.fail('invalid_request', 'Date ranges are limited to two years.');
  end if;
  v_tz := private.group_timezone(p_group_id);
  v_from_at := p_from::timestamp at time zone v_tz;
  v_to_at := (p_to + 1)::timestamp at time zone v_tz;
  select * into v_open from public.accounting_cycles where group_id = p_group_id and status = 'open';
  select * into v_previous from public.accounting_cycles where id = private.previous_cycle_id(v_open.id);

  with coffees as (
    select t.member_id, t.quantity, t.amount_cents, (t.occurred_at at time zone v_tz) as local_at
    from public.transactions t
    where t.group_id = p_group_id and t.kind = 'coffee' and t.status = 'posted'
      and t.occurred_at >= v_from_at and t.occurred_at < v_to_at
  ),
  days as (
    select d::date as day from generate_series(p_from, p_to, interval '1 day') d
  ),
  daily as (
    select d.day,
      coalesce(sum(c.quantity), 0) as group_coffees,
      coalesce(sum(c.quantity) filter (where c.member_id = v_actor), 0) as my_coffees,
      coalesce(sum(c.amount_cents), 0) as group_spend_cents,
      coalesce(sum(c.amount_cents) filter (where c.member_id = v_actor), 0) as my_spend_cents
    from days d
    left join coffees c on c.local_at::date = d.day
    group by d.day
  ),
  cash_daily as (
    select (e.created_at at time zone v_tz)::date as day, sum(e.amount_cents) as delta
    from public.ledger_entries e
    where e.group_id = p_group_id and e.account = 'cash_box' and e.created_at < v_to_at
    group by 1
  ),
  cash_start as (
    select coalesce(sum(delta), 0) as cents from cash_daily where day < p_from
  ),
  cash_series as (
    select d.day,
      (select cents from cash_start)
        + sum(coalesce(cd.delta, 0)) over (order by d.day rows between unbounded preceding and current row) as balance
    from days d
    left join cash_daily cd on cd.day = d.day
  ),
  participation as (
    select c.member_id, sum(c.quantity) as coffees
    from coffees c group by c.member_id
  )
  select jsonb_build_object(
    'from', p_from,
    'to', p_to,
    'timezone', v_tz,
    'totals', jsonb_build_object(
      'group_coffees', (select coalesce(sum(group_coffees), 0) from daily),
      'my_coffees', (select coalesce(sum(my_coffees), 0) from daily),
      'group_spend_cents', (select coalesce(sum(group_spend_cents), 0) from daily),
      'my_spend_cents', (select coalesce(sum(my_spend_cents), 0) from daily)),
    'daily', (select jsonb_agg(jsonb_build_object('date', day, 'group_coffees', group_coffees,
                'my_coffees', my_coffees, 'group_spend_cents', group_spend_cents, 'my_spend_cents', my_spend_cents)
                order by day) from daily),
    'weekday', (select jsonb_agg(jsonb_build_object('weekday', w, 'group_coffees', coalesce(g, 0), 'my_coffees', coalesce(m, 0))
                  order by w)
                from (select w, (select sum(quantity) from coffees where extract(isodow from local_at) = w) as g,
                             (select sum(quantity) from coffees where extract(isodow from local_at) = w
                                and member_id = v_actor) as m
                      from generate_series(1, 7) w) x),
    'hourly', (select jsonb_agg(jsonb_build_object('hour', h, 'group_coffees', coalesce(g, 0), 'my_coffees', coalesce(m, 0))
                 order by h)
               from (select h, (select sum(quantity) from coffees where extract(hour from local_at) = h) as g,
                            (select sum(quantity) from coffees where extract(hour from local_at) = h
                               and member_id = v_actor) as m
                     from generate_series(0, 23) h) x),
    'cash_box', (select jsonb_agg(jsonb_build_object('date', day, 'balance_cents', balance) order by day)
                 from cash_series),
    'purchases', coalesce((
      select jsonb_agg(jsonb_build_object('id', t.id, 'date', (t.occurred_at at time zone v_tz)::date,
        'amount_cents', t.amount_cents, 'funding', case when t.kind = 'purchase_box' then 'cash_box' else 'personal' end,
        'member_name', private.display_name(t.member_id), 'description', t.description)
        order by t.occurred_at)
      from public.transactions t
      where t.group_id = p_group_id and t.status = 'posted' and t.kind in ('purchase_personal', 'purchase_box')
        and t.occurred_at >= v_from_at and t.occurred_at < v_to_at), '[]'::jsonb),
    'participation', jsonb_build_object(
      'active_members', (select count(*) from public.group_members where group_id = p_group_id and status = 'active'),
      'consuming_members', (select count(*) from participation),
      'members', coalesce((
        select jsonb_agg(jsonb_build_object(
          'user_id', case when private.visible_on_leaderboard(pt.member_id) or pt.member_id = v_actor
                          then pt.member_id end,
          'display_name', case when private.visible_on_leaderboard(pt.member_id) or pt.member_id = v_actor
                               then private.display_name(pt.member_id) end,
          'coffees', pt.coffees, 'is_me', pt.member_id = v_actor) order by pt.coffees desc)
        from participation pt), '[]'::jsonb)),
    'cycle_comparison', jsonb_build_object(
      'current', (select jsonb_build_object('cycle', private.cycle_json(v_open),
          'coffees', coalesce(sum(r.coffees), 0), 'consumption_cents', coalesce(sum(r.consumption_cents), 0),
          'deposits_cents', coalesce(sum(r.deposits_cents), 0),
          'personal_purchases_cents', coalesce(sum(r.personal_purchases_cents), 0),
          'consumers', count(*) filter (where r.coffees > 0),
          'days', greatest(1, ceil(extract(epoch from (now() - v_open.opened_at)) / 86400)::integer))
        from private.cycle_member_rows(p_group_id, v_open.id) r),
      'previous', case when v_previous.id is null then null else (
        select jsonb_build_object('cycle', private.cycle_json(v_previous),
          'coffees', coalesce(sum(b.coffees), 0), 'consumption_cents', coalesce(sum(b.consumption_cents), 0),
          'deposits_cents', coalesce(sum(b.deposits_cents), 0),
          'personal_purchases_cents', coalesce(sum(b.personal_purchases_cents), 0),
          'consumers', count(*) filter (where b.coffees > 0),
          'days', greatest(1, ceil(extract(epoch from (v_previous.closed_at - v_previous.opened_at)) / 86400)::integer))
        from public.cycle_member_balances b where b.cycle_id = v_previous.id) end)
  ) into v_result;
  return v_result;
end;
$$;

-- -----------------------------------------------------------------------------
-- Cycles and reports
-- -----------------------------------------------------------------------------

create function public.get_cycles(p_group_id uuid)
returns table (
  id uuid,
  sequence_no integer,
  name text,
  status public.cycle_status,
  opened_at timestamptz,
  closed_at timestamptz,
  opened_by_name text,
  closed_by_name text,
  coffees bigint,
  consumption_cents bigint,
  closing_cash_cents bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_member(p_group_id);
  return query
    select c.id, c.sequence_no, c.name, c.status, c.opened_at, c.closed_at,
      private.display_name(c.opened_by), private.display_name(c.closed_by),
      coalesce((select sum(r.coffees) from private.balance_rows(p_group_id, c.id, false) r), 0)::bigint,
      coalesce((select sum(r.consumption_cents) from private.balance_rows(p_group_id, c.id, false) r), 0)::bigint,
      (select x.closing_cash_cents from private.cash_rows(p_group_id, c.id, false) x)
    from public.accounting_cycles c
    where c.group_id = p_group_id
    order by c.sequence_no desc;
end;
$$;

create function public.get_cycle_report(p_cycle_id uuid) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cycle public.accounting_cycles;
  v_group public.groups;
begin
  select * into v_cycle from public.accounting_cycles where id = p_cycle_id;
  if v_cycle.id is null then
    perform private.fail('not_found', 'Accounting cycle not found.');
  end if;
  perform private.require_member(v_cycle.group_id);
  select * into v_group from public.groups where id = v_cycle.group_id;

  return jsonb_build_object(
    'group', jsonb_build_object('id', v_group.id, 'name', v_group.name, 'currency', v_group.currency,
      'timezone', v_group.timezone),
    'cycle', private.cycle_json(v_cycle),
    'is_final', v_cycle.status = 'closed',
    'generated_at', now(),
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id', r.user_id, 'display_name', p.display_name, 'membership_status', gm.status,
        'opening_cents', r.opening_cents, 'coffees', r.coffees, 'consumption_cents', r.consumption_cents,
        'deposits_cents', r.deposits_cents, 'personal_purchases_cents', r.personal_purchases_cents,
        'transfers_sent_cents', r.transfers_sent_cents, 'transfers_received_cents', r.transfers_received_cents,
        'reimbursements_cents', r.reimbursements_cents, 'adjustments_cents', r.adjustments_cents,
        'closing_cents', r.closing_cents) order by lower(p.display_name))
      from private.balance_rows(v_cycle.group_id, v_cycle.id, false) r
      join public.profiles p on p.id = r.user_id
      join public.group_members gm on gm.group_id = v_cycle.group_id and gm.user_id = r.user_id
      where gm.status = 'active' or r.closing_cents <> 0 or r.coffees <> 0 or r.opening_cents <> 0), '[]'::jsonb),
    'cash', (select to_jsonb(c) from private.cash_rows(v_cycle.group_id, v_cycle.id, false) c),
    'pending', case when v_cycle.status = 'open' then private.pending_summary(v_cycle.group_id) end
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- Cash box, settlement inputs, audit, export, integrity
-- -----------------------------------------------------------------------------

create function public.get_cash_box(p_group_id uuid) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_member(p_group_id);
  return jsonb_build_object(
    'expected_cents', private.cash_balance(p_group_id),
    'pending_deposits', (select jsonb_build_object('count', count(*), 'cents', coalesce(sum(amount_cents), 0))
                         from public.transactions where group_id = p_group_id and status in ('pending', 'disputed')
                           and kind = 'deposit'),
    'pending_outflows', (select jsonb_build_object('count', count(*), 'cents', coalesce(sum(amount_cents), 0))
                         from public.transactions where group_id = p_group_id and status in ('pending', 'disputed')
                           and kind in ('purchase_box', 'reimbursement')),
    'reconciliations', coalesce((
      select jsonb_agg(x.item order by x.created_at desc) from (
        select r.created_at, jsonb_build_object('id', r.id, 'expected_cents', r.expected_cents,
          'counted_cents', r.counted_cents, 'difference_cents', r.counted_cents - r.expected_cents,
          'note', r.note, 'adjustment_transaction_id', r.adjustment_transaction_id,
          'created_by_name', private.display_name(r.created_by), 'created_at', r.created_at) as item
        from public.cash_reconciliations r
        where r.group_id = p_group_id
        order by r.created_at desc
        limit 20) x), '[]'::jsonb)
  );
end;
$$;

create function public.get_settlement_inputs(p_group_id uuid) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_member(p_group_id);
  return jsonb_build_object(
    'cash_box_cents', private.cash_balance(p_group_id),
    'pending_box_outflow_cents', (
      select coalesce(sum(amount_cents), 0) from public.transactions
      where group_id = p_group_id and status in ('pending', 'disputed') and kind in ('purchase_box', 'reimbursement')),
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id', b.user_id, 'display_name', p.display_name, 'active', gm.status = 'active',
        'net_cents', b.net,
        'pending_out_cents', coalesce(po.cents, 0),
        'pending_in_cents', coalesce(pi.cents, 0),
        'pending_reimbursement_cents', coalesce(pr.cents, 0)) order by lower(p.display_name))
      from (
        select e.member_id as user_id, sum(e.amount_cents) as net
        from public.ledger_entries e
        where e.group_id = p_group_id and e.account = 'member'
        group by e.member_id
      ) b
      join public.profiles p on p.id = b.user_id
      join public.group_members gm on gm.group_id = p_group_id and gm.user_id = b.user_id
      left join lateral (select sum(t.amount_cents) as cents from public.transactions t
                         where t.group_id = p_group_id and t.kind = 'transfer'
                           and t.status in ('pending', 'disputed') and t.member_id = b.user_id) po on true
      left join lateral (select sum(t.amount_cents) as cents from public.transactions t
                         where t.group_id = p_group_id and t.kind = 'transfer'
                           and t.status in ('pending', 'disputed') and t.counterparty_id = b.user_id) pi on true
      left join lateral (select sum(t.amount_cents) as cents from public.transactions t
                         where t.group_id = p_group_id and t.kind = 'reimbursement'
                           and t.status in ('pending', 'disputed') and t.member_id = b.user_id) pr on true
      where b.net <> 0 or po.cents is not null or pi.cents is not null or pr.cents is not null), '[]'::jsonb)
  );
end;
$$;

create function public.get_audit_log(p_group_id uuid, p_before_id bigint default null, p_limit integer default 50)
returns table (
  id bigint,
  action text,
  actor_id uuid,
  actor_name text,
  target_type text,
  target_id text,
  details jsonb,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_role(p_group_id, array['admin']::public.member_role[]);
  return query
    select a.id, a.action, a.actor_id, private.display_name(a.actor_id), a.target_type, a.target_id, a.details,
      a.created_at
    from public.audit_log a
    where a.group_id = p_group_id and (p_before_id is null or a.id < p_before_id)
    order by a.id desc
    limit least(greatest(coalesce(p_limit, 50), 1), 200);
end;
$$;

create function public.export_transactions(p_group_id uuid, p_from timestamptz default null,
  p_to timestamptz default null)
returns table (
  id uuid,
  created_at timestamptz,
  occurred_at timestamptz,
  cycle_name text,
  kind public.txn_kind,
  status public.txn_status,
  amount_cents bigint,
  quantity integer,
  unit_price_cents integer,
  direction smallint,
  member_name text,
  counterparty_name text,
  initiator_name text,
  description text,
  reverses_id uuid
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_role(p_group_id, array['treasurer', 'admin']::public.member_role[]);
  return query
    select t.id, t.created_at, t.occurred_at, c.name, t.kind, t.status, t.amount_cents, t.quantity,
      t.unit_price_cents, t.direction, private.display_name(t.member_id), private.display_name(t.counterparty_id),
      private.display_name(t.initiated_by), t.description, t.reverses_id
    from public.transactions t
    join public.accounting_cycles c on c.id = t.cycle_id
    where t.group_id = p_group_id
      and (p_from is null or t.created_at >= p_from)
      and (p_to is null or t.created_at < p_to)
    order by t.created_at, t.id
    limit 50000;
end;
$$;

create function public.verify_ledger_integrity(p_group_id uuid) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_checks jsonb := '[]'::jsonb;
  v_value bigint;
  v_ok boolean := true;
  v_figures jsonb;
begin
  perform private.require_role(p_group_id, array['treasurer', 'admin']::public.member_role[]);

  -- 1. Every posted transaction is balanced.
  select count(*) into v_value from (
    select transaction_id from public.ledger_entries where group_id = p_group_id
    group by transaction_id having sum(amount_cents) <> 0) x;
  v_checks := v_checks || jsonb_build_object('key', 'balanced_transactions', 'ok', v_value = 0, 'value', v_value);

  -- 2. Only posted (or later reversed) transactions have ledger entries.
  select count(*) into v_value from public.transactions t
  where t.group_id = p_group_id and t.status not in ('posted', 'reversed')
    and exists (select 1 from public.ledger_entries e where e.transaction_id = t.id);
  v_checks := v_checks || jsonb_build_object('key', 'no_entries_for_open_items', 'ok', v_value = 0, 'value', v_value);

  -- 3. Every posted transaction has ledger entries.
  select count(*) into v_value from public.transactions t
  where t.group_id = p_group_id and t.status in ('posted', 'reversed')
    and not exists (select 1 from public.ledger_entries e where e.transaction_id = t.id);
  v_checks := v_checks || jsonb_build_object('key', 'posted_have_entries', 'ok', v_value = 0, 'value', v_value);

  -- 4. Each reversal exactly negates its original and each reversed item has one reversal.
  select count(*) into v_value from public.transactions r
  where r.group_id = p_group_id and r.kind = 'reversal'
    and exists (
      select e.account, e.member_id, e.category, sum(e.amount_cents)
      from public.ledger_entries e where e.transaction_id in (r.id, r.reverses_id)
      group by e.account, e.member_id, e.category having sum(e.amount_cents) <> 0);
  select v_value + count(*) into v_value from public.transactions t
  where t.group_id = p_group_id and t.status = 'reversed'
    and not exists (select 1 from public.transactions r where r.reverses_id = t.id);
  v_checks := v_checks || jsonb_build_object('key', 'reversals_match', 'ok', v_value = 0, 'value', v_value);

  -- 5. Closed-cycle snapshots still match the ledger (money columns; coffee
  --    counts are statistics and may change when an old coffee is reversed).
  select count(*) into v_value from public.accounting_cycles c
  where c.group_id = p_group_id and c.status = 'closed'
    and (
      exists (
        select 1
        from private.cycle_member_rows(p_group_id, c.id) r
        full join (select * from public.cycle_member_balances b where b.cycle_id = c.id) s on s.user_id = r.user_id
        where (coalesce(r.opening_cents, 0), coalesce(r.consumption_cents, 0), coalesce(r.deposits_cents, 0),
               coalesce(r.personal_purchases_cents, 0), coalesce(r.transfers_sent_cents, 0),
               coalesce(r.transfers_received_cents, 0), coalesce(r.reimbursements_cents, 0),
               coalesce(r.adjustments_cents, 0), coalesce(r.closing_cents, 0))
          is distinct from
              (coalesce(s.opening_cents, 0), coalesce(s.consumption_cents, 0), coalesce(s.deposits_cents, 0),
               coalesce(s.personal_purchases_cents, 0), coalesce(s.transfers_sent_cents, 0),
               coalesce(s.transfers_received_cents, 0), coalesce(s.reimbursements_cents, 0),
               coalesce(s.adjustments_cents, 0), coalesce(s.closing_cents, 0)))
      or (select r.closing_cash_cents from private.cycle_cash_row(p_group_id, c.id) r)
         is distinct from (select s.closing_cash_cents from public.cycle_cash_snapshots s where s.cycle_id = c.id));
  v_checks := v_checks || jsonb_build_object('key', 'snapshots_match_ledger', 'ok', v_value = 0, 'value', v_value);

  -- 5b. Each cycle opens with the previous cycle's closing balances.
  select count(*) into v_value
  from public.cycle_member_balances b
  join public.accounting_cycles c on c.id = b.cycle_id
  left join public.accounting_cycles p on p.group_id = c.group_id and p.sequence_no = c.sequence_no - 1
  left join public.cycle_member_balances pb on pb.cycle_id = p.id and pb.user_id = b.user_id
  where b.group_id = p_group_id and b.opening_cents <> coalesce(pb.closing_cents, 0);
  v_checks := v_checks || jsonb_build_object('key', 'opening_matches_previous_close', 'ok', v_value = 0,
    'value', v_value);

  -- 6. The cash box never went negative.
  select count(*) into v_value from (
    select sum(amount_cents) over (order by id) as running
    from public.ledger_entries where group_id = p_group_id and account = 'cash_box') x
  where x.running < 0;
  v_checks := v_checks || jsonb_build_object('key', 'cash_never_negative', 'ok', v_value = 0, 'value', v_value);

  -- 7. The whole ledger sums to zero.
  select coalesce(sum(amount_cents), 0) into v_value from public.ledger_entries where group_id = p_group_id;
  v_checks := v_checks || jsonb_build_object('key', 'ledger_sums_to_zero', 'ok', v_value = 0, 'value', v_value);

  select jsonb_build_object(
    'members_net_cents', coalesce(sum(amount_cents) filter (where account = 'member'), 0),
    'cash_box_cents', coalesce(sum(amount_cents) filter (where account = 'cash_box'), 0),
    'consumption_cents', -coalesce(sum(amount_cents) filter (where account = 'consumption'), 0),
    'supplies_cents', coalesce(sum(amount_cents) filter (where account = 'supplies'), 0),
    'adjustments_cents', coalesce(sum(amount_cents) filter (where account = 'adjustments'), 0))
  into v_figures
  from public.ledger_entries where group_id = p_group_id;

  select bool_and((c ->> 'ok')::boolean) into v_ok from jsonb_array_elements(v_checks) c;
  return jsonb_build_object('ok', v_ok, 'checked_at', now(), 'checks', v_checks, 'figures', v_figures);
end;
$$;

create function public.list_timezones() returns setof text
language sql
stable
set search_path = ''
as $$
  select name from pg_catalog.pg_timezone_names
  where name ~ '^(Africa|America|Antarctica|Asia|Atlantic|Australia|Europe|Indian|Pacific)/' or name = 'UTC'
  order by name
$$;
