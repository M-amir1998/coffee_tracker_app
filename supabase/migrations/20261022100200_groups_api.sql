-- =============================================================================
-- Coffee Tracker — groups, memberships, invitations, prices, profiles
-- =============================================================================

create function private.require_timezone(p_timezone text) returns text
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_timezone is null or not exists (select 1 from pg_catalog.pg_timezone_names where name = p_timezone) then
    perform private.fail('invalid_timezone', 'Choose a valid IANA time zone such as Europe/Madrid.');
  end if;
  return p_timezone;
end;
$$;

-- Ensures the caller has a profile (accounts created before this schema existed).
create function private.ensure_profile(p_user uuid) returns void
language plpgsql
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  select u.id, left(coalesce(nullif(btrim(u.raw_user_meta_data ->> 'display_name'), ''),
                             nullif(split_part(coalesce(u.email, ''), '@', 1), ''), 'Coffee lover'), 40)
  from auth.users u where u.id = p_user
  on conflict (id) do nothing;
  insert into public.user_preferences (user_id)
  select id from public.profiles where id = p_user
  on conflict (user_id) do nothing;
end;
$$;

create function private.generate_invitation_code() returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_bytes bytea := uuid_send(gen_random_uuid());
  v_code text := '';
  v_index integer;
begin
  -- Skip byte 6 (UUID version bits); the low five bits of every other byte are random.
  foreach v_index in array array[0, 1, 2, 3, 4, 5, 7, 9] loop
    v_code := v_code || substr(v_alphabet, (get_byte(v_bytes, v_index) % 32) + 1, 1);
  end loop;
  return v_code;
end;
$$;

-- -----------------------------------------------------------------------------
-- Groups
-- -----------------------------------------------------------------------------

