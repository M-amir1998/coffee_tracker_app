-- =============================================================================
-- Coffee Tracker — security: RLS policies, privileges, realtime, storage
--
-- Principles (see docs/security/SECURITY.md):
--   * anon can do nothing.
--   * authenticated can SELECT rows of groups they actively belong to (RLS).
--   * No API role can INSERT/UPDATE/DELETE application tables directly. All
--     writes go through SECURITY DEFINER functions that validate everything.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Row level security
-- -----------------------------------------------------------------------------

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'profiles', 'user_preferences', 'groups', 'group_members', 'invitations', 'accounting_cycles',
    'coffee_prices', 'transactions', 'ledger_entries', 'transaction_events', 'cycle_member_balances',
    'cycle_cash_snapshots', 'cash_reconciliations', 'notifications', 'audit_log', 'monthly_awards',
    'monthly_award_runs'
  ] loop
    execute format('alter table public.%I enable row level security', v_table);
  end loop;

  -- Group-scoped tables readable by active members of that group.
  foreach v_table in array array[
    'accounting_cycles', 'coffee_prices', 'transactions', 'ledger_entries', 'transaction_events',
    'cycle_member_balances', 'cycle_cash_snapshots', 'cash_reconciliations', 'monthly_awards',
    'monthly_award_runs'
  ] loop
    execute format(
      'create policy %I on public.%I for select to authenticated using (group_id in (select private.my_group_ids()))',
      v_table || '_select_members', v_table);
  end loop;
end;
$$;

create policy profiles_select_self_and_co_members on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or id in (select private.my_co_member_ids()));

create policy user_preferences_select_own on public.user_preferences
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy groups_select_members on public.groups
  for select to authenticated
  using (id in (select private.my_group_ids()));

create policy group_members_select_members on public.group_members
  for select to authenticated
  using (group_id in (select private.my_group_ids()));

create policy invitations_select_admins on public.invitations
  for select to authenticated
  using (group_id in (select private.my_admin_group_ids()));

create policy notifications_select_own on public.notifications
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy audit_log_select_admins on public.audit_log
  for select to authenticated
  using (group_id in (select private.my_admin_group_ids()));

-- -----------------------------------------------------------------------------
-- Privileges
-- -----------------------------------------------------------------------------

revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;
revoke all on all functions in schema private from public, anon, authenticated;

grant select on
  public.profiles, public.user_preferences, public.groups, public.group_members, public.invitations,
  public.accounting_cycles, public.coffee_prices, public.transactions, public.ledger_entries,
  public.transaction_events, public.cycle_member_balances, public.cycle_cash_snapshots,
  public.cash_reconciliations, public.notifications, public.audit_log, public.monthly_awards,
  public.monthly_award_runs
to authenticated;

-- Every function in the public schema is an RPC meant for signed-in users;
-- each one authenticates and authorizes the caller itself.
grant execute on all functions in schema public to authenticated;

-- RLS policies call these helpers with the privileges of the caller.
grant usage on schema private to authenticated;
grant execute on function private.my_group_ids(), private.my_admin_group_ids(), private.my_co_member_ids()
  to authenticated;

-- Future tables and sequences are private until a migration grants access explicitly.
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;

-- -----------------------------------------------------------------------------
-- Realtime: clients subscribe to changes and refetch aggregates.
-- -----------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table
      public.transactions, public.notifications, public.accounting_cycles, public.group_members,
      public.coffee_prices;
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- Storage: private receipts per group, public avatars per user
-- -----------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('receipts', 'receipts', false, 5242880,
   array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'application/pdf']),
  ('avatars', 'avatars', true, 1048576, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

-- Receipts live under "<group_id>/<file>"; members of that group can read and add them.
-- They are never updated or deleted so that evidence stays with the transaction.
create policy receipts_select_members on storage.objects
  for select to authenticated
  using (bucket_id = 'receipts'
         and (storage.foldername(name))[1] in (select g::text from private.my_group_ids() as g));

create policy receipts_insert_members on storage.objects
  for insert to authenticated
  with check (bucket_id = 'receipts'
              and (storage.foldername(name))[1] in (select g::text from private.my_group_ids() as g));

-- Avatars live under "<user_id>/<file>" and are managed by their owner.
create policy avatars_select_authenticated on storage.objects
  for select to authenticated
  using (bucket_id = 'avatars');

create policy avatars_insert_owner on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy avatars_update_owner on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy avatars_delete_owner on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
