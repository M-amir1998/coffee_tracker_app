-- Test helpers shared by all database tests.
-- This file runs first (alphabetical order) and deliberately commits, so the
-- helpers exist for the other files, which each run inside a rolled-back
-- transaction. Only for local and CI test databases.

create extension if not exists pgtap with schema extensions;

create schema if not exists tests;
grant usage on schema tests to authenticated, anon;

-- Creates a confirmed auth user "<name>@test.local"; the profile is created by
-- the on_auth_user_created trigger.
create or replace function tests.create_user(p_name text) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
    lower(p_name) || '@test.local', '', now(), '{"provider": "email", "providers": ["email"]}',
    jsonb_build_object('display_name', p_name), now(), now());
  return v_id;
end;
$$;

create or replace function tests.uid(p_name text) returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select id from auth.users where email = lower(p_name) || '@test.local'
$$;

create or replace function tests.gid(p_name text) returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select id from public.groups where name = p_name order by created_at desc limit 1
$$;

-- Acts as the given user for the rest of the transaction (like PostgREST does).
create or replace function tests.login(p_name text) returns void
language plpgsql
set search_path = ''
as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', tests.uid(p_name), 'role', 'authenticated')::text, true);
end;
$$;

create or replace function tests.logout() returns void
language plpgsql
set search_path = ''
as $$
begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'postgres', true);
end;
$$;

-- Ledger figures read with full privileges, for assertions.
create or replace function tests.balance(p_group text, p_user text) returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(amount_cents), 0)::bigint from public.ledger_entries
  where group_id = tests.gid(p_group) and account = 'member' and member_id = tests.uid(p_user)
$$;

create or replace function tests.cash(p_group text) returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(amount_cents), 0)::bigint from public.ledger_entries
  where group_id = tests.gid(p_group) and account = 'cash_box'
$$;

create or replace function tests.ledger_total(p_group text) returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(amount_cents), 0)::bigint from public.ledger_entries where group_id = tests.gid(p_group)
$$;

create or replace function tests.last_txn(p_group text) returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select id from public.transactions where group_id = tests.gid(p_group) order by created_at desc, id desc limit 1
$$;

-- Notifications and invitations are private to their recipient / admins, so
-- assertions about them read with full privileges.
create or replace function tests.notification_count(p_user text, p_kind text) returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer from public.notifications where user_id = tests.uid(p_user) and kind = p_kind
$$;

create or replace function tests.notification_payload(p_user text, p_kind text) returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select payload from public.notifications where user_id = tests.uid(p_user) and kind = p_kind
  order by created_at desc limit 1
$$;

create or replace function tests.invitation_uses(p_code text) returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select use_count from public.invitations where code = p_code
$$;

-- Books a coffee in the past through the ledger engine (the public API only
-- accepts coffees from the last seven days).
create or replace function tests.past_coffee(p_group text, p_user text, p_quantity integer, p_at timestamptz)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  t public.transactions;
begin
  t := private.insert_transaction(tests.gid(p_group), 'coffee', 'posted', (p_quantity * 20)::bigint,
    tests.uid(p_user), null, tests.uid(p_user), gen_random_uuid(),
    p_occurred_at => p_at, p_quantity => p_quantity, p_unit_price => 20, p_at => p_at);
  return t.id;
end;
$$;

-- Builds a group: the first name becomes the administrator, the others join
-- through an invitation. Roles can be adjusted by the test afterwards.
create or replace function tests.make_group(p_group text, p_members text[], p_price integer default 20)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_group uuid;
  v_code text;
  v_name text;
begin
  foreach v_name in array p_members loop
    if tests.uid(v_name) is null then
      perform tests.create_user(v_name);
    end if;
  end loop;

  perform tests.login(p_members[1]);
  v_group := public.create_group(p_group, 'Cycle 1', p_price, 'Europe/Madrid');
  v_code := public.create_invitation(v_group) ->> 'code';
  foreach v_name in array p_members[2:] loop
    perform tests.login(v_name);
    perform public.join_group(v_code);
  end loop;
  perform tests.logout();
  return v_group;
end;
$$;

grant execute on all functions in schema tests to authenticated, anon;

begin;
select plan(1);
select ok(to_regprocedure('tests.make_group(text, text[], integer)') is not null, 'test helpers installed');
select * from finish();
rollback;