create function public.create_group(
  p_name text,
  p_first_cycle_name text,
  p_coffee_price_cents integer default 20,
  p_timezone text default 'Europe/Madrid',
  p_currency text default 'EUR'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_name text := private.require_text(p_name, 'invalid_name', 1, 60, 'The group name');
  v_cycle_name text := private.require_text(p_first_cycle_name, 'invalid_name', 1, 60, 'The cycle name');
  v_group uuid;
begin
  if p_coffee_price_cents is null or p_coffee_price_cents not between 1 and 10000 then
    perform private.fail('invalid_price', 'The coffee price must be between 0.01 and 100.00.');
  end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    perform private.fail('invalid_currency', 'Use a three-letter ISO currency code such as EUR.');
  end if;
  perform private.require_timezone(p_timezone);
  perform private.ensure_profile(v_actor);

  insert into public.groups (name, currency, timezone, created_by)
  values (v_name, p_currency, p_timezone, v_actor)
  returning id into v_group;

  insert into public.group_members (group_id, user_id, role) values (v_group, v_actor, 'admin');
  insert into public.coffee_prices (group_id, price_cents, effective_from, created_by)
  values (v_group, p_coffee_price_cents, clock_timestamp(), v_actor);
  insert into public.accounting_cycles (group_id, sequence_no, name, opened_at, opened_by)
  values (v_group, 1, v_cycle_name, clock_timestamp(), v_actor);

  perform private.audit(v_group, v_actor, 'group_created', 'group', v_group::text,
    jsonb_build_object('name', v_name, 'price_cents', p_coffee_price_cents, 'timezone', p_timezone));
  return v_group;
end;
$$;

create function public.update_group_settings(
  p_group_id uuid,
  p_name text default null,
  p_timezone text default null,
  p_require_deposit_confirmation boolean default null,
  p_require_purchase_approval boolean default null,
  p_member_undo_window_minutes integer default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_old public.groups;
  v_new public.groups;
begin
  perform private.require_role(p_group_id, array['admin']::public.member_role[]);
  if p_timezone is not null then
    perform private.require_timezone(p_timezone);
  end if;
  if p_member_undo_window_minutes is not null and p_member_undo_window_minutes not between 0 and 1440 then
    perform private.fail('invalid_request', 'The undo window must be between 0 and 1440 minutes.');
  end if;

  select * into v_old from public.groups where id = p_group_id for update;
  update public.groups set
    name = case when p_name is null then name
                else private.require_text(p_name, 'invalid_name', 1, 60, 'The group name') end,
    timezone = coalesce(p_timezone, timezone),
    require_deposit_confirmation = coalesce(p_require_deposit_confirmation, require_deposit_confirmation),
    require_purchase_approval = coalesce(p_require_purchase_approval, require_purchase_approval),
    member_undo_window_minutes = coalesce(p_member_undo_window_minutes, member_undo_window_minutes)
  where id = p_group_id
  returning * into v_new;

  perform private.audit(p_group_id, v_actor, 'group_settings_updated', 'group', p_group_id::text,
    jsonb_build_object(
      'before', jsonb_build_object('name', v_old.name, 'timezone', v_old.timezone,
        'require_deposit_confirmation', v_old.require_deposit_confirmation,
        'require_purchase_approval', v_old.require_purchase_approval,
        'member_undo_window_minutes', v_old.member_undo_window_minutes),
      'after', jsonb_build_object('name', v_new.name, 'timezone', v_new.timezone,
        'require_deposit_confirmation', v_new.require_deposit_confirmation,
        'require_purchase_approval', v_new.require_purchase_approval,
        'member_undo_window_minutes', v_new.member_undo_window_minutes)));
end;
$$;

-- -----------------------------------------------------------------------------
-- Invitations and membership
-- -----------------------------------------------------------------------------

create function public.create_invitation(
  p_group_id uuid,
  p_role public.member_role default 'member',
  p_max_uses integer default null,
  p_expires_in_days integer default 14
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_invitation public.invitations;
begin
  perform private.require_role(p_group_id, array['admin']::public.member_role[]);
  if p_role not in ('member', 'treasurer') then
    perform private.fail('invalid_request', 'Invitations can grant the member or treasurer role.');
  end if;
  if p_max_uses is not null and p_max_uses not between 1 and 1000 then
    perform private.fail('invalid_request', 'The maximum number of uses must be between 1 and 1000.');
  end if;
  if p_expires_in_days is not null and p_expires_in_days not between 1 and 365 then
    perform private.fail('invalid_request', 'Invitations can be valid for 1 to 365 days.');
  end if;

  loop
    begin
      insert into public.invitations (group_id, code, role, max_uses, expires_at, created_by)
      values (p_group_id, private.generate_invitation_code(), p_role, p_max_uses,
        case when p_expires_in_days is null then null else now() + make_interval(days => p_expires_in_days) end,
        v_actor)
      returning * into v_invitation;
      exit;
    exception when unique_violation then
      -- extremely unlikely code collision: try another code
    end;
  end loop;

  perform private.audit(p_group_id, v_actor, 'invitation_created', 'invitation', v_invitation.id::text,
    jsonb_build_object('role', p_role, 'max_uses', p_max_uses, 'expires_at', v_invitation.expires_at));
  return jsonb_build_object('id', v_invitation.id, 'code', v_invitation.code, 'role', v_invitation.role,
    'max_uses', v_invitation.max_uses, 'expires_at', v_invitation.expires_at);
end;
$$;

create function public.revoke_invitation(p_invitation_id uuid) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_invitation public.invitations;
begin
  select * into v_invitation from public.invitations where id = p_invitation_id;
  if v_invitation.id is null then
    perform private.fail('not_found', 'Invitation not found.');
  end if;
  perform private.require_role(v_invitation.group_id, array['admin']::public.member_role[]);
  update public.invitations set revoked_at = coalesce(revoked_at, now()) where id = p_invitation_id;
  perform private.audit(v_invitation.group_id, v_actor, 'invitation_revoked', 'invitation', p_invitation_id::text);
end;
$$;

create function private.normalize_code(p_code text) returns text
language sql
immutable
set search_path = ''
as $$
  select upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'))
$$;

create function private.invitation_problem(v public.invitations) returns text
language sql
stable
set search_path = ''
as $$
  select case
    when v.id is null then 'invalid_invitation'
    when v.revoked_at is not null then 'invitation_revoked'
    when v.expires_at is not null and v.expires_at <= now() then 'invitation_expired'
    when v.max_uses is not null and v.use_count >= v.max_uses then 'invitation_used_up'
  end
$$;

create function public.preview_invitation(p_code text) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_invitation public.invitations;
  v_problem text;
begin
  select * into v_invitation from public.invitations where code = private.normalize_code(p_code);
  v_problem := private.invitation_problem(v_invitation);
  if v_problem is not null then
    return jsonb_build_object('valid', false, 'reason', v_problem);
  end if;
  return jsonb_build_object(
    'valid', true,
    'group_id', v_invitation.group_id,
    'group_name', (select name from public.groups where id = v_invitation.group_id),
    'member_count', (select count(*) from public.group_members
                     where group_id = v_invitation.group_id and status = 'active'),
    'role', v_invitation.role,
    'already_member', private.membership_role(v_invitation.group_id, v_actor) is not null
  );
end;
$$;

create function public.join_group(p_code text) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_invitation public.invitations;
  v_problem text;
  v_existing public.group_members;
begin
  perform private.ensure_profile(v_actor);
  select * into v_invitation from public.invitations
  where code = private.normalize_code(p_code) for update;
  v_problem := private.invitation_problem(v_invitation);
  if v_problem is not null then
    perform private.fail(v_problem, 'This invitation code is not valid.');
  end if;

  select * into v_existing from public.group_members
  where group_id = v_invitation.group_id and user_id = v_actor for update;
  if v_existing.status = 'active' then
    return v_invitation.group_id;
  end if;

  if v_existing.user_id is null then
    insert into public.group_members (group_id, user_id, role)
    values (v_invitation.group_id, v_actor, v_invitation.role);
  else
    update public.group_members
    set status = 'active', left_at = null, role = v_invitation.role
    where group_id = v_invitation.group_id and user_id = v_actor;
  end if;

  update public.invitations set use_count = use_count + 1 where id = v_invitation.id;

  perform private.notify_roles(v_invitation.group_id, array['admin']::public.member_role[], 'member_joined', null,
    jsonb_build_object('member_id', v_actor, 'member_name', private.display_name(v_actor)), v_actor);
  perform private.audit(v_invitation.group_id, v_actor, 'member_joined', 'group_member', v_actor::text,
    jsonb_build_object('invitation_id', v_invitation.id, 'role', v_invitation.role,
      'rejoined', v_existing.user_id is not null));
  return v_invitation.group_id;
end;
$$;

create function private.has_open_items(p_group uuid, p_user uuid) returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1 from public.transactions
    where group_id = p_group and status in ('pending', 'disputed')
      and (member_id = p_user or counterparty_id = p_user or initiated_by = p_user)
  )
$$;

create function private.other_active_admins(p_group uuid, p_user uuid) returns integer
language sql
stable
set search_path = ''
as $$
  select count(*)::integer from public.group_members
  where group_id = p_group and status = 'active' and role = 'admin' and user_id <> p_user
$$;

create function public.leave_group(p_group_id uuid) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_role public.member_role := private.require_member(p_group_id);
  v_balance bigint;
begin
  perform private.lock_group(p_group_id);
  v_balance := private.member_balance(p_group_id, v_actor);
  if v_balance <> 0 then
    perform private.fail('outstanding_balance',
      'Settle your balance before leaving the group.');
  end if;
  if private.has_open_items(p_group_id, v_actor) then
    perform private.fail('open_items', 'Resolve your pending transactions before leaving the group.');
  end if;
  if v_role = 'admin' and private.other_active_admins(p_group_id, v_actor) = 0
     and exists (select 1 from public.group_members
                 where group_id = p_group_id and status = 'active' and user_id <> v_actor) then
    perform private.fail('last_admin', 'Appoint another administrator before leaving the group.');
  end if;

  update public.group_members set status = 'left', left_at = now()
  where group_id = p_group_id and user_id = v_actor;
  perform private.audit(p_group_id, v_actor, 'member_left', 'group_member', v_actor::text);
end;
$$;

create function public.set_member_role(p_group_id uuid, p_user_id uuid, p_role public.member_role) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_current public.member_role;
begin
  perform private.require_role(p_group_id, array['admin']::public.member_role[]);
  v_current := private.membership_role(p_group_id, p_user_id);
  if v_current is null then
    perform private.fail('not_member', 'That person is not an active member of this group.');
  end if;
  if v_current = p_role then
    return;
  end if;
  if v_current = 'admin' and private.other_active_admins(p_group_id, p_user_id) = 0 then
    perform private.fail('last_admin', 'A group needs at least one administrator.');
  end if;

  update public.group_members set role = p_role where group_id = p_group_id and user_id = p_user_id;
  perform private.notify(p_user_id, p_group_id, 'role_changed', null,
    jsonb_build_object('role', p_role, 'previous_role', v_current), v_actor);
  perform private.audit(p_group_id, v_actor, 'role_changed', 'group_member', p_user_id::text,
    jsonb_build_object('from', v_current, 'to', p_role));
end;
$$;

create function public.remove_member(p_group_id uuid, p_user_id uuid, p_note text default null) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_role public.member_role;
begin
  perform private.require_role(p_group_id, array['admin']::public.member_role[]);
  if p_user_id = v_actor then
    perform private.fail('invalid_request', 'Use "leave group" to remove yourself.');
  end if;
  v_role := private.membership_role(p_group_id, p_user_id);
  if v_role is null then
    perform private.fail('not_member', 'That person is not an active member of this group.');
  end if;

  -- The member's balance stays in the ledger; an administrator can settle or
  -- write it off later with an audited balance adjustment.
  update public.group_members set status = 'removed', left_at = now()
  where group_id = p_group_id and user_id = p_user_id;
  perform private.audit(p_group_id, v_actor, 'member_removed', 'group_member', p_user_id::text,
    jsonb_build_object('role', v_role, 'note', nullif(btrim(p_note), ''),
      'balance_cents', private.member_balance(p_group_id, p_user_id)));
end;
$$;

-- -----------------------------------------------------------------------------
-- Coffee price
-- -----------------------------------------------------------------------------

create function public.set_coffee_price(
  p_group_id uuid,
  p_price_cents integer,
  p_effective_from timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_from timestamptz := coalesce(p_effective_from, clock_timestamp());
  v_previous integer;
  v_id uuid;
  v_user uuid;
begin
  perform private.require_role(p_group_id, array['admin']::public.member_role[]);
  if p_price_cents is null or p_price_cents not between 1 and 10000 then
    perform private.fail('invalid_price', 'The coffee price must be between 0.01 and 100.00.');
  end if;
  if v_from < clock_timestamp() - interval '1 minute' then
    perform private.fail('price_backdated', 'Price changes only apply from now on; history never changes.');
  end if;
  v_from := greatest(v_from, clock_timestamp());
  v_previous := private.price_at(p_group_id, v_from);

  insert into public.coffee_prices (group_id, price_cents, effective_from, created_by)
  values (p_group_id, p_price_cents, v_from, v_actor)
  returning id into v_id;

  for v_user in
    select user_id from public.group_members where group_id = p_group_id and status = 'active'
  loop
    perform private.notify(v_user, p_group_id, 'price_changed', null,
      jsonb_build_object('price_cents', p_price_cents, 'previous_price_cents', v_previous, 'effective_from', v_from),
      v_actor);
  end loop;
  perform private.audit(p_group_id, v_actor, 'price_changed', 'coffee_price', v_id::text,
    jsonb_build_object('price_cents', p_price_cents, 'previous_price_cents', v_previous, 'effective_from', v_from));
  return v_id;
end;
$$;

create function public.cancel_scheduled_price(p_price_id uuid) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_price public.coffee_prices;
begin
  select * into v_price from public.coffee_prices where id = p_price_id;
  if v_price.id is null then
    perform private.fail('not_found', 'Price not found.');
  end if;
  perform private.require_role(v_price.group_id, array['admin']::public.member_role[]);
  if v_price.effective_from <= now() then
    perform private.fail('append_only', 'This price already applies and is part of the history.');
  end if;
  delete from public.coffee_prices where id = p_price_id;
  perform private.audit(v_price.group_id, v_actor, 'price_cancelled', 'coffee_price', p_price_id::text,
    jsonb_build_object('price_cents', v_price.price_cents, 'effective_from', v_price.effective_from));
end;
$$;

-- -----------------------------------------------------------------------------
-- Profile, preferences, notifications, account deletion
-- -----------------------------------------------------------------------------

create function public.update_profile(p_display_name text default null, p_avatar_path text default null,
  p_clear_avatar boolean default false)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
begin
  perform private.ensure_profile(v_actor);
  if p_avatar_path is not null and p_avatar_path not like v_actor::text || '/%' then
    perform private.fail('invalid_request', 'Avatars must be stored in your own folder.');
  end if;
  update public.profiles set
    display_name = case when p_display_name is null then display_name
                        else private.require_text(p_display_name, 'invalid_name', 1, 40, 'The display name') end,
    avatar_path = case when p_clear_avatar then null else coalesce(p_avatar_path, avatar_path) end
  where id = v_actor and deleted_at is null;
end;
$$;

create function public.update_preferences(
  p_theme text default null,
  p_locale text default null,
  p_show_on_leaderboard boolean default null,
  p_gamification_enabled boolean default null,
  p_notify_settlements boolean default null,
  p_notify_approvals boolean default null,
  p_notify_balance boolean default null,
  p_notify_cycles boolean default null,
  p_notify_awards boolean default null
)
returns public.user_preferences
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_prefs public.user_preferences;
begin
  perform private.ensure_profile(v_actor);
  update public.user_preferences set
    theme = coalesce(p_theme, theme),
    locale = coalesce(p_locale, locale),
    show_on_leaderboard = coalesce(p_show_on_leaderboard, show_on_leaderboard),
    gamification_enabled = coalesce(p_gamification_enabled, gamification_enabled),
    notify_settlements = coalesce(p_notify_settlements, notify_settlements),
    notify_approvals = coalesce(p_notify_approvals, notify_approvals),
    notify_balance = coalesce(p_notify_balance, notify_balance),
    notify_cycles = coalesce(p_notify_cycles, notify_cycles),
    notify_awards = coalesce(p_notify_awards, notify_awards)
  where user_id = v_actor
  returning * into v_prefs;
  return v_prefs;
end;
$$;

create function public.mark_notifications_read(p_ids uuid[] default null) returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_count integer;
begin
  update public.notifications set read_at = now()
  where user_id = v_actor and read_at is null and (p_ids is null or id = any (p_ids));
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Deletes the caller's login. The anonymised profile and the ledger history
-- stay, so group balances remain correct for everybody else.
create function public.delete_my_account() returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.current_user_id();
  v_group record;
begin
  for v_group in
    select group_id from public.group_members where user_id = v_actor and status = 'active'
  loop
    perform private.lock_group(v_group.group_id);
    if private.member_balance(v_group.group_id, v_actor) <> 0 then
      perform private.fail('outstanding_balance', 'Settle your balance in every group before deleting your account.');
    end if;
    if private.has_open_items(v_group.group_id, v_actor) then
      perform private.fail('open_items', 'Resolve your pending transactions before deleting your account.');
    end if;
    if private.membership_role(v_group.group_id, v_actor) = 'admin'
       and private.other_active_admins(v_group.group_id, v_actor) = 0
       and exists (select 1 from public.group_members
                   where group_id = v_group.group_id and status = 'active' and user_id <> v_actor) then
      perform private.fail('last_admin', 'Appoint another administrator before deleting your account.');
    end if;
    perform private.audit(v_group.group_id, v_actor, 'account_deleted', 'profile', v_actor::text);
  end loop;

  update public.notifications set read_at = coalesce(read_at, now()) where user_id = v_actor;
  -- Fires private.handle_deleted_user(), which anonymises the profile and ends memberships.
  delete from auth.users where id = v_actor;
end;
$$;
