-- =============================================================================
-- Coffee Tracker — balance-changing operations
--
-- Every function: authenticates, authorizes, validates, takes the group lock,
-- checks the idempotency key, and only then writes. Writes go through the
-- ledger engine so posting rules and post-conditions are applied uniformly.
-- =============================================================================

create function private.require_active_member(p_group uuid, p_user uuid) returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if private.membership_role(p_group, p_user) is null then
    perform private.fail('not_member', 'That person is not an active member of this group.');
  end if;
end;
$$;

create function private.require_occurred_at(p_at timestamptz, p_max_age interval) returns timestamptz
language plpgsql
stable
set search_path = ''
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_at timestamptz := coalesce(p_at, v_now);
begin
  if v_at < v_now - p_max_age or v_at > v_now + interval '5 minutes' then
    perform private.fail('occurred_at_out_of_range', 'The date of this operation is outside the allowed range.');
  end if;
  return least(v_at, v_now);
end;
$$;

-- -----------------------------------------------------------------------------
-- Coffee consumption
-- -----------------------------------------------------------------------------

create function public.record_coffee(
  p_group_id uuid,
  p_idempotency_key uuid,
  p_quantity integer default 1,
  p_occurred_at timestamptz default null,
  p_member_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_role public.member_role := private.require_member(p_group_id);
  v_member uuid := coalesce(p_member_id, v_actor);
  v_at timestamptz;
  v_price integer;
  v_replayed boolean := false;
  t public.transactions;
begin
  if p_quantity is null or p_quantity not between 1 and 20 then
    perform private.fail('invalid_quantity', 'You can record between 1 and 20 coffees at once.');
  end if;
  if v_member <> v_actor then
    if v_role not in ('treasurer', 'admin') then
      perform private.fail('forbidden', 'Only treasurers and administrators can record coffees for other members.');
    end if;
    perform private.require_active_member(p_group_id, v_member);
  end if;
  -- Offline-queued coffees may arrive late; they keep the price of the moment they were drunk.
  v_at := private.require_occurred_at(p_occurred_at, interval '7 days');

  perform private.lock_group(p_group_id);
  t := private.idempotent_replay(v_actor, p_idempotency_key, p_group_id, 'coffee');
  if t.id is not null then
    if t.quantity <> p_quantity or t.member_id <> v_member then
      perform private.fail('idempotency_conflict', 'This request key was already used for a different operation.');
    end if;
    v_replayed := true;
  else
    v_price := private.price_at(p_group_id, v_at);
    t := private.insert_transaction(
      p_group_id, 'coffee', 'posted', (p_quantity * v_price)::bigint, v_member, null, v_actor, p_idempotency_key,
      p_occurred_at => v_at, p_quantity => p_quantity, p_unit_price => v_price);
    if v_member <> v_actor then
      perform private.notify(v_member, p_group_id, 'coffee_recorded_for_you', t.id, private.txn_payload(t), v_actor);
    end if;
  end if;

  return private.txn_result(t, v_replayed) || jsonb_build_object(
    'quantity', t.quantity,
    'unit_price_cents', t.unit_price_cents,
    'occurred_at', t.occurred_at,
    'balance_cents', private.member_balance(p_group_id, v_member)
  );
end;
$$;

-- Members can undo their own coffees for a short time. The original entry is
-- kept and cancelled by a reversal, never deleted.
create function public.undo_coffee(p_transaction_id uuid, p_idempotency_key uuid default null) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_window integer;
  t public.transactions;
  r public.transactions;
begin
  select * into t from public.transactions where id = p_transaction_id;
  if t.id is null then
    perform private.fail('not_found', 'Transaction not found.');
  end if;
  perform private.require_member(t.group_id);
  if t.kind <> 'coffee' or t.member_id <> v_actor or t.initiated_by <> v_actor then
    perform private.fail('forbidden', 'You can only undo coffees you recorded yourself.');
  end if;

  perform private.lock_group(t.group_id);
  select * into t from public.transactions where id = p_transaction_id for update;
  if t.status = 'reversed' then
    select * into r from public.transactions where reverses_id = t.id;
    return private.txn_result(r, true)
      || jsonb_build_object('balance_cents', private.member_balance(t.group_id, v_actor));
  end if;
  if t.status <> 'posted' then
    perform private.fail('invalid_state', 'This coffee can no longer be undone.');
  end if;

  select member_undo_window_minutes into v_window from public.groups where id = t.group_id;
  if t.created_at < now() - make_interval(mins => v_window) then
    perform private.fail('undo_window_expired',
      format('Coffees can be undone within %s minutes. Ask an administrator to correct older entries.', v_window));
  end if;
  if t.cycle_id <> private.open_cycle_id(t.group_id) then
    perform private.fail('cycle_closed', 'This coffee belongs to a closed accounting cycle.');
  end if;

  r := private.reverse_internal(t.id, v_actor, 'Undone by the member', coalesce(p_idempotency_key, gen_random_uuid()));
  return private.txn_result(r, false)
    || jsonb_build_object('balance_cents', private.member_balance(t.group_id, v_actor));
end;
$$;

-- -----------------------------------------------------------------------------
-- Cash-box deposits
-- -----------------------------------------------------------------------------

create function public.submit_deposit(
  p_group_id uuid,
  p_amount_cents bigint,
  p_idempotency_key uuid,
  p_description text default null,
  p_member_id uuid default null,
  p_occurred_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_role public.member_role := private.require_member(p_group_id);
  v_member uuid := coalesce(p_member_id, v_actor);
  v_amount bigint := private.require_amount(p_amount_cents);
  v_at timestamptz := private.require_occurred_at(p_occurred_at, interval '31 days');
  v_status public.txn_status;
  t public.transactions;
begin
  if v_member <> v_actor then
    if v_role not in ('treasurer', 'admin') then
      perform private.fail('forbidden', 'Only treasurers and administrators can record deposits for other members.');
    end if;
    perform private.require_active_member(p_group_id, v_member);
  end if;

  perform private.lock_group(p_group_id);
  t := private.idempotent_replay(v_actor, p_idempotency_key, p_group_id, 'deposit', v_amount);
  if t.id is not null then
    return private.txn_result(t, true);
  end if;

  -- Treasurers hold the box, so their records are final. Other members'
  -- deposits wait for verification when the group requires it.
  select case when v_role in ('treasurer', 'admin') or not g.require_deposit_confirmation
              then 'posted'::public.txn_status else 'pending'::public.txn_status end
  into v_status
  from public.groups g where g.id = p_group_id;

  t := private.insert_transaction(p_group_id, 'deposit', v_status, v_amount, v_member, null, v_actor,
    p_idempotency_key, p_occurred_at => v_at, p_description => p_description);

  if v_status = 'pending' then
    perform private.notify_roles(p_group_id, array['treasurer', 'admin']::public.member_role[],
      'deposit_pending', t.id, private.txn_payload(t), v_actor);
  elsif v_member <> v_actor then
    perform private.notify(v_member, p_group_id, 'deposit_recorded', t.id, private.txn_payload(t), v_actor);
  end if;
  return private.txn_result(t, false);
end;
$$;

-- -----------------------------------------------------------------------------
-- Bean purchases
-- -----------------------------------------------------------------------------

create function public.submit_purchase(
  p_group_id uuid,
  p_funding text,
  p_amount_cents bigint,
  p_description text,
  p_idempotency_key uuid,
  p_purchased_at timestamptz default null,
  p_evidence_path text default null,
  p_member_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_role public.member_role := private.require_member(p_group_id);
  v_member uuid := coalesce(p_member_id, v_actor);
  v_amount bigint := private.require_amount(p_amount_cents);
  v_description text := private.require_text(p_description, 'description_required', 1, 500, 'The description');
  v_at timestamptz := private.require_occurred_at(p_purchased_at, interval '365 days');
  v_kind public.txn_kind;
  v_status public.txn_status;
  t public.transactions;
begin
  v_kind := case p_funding
    when 'personal' then 'purchase_personal'::public.txn_kind
    when 'cash_box' then 'purchase_box'::public.txn_kind
  end;
  if v_kind is null then
    perform private.fail('invalid_request', 'A purchase is funded either personally or from the cash box.');
  end if;
  if v_member <> v_actor then
    if v_role not in ('treasurer', 'admin') then
      perform private.fail('forbidden', 'Only treasurers and administrators can record purchases for other members.');
    end if;
    perform private.require_active_member(p_group_id, v_member);
  end if;
  if p_evidence_path is not null and p_evidence_path not like p_group_id::text || '/%' then
    perform private.fail('invalid_request', 'Receipts must be uploaded to the group folder.');
  end if;

  perform private.lock_group(p_group_id);
  t := private.idempotent_replay(v_actor, p_idempotency_key, p_group_id, v_kind, v_amount);
  if t.id is not null then
    return private.txn_result(t, true);
  end if;

  select case when v_role in ('treasurer', 'admin') or not g.require_purchase_approval
              then 'posted'::public.txn_status else 'pending'::public.txn_status end
  into v_status
  from public.groups g where g.id = p_group_id;

  t := private.insert_transaction(p_group_id, v_kind, v_status, v_amount, v_member, null, v_actor,
    p_idempotency_key, p_occurred_at => v_at, p_description => v_description, p_evidence_path => p_evidence_path);

  if v_status = 'pending' then
    perform private.notify_roles(p_group_id, array['treasurer', 'admin']::public.member_role[],
      'purchase_pending', t.id, private.txn_payload(t), v_actor);
  end if;
  return private.txn_result(t, false);
end;
$$;

-- -----------------------------------------------------------------------------
-- Direct settlements between members
-- -----------------------------------------------------------------------------

create function public.record_transfer(
  p_group_id uuid,
  p_from_member_id uuid,
  p_to_member_id uuid,
  p_amount_cents bigint,
  p_idempotency_key uuid,
  p_description text default null,
  p_admin_override boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_role public.member_role := private.require_member(p_group_id);
  v_amount bigint := private.require_amount(p_amount_cents);
  v_status public.txn_status;
  t public.transactions;
begin
  if p_from_member_id is null or p_to_member_id is null then
    perform private.fail('invalid_request', 'Choose who paid and who received the money.');
  end if;
  if p_from_member_id = p_to_member_id then
    perform private.fail('self_transfer', 'A member cannot pay themselves.');
  end if;
  perform private.require_active_member(p_group_id, p_from_member_id);
  perform private.require_active_member(p_group_id, p_to_member_id);
  if p_admin_override and v_role <> 'admin' then
    perform private.fail('forbidden', 'Only administrators can confirm a payment on behalf of the recipient.');
  end if;
  if p_admin_override and char_length(btrim(coalesce(p_description, ''))) < 3 then
    perform private.fail('note_required', 'Explain why the payment is confirmed without the recipient.');
  end if;
  if v_actor not in (p_from_member_id, p_to_member_id) and v_role <> 'admin' then
    perform private.fail('forbidden', 'You can only record payments you made or received.');
  end if;

  perform private.lock_group(p_group_id);
  t := private.idempotent_replay(v_actor, p_idempotency_key, p_group_id, 'transfer', v_amount);
  if t.id is not null then
    return private.txn_result(t, true);
  end if;

  -- A recipient acknowledging receipt only lowers their own claim, so it is
  -- final. Any other record waits for the recipient (or an administrator).
  v_status := case when v_actor = p_to_member_id or p_admin_override
                   then 'posted'::public.txn_status else 'pending'::public.txn_status end;

  t := private.insert_transaction(p_group_id, 'transfer', v_status, v_amount, p_from_member_id, p_to_member_id,
    v_actor, p_idempotency_key, p_description => p_description,
    p_note => case when p_admin_override then 'Confirmed by an administrator on behalf of the recipient' end,
    p_metadata => case when p_admin_override then jsonb_build_object('admin_override', true) else '{}'::jsonb end);

  if v_status = 'pending' then
    perform private.notify(p_to_member_id, p_group_id, 'transfer_requested', t.id, private.txn_payload(t), v_actor);
  else
    perform private.notify(p_from_member_id, p_group_id, 'transfer_confirmed', t.id, private.txn_payload(t), v_actor);
    if p_admin_override then
      perform private.notify(p_to_member_id, p_group_id, 'transfer_confirmed', t.id, private.txn_payload(t), v_actor);
      perform private.audit(p_group_id, v_actor, 'transfer_admin_override', 'transaction', t.id::text,
        jsonb_build_object('amount_cents', v_amount, 'note', p_description));
    end if;
  end if;
  return private.txn_result(t, false);
end;
$$;

-- -----------------------------------------------------------------------------
-- Reimbursements from the cash box
-- -----------------------------------------------------------------------------

create function public.record_reimbursement(
  p_group_id uuid,
  p_member_id uuid,
  p_amount_cents bigint,
  p_idempotency_key uuid,
  p_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_role public.member_role := private.require_member(p_group_id);
  v_member uuid := coalesce(p_member_id, v_actor);
  v_amount bigint := private.require_amount(p_amount_cents);
  v_status public.txn_status;
  v_credit bigint;
  v_requested bigint;
  t public.transactions;
begin
  perform private.require_active_member(p_group_id, v_member);
  if v_role not in ('treasurer', 'admin') and v_member <> v_actor then
    perform private.fail('forbidden', 'Members can only request reimbursements for themselves.');
  end if;

  perform private.lock_group(p_group_id);
  t := private.idempotent_replay(v_actor, p_idempotency_key, p_group_id, 'reimbursement', v_amount);
  if t.id is not null then
    return private.txn_result(t, true);
  end if;

  -- Treasurers hand out the cash themselves, so their record is final.
  -- Members request a reimbursement that a treasurer pays out later.
  v_status := case when v_role in ('treasurer', 'admin') then 'posted'::public.txn_status
                   else 'pending'::public.txn_status end;

  if v_status = 'pending' then
    v_credit := -private.member_balance(p_group_id, v_member);
    select coalesce(sum(amount_cents), 0) into v_requested
    from public.transactions
    where group_id = p_group_id and kind = 'reimbursement' and status in ('pending', 'disputed')
      and member_id = v_member;
    if v_amount > v_credit - v_requested then
      perform private.fail('reimbursement_exceeds_credit',
        'A reimbursement cannot exceed the amount the group owes you, including requests already waiting.');
    end if;
  end if;

  t := private.insert_transaction(p_group_id, 'reimbursement', v_status, v_amount, v_member, null, v_actor,
    p_idempotency_key, p_description => p_description);

  if v_status = 'pending' then
    perform private.notify_roles(p_group_id, array['treasurer', 'admin']::public.member_role[],
      'reimbursement_requested', t.id, private.txn_payload(t), v_actor);
  else
    perform private.notify(v_member, p_group_id, 'reimbursement_paid', t.id, private.txn_payload(t), v_actor);
  end if;
  return private.txn_result(t, false);
end;
$$;

-- -----------------------------------------------------------------------------
-- Decisions: confirm / reject / cancel / dispute
-- -----------------------------------------------------------------------------

create function private.decision_kind(p_kind public.txn_kind, p_approved boolean) returns text
language sql
immutable
set search_path = ''
as $$
  select case p_kind
    when 'transfer' then case when p_approved then 'transfer_confirmed' else 'transfer_rejected' end
    when 'deposit' then case when p_approved then 'deposit_confirmed' else 'deposit_rejected' end
    when 'purchase_personal' then case when p_approved then 'purchase_approved' else 'purchase_rejected' end
    when 'purchase_box' then case when p_approved then 'purchase_approved' else 'purchase_rejected' end
    when 'reimbursement' then case when p_approved then 'reimbursement_paid' else 'reimbursement_rejected' end
  end
$$;

-- Who may decide on a pending transaction. Nobody approves their own submission.
create function private.can_decide(t public.transactions, p_actor uuid, p_role public.member_role) returns boolean
language sql
stable
set search_path = ''
as $$
  select case
    when t.status <> 'pending' or p_role is null then false
    when t.kind = 'transfer' then p_actor = t.counterparty_id or (p_role = 'admin' and p_actor <> t.member_id)
    when t.kind in ('deposit', 'purchase_personal', 'purchase_box', 'reimbursement') then
      p_role in ('treasurer', 'admin') and p_actor <> t.initiated_by and p_actor <> t.member_id
    else false
  end
$$;

create function public.respond_to_transaction(p_transaction_id uuid, p_approve boolean, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_role public.member_role;
  v_kind text;
  t public.transactions;
begin
  select * into t from public.transactions where id = p_transaction_id;
  if t.id is null then
    perform private.fail('not_found', 'Transaction not found.');
  end if;
  v_role := private.require_member(t.group_id);

  perform private.lock_group(t.group_id);
  select * into t from public.transactions where id = p_transaction_id for update;
  if t.status <> 'pending' then
    perform private.fail('invalid_state', 'This transaction is no longer awaiting a decision.');
  end if;
  if not private.can_decide(t, v_actor, v_role) then
    perform private.fail('forbidden', 'You cannot decide on this transaction.');
  end if;
  if (not p_approve or (t.kind = 'transfer' and v_actor <> t.counterparty_id))
     and char_length(btrim(coalesce(p_note, ''))) < 3 then
    perform private.fail('note_required', 'Please add a short explanation.');
  end if;

  if p_approve then
    t := private.post_existing(t.id, v_actor, p_note);
  else
    t := private.change_status(t.id, 'rejected', v_actor, p_note);
  end if;

  v_kind := private.decision_kind(t.kind, p_approve);
  perform private.notify(t.initiated_by, t.group_id, v_kind, t.id,
    private.txn_payload(t) || jsonb_build_object('note', nullif(btrim(p_note), '')), v_actor);
  if t.member_id <> t.initiated_by then
    perform private.notify(t.member_id, t.group_id, v_kind, t.id,
      private.txn_payload(t) || jsonb_build_object('note', nullif(btrim(p_note), '')), v_actor);
  end if;
  if t.kind = 'transfer' and v_actor <> t.counterparty_id then
    perform private.notify(t.counterparty_id, t.group_id, v_kind, t.id,
      private.txn_payload(t) || jsonb_build_object('note', nullif(btrim(p_note), '')), v_actor);
    perform private.audit(t.group_id, v_actor, 'transfer_decided_by_admin', 'transaction', t.id::text,
      jsonb_build_object('approved', p_approve, 'note', p_note));
  end if;
  return private.txn_result(t, false);
end;
$$;

create function public.cancel_transaction(p_transaction_id uuid, p_note text default null) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  t public.transactions;
begin
  select * into t from public.transactions where id = p_transaction_id;
  if t.id is null then
    perform private.fail('not_found', 'Transaction not found.');
  end if;
  perform private.require_member(t.group_id);
  perform private.lock_group(t.group_id);
  select * into t from public.transactions where id = p_transaction_id for update;
  if t.initiated_by <> v_actor then
    perform private.fail('forbidden', 'Only the person who submitted this transaction can cancel it.');
  end if;
  if t.status <> 'pending' then
    perform private.fail('invalid_state', 'Only pending transactions can be cancelled.');
  end if;

  t := private.change_status(t.id, 'cancelled', v_actor, coalesce(p_note, 'Cancelled by the submitter'));
  if t.kind = 'transfer' then
    perform private.notify(t.counterparty_id, t.group_id, 'transaction_cancelled', t.id, private.txn_payload(t), v_actor);
  end if;
  return private.txn_result(t, false);
end;
$$;

create function public.dispute_transaction(p_transaction_id uuid, p_note text) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_note text;
  t public.transactions;
begin
  select * into t from public.transactions where id = p_transaction_id;
  if t.id is null then
    perform private.fail('not_found', 'Transaction not found.');
  end if;
  perform private.require_member(t.group_id);
  perform private.lock_group(t.group_id);
  select * into t from public.transactions where id = p_transaction_id for update;
  if t.initiated_by <> v_actor then
    perform private.fail('forbidden', 'Only the person who submitted this transaction can dispute its rejection.');
  end if;
  v_note := private.require_text(p_note, 'note_required', 3, 500, 'The explanation');
  if t.status <> 'rejected' then
    perform private.fail('invalid_state', 'Only rejected transactions can be disputed.');
  end if;
  if exists (select 1 from public.transaction_events where transaction_id = t.id and to_status = 'disputed') then
    perform private.fail('already_disputed', 'This transaction was already disputed and resolved.');
  end if;

  t := private.change_status(t.id, 'disputed', v_actor, v_note);
  perform private.notify_roles(t.group_id, array['admin']::public.member_role[], 'dispute_opened', t.id,
    private.txn_payload(t) || jsonb_build_object('note', v_note), v_actor);
  return private.txn_result(t, false);
end;
$$;

create function public.resolve_dispute(p_transaction_id uuid, p_approve boolean, p_note text) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_note text;
  t public.transactions;
begin
  select * into t from public.transactions where id = p_transaction_id;
  if t.id is null then
    perform private.fail('not_found', 'Transaction not found.');
  end if;
  perform private.require_role(t.group_id, array['admin']::public.member_role[]);
  v_note := private.require_text(p_note, 'note_required', 3, 500, 'The resolution note');
  perform private.lock_group(t.group_id);
  select * into t from public.transactions where id = p_transaction_id for update;
  if t.status <> 'disputed' then
    perform private.fail('invalid_state', 'This transaction is not disputed.');
  end if;
  -- Parties may not judge their own dispute unless nobody else can.
  if v_actor in (t.initiated_by, t.member_id, coalesce(t.counterparty_id, t.member_id))
     and exists (select 1 from public.group_members
                 where group_id = t.group_id and status = 'active' and role = 'admin'
                   and user_id not in (t.initiated_by, t.member_id, coalesce(t.counterparty_id, t.member_id))) then
    perform private.fail('forbidden', 'Another administrator who is not involved must resolve this dispute.');
  end if;

  if p_approve then
    t := private.post_existing(t.id, v_actor, v_note);
  else
    t := private.change_status(t.id, 'rejected', v_actor, v_note);
  end if;

  perform private.notify(t.initiated_by, t.group_id, 'dispute_resolved', t.id,
    private.txn_payload(t) || jsonb_build_object('approved', p_approve, 'note', v_note), v_actor);
  if t.counterparty_id is not null then
    perform private.notify(t.counterparty_id, t.group_id, 'dispute_resolved', t.id,
      private.txn_payload(t) || jsonb_build_object('approved', p_approve, 'note', v_note), v_actor);
  end if;
  perform private.audit(t.group_id, v_actor, 'dispute_resolved', 'transaction', t.id::text,
    jsonb_build_object('approved', p_approve, 'note', v_note));
  return private.txn_result(t, false);
end;
$$;

-- -----------------------------------------------------------------------------
-- Administrative corrections
-- -----------------------------------------------------------------------------

create function public.reverse_transaction(p_transaction_id uuid, p_note text, p_idempotency_key uuid) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_note text;
  t public.transactions;
  r public.transactions;
begin
  select * into t from public.transactions where id = p_transaction_id;
  if t.id is null then
    perform private.fail('not_found', 'Transaction not found.');
  end if;
  perform private.require_role(t.group_id, array['admin']::public.member_role[]);
  v_note := private.require_text(p_note, 'note_required', 3, 500, 'The reason');
  perform private.lock_group(t.group_id);

  r := private.idempotent_replay(v_actor, p_idempotency_key, t.group_id, 'reversal');
  if r.id is not null then
    if r.reverses_id <> t.id then
      perform private.fail('idempotency_conflict', 'This request key was already used for a different operation.');
    end if;
    return private.txn_result(r, true);
  end if;

  r := private.reverse_internal(t.id, v_actor, v_note, p_idempotency_key);

  perform private.notify(t.member_id, t.group_id, 'transaction_reversed', r.id,
    private.txn_payload(t) || jsonb_build_object('note', v_note), v_actor);
  perform private.notify(t.counterparty_id, t.group_id, 'transaction_reversed', r.id,
    private.txn_payload(t) || jsonb_build_object('note', v_note), v_actor);
  perform private.audit(t.group_id, v_actor, 'transaction_reversed', 'transaction', t.id::text,
    jsonb_build_object('reversal_id', r.id, 'kind', t.kind, 'amount_cents', t.amount_cents, 'note', v_note));
  return private.txn_result(r, false);
end;
$$;

-- p_direction = 1 increases what the member owes (a charge);
-- p_direction = -1 decreases it (a credit, e.g. a write-off).
create function public.record_balance_adjustment(
  p_group_id uuid,
  p_member_id uuid,
  p_direction smallint,
  p_amount_cents bigint,
  p_note text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_role public.member_role := private.require_role(p_group_id, array['admin']::public.member_role[]);
  v_amount bigint := private.require_amount(p_amount_cents);
  v_note text := private.require_text(p_note, 'note_required', 3, 500, 'The reason');
  t public.transactions;
begin
  if p_direction is null or p_direction not in (-1, 1) then
    perform private.fail('invalid_request', 'Choose whether the adjustment charges or credits the member.');
  end if;
  -- Former members can be adjusted too (for example to write off a small debt).
  if not exists (select 1 from public.group_members where group_id = p_group_id and user_id = p_member_id) then
    perform private.fail('not_member', 'That person never belonged to this group.');
  end if;

  perform private.lock_group(p_group_id);
  t := private.idempotent_replay(v_actor, p_idempotency_key, p_group_id, 'balance_adjustment', v_amount);
  if t.id is not null then
    return private.txn_result(t, true);
  end if;

  t := private.insert_transaction(p_group_id, 'balance_adjustment', 'posted', v_amount, p_member_id, null, v_actor,
    p_idempotency_key, p_description => v_note, p_direction => p_direction, p_note => v_note);
  perform private.notify(p_member_id, p_group_id, 'balance_adjusted', t.id,
    private.txn_payload(t) || jsonb_build_object('direction', p_direction, 'note', v_note), v_actor);
  perform private.audit(p_group_id, v_actor, 'balance_adjusted', 'transaction', t.id::text,
    jsonb_build_object('member_id', p_member_id, 'direction', p_direction, 'amount_cents', v_amount, 'note', v_note));
  return private.txn_result(t, false);
end;
$$;

create function public.reconcile_cash_box(
  p_group_id uuid,
  p_counted_cents bigint,
  p_idempotency_key uuid,
  p_note text default null,
  p_apply_adjustment boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_expected bigint;
  v_difference bigint;
  v_existing public.cash_reconciliations;
  v_reconciliation public.cash_reconciliations;
  t public.transactions;
begin
  perform private.require_role(p_group_id, array['treasurer', 'admin']::public.member_role[]);
  if p_counted_cents is null or p_counted_cents not between 0 and 100000000 then
    perform private.fail('invalid_amount', 'Enter the counted amount of cash.');
  end if;
  if p_idempotency_key is null then
    perform private.fail('invalid_request', 'Every operation needs an idempotency key.');
  end if;

  perform private.lock_group(p_group_id);
  select * into v_existing from public.cash_reconciliations
  where created_by = v_actor and idempotency_key = p_idempotency_key;
  if v_existing.id is not null then
    return jsonb_build_object('reconciliation_id', v_existing.id, 'expected_cents', v_existing.expected_cents,
      'counted_cents', v_existing.counted_cents, 'difference_cents', v_existing.counted_cents - v_existing.expected_cents,
      'adjustment_transaction_id', v_existing.adjustment_transaction_id, 'replayed', true);
  end if;

  v_expected := private.cash_balance(p_group_id);
  v_difference := p_counted_cents - v_expected;
  if v_difference <> 0 and char_length(btrim(coalesce(p_note, ''))) < 3 then
    perform private.fail('note_required', 'Explain the difference between the counted and the expected cash.');
  end if;

  if v_difference <> 0 and p_apply_adjustment then
    t := private.insert_transaction(p_group_id, 'cash_adjustment', 'posted', abs(v_difference), null, null, v_actor,
      p_idempotency_key, p_description => p_note, p_direction => sign(v_difference)::smallint, p_note => p_note);
  end if;

  insert into public.cash_reconciliations (group_id, cycle_id, expected_cents, counted_cents, note,
    adjustment_transaction_id, idempotency_key, created_by)
  values (p_group_id, private.open_cycle_id(p_group_id), v_expected, p_counted_cents, nullif(btrim(p_note), ''),
    t.id, p_idempotency_key, v_actor)
  returning * into v_reconciliation;

  perform private.audit(p_group_id, v_actor, 'cash_reconciled', 'cash_reconciliation', v_reconciliation.id::text,
    jsonb_build_object('expected_cents', v_expected, 'counted_cents', p_counted_cents,
      'difference_cents', v_difference, 'adjustment_transaction_id', t.id));
  return jsonb_build_object('reconciliation_id', v_reconciliation.id, 'expected_cents', v_expected,
    'counted_cents', p_counted_cents, 'difference_cents', v_difference,
    'adjustment_transaction_id', t.id, 'replayed', false);
end;
$$;

-- -----------------------------------------------------------------------------
-- Accounting cycles
-- -----------------------------------------------------------------------------

create function public.close_cycle(
  p_group_id uuid,
  p_cycle_id uuid,
  p_confirmation text,
  p_next_cycle_name text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_role public.member_role := private.require_role(p_group_id, array['admin']::public.member_role[]);
  v_next_name text := private.require_text(p_next_cycle_name, 'invalid_name', 1, 60, 'The name of the next cycle');
  v_cycle public.accounting_cycles;
  v_new uuid;
begin
  perform private.lock_group(p_group_id);

  select * into v_cycle from public.accounting_cycles where group_id = p_group_id and status = 'open';
  if v_cycle.id is null or v_cycle.id <> p_cycle_id then
    perform private.fail('stale_cycle', 'The open accounting cycle has changed. Refresh and try again.');
  end if;
  -- Typing the exact cycle name protects against closing a cycle by accident.
  if btrim(coalesce(p_confirmation, '')) <> v_cycle.name then
    perform private.fail('confirmation_mismatch', 'Type the exact name of the cycle to confirm.');
  end if;
  if v_next_name = v_cycle.name then
    perform private.fail('invalid_name', 'The next cycle needs a different name.');
  end if;

  v_new := private.close_cycle_internal(p_group_id, v_cycle.id, v_actor, v_next_name, p_note);
  return jsonb_build_object('closed_cycle_id', v_cycle.id, 'new_cycle_id', v_new);
end;
$$;
