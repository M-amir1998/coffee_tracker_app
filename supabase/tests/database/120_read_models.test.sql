-- Read models: Coffee Heroes, monthly awards, activity pagination, analytics,
-- personal statistics and the dashboard.
begin;
select plan(31);

select tests.make_group('Lab', array['Alice', 'Bob', 'Charlie', 'Dana']);
-- The group has existed for a while.
update public.groups set created_at = now() - interval '3 months' where id = tests.gid('Lab');

create function pg_temp.last_month_at(p_day integer, p_hour integer) returns timestamptz language sql as $$
  select (date_trunc('month', now() at time zone 'Europe/Madrid') - interval '1 month'
          + make_interval(days => p_day - 1, hours => p_hour)) at time zone 'Europe/Madrid'
$$;
grant execute on function pg_temp.last_month_at(integer, integer) to authenticated;

-- Last month: Bob 5, Charlie 3.  This week: Alice 2, Bob 1, Dana 4 (hidden).
select tests.past_coffee('Lab', 'Bob', 5, pg_temp.last_month_at(10, 10));
select tests.past_coffee('Lab', 'Charlie', 3, pg_temp.last_month_at(12, 15));
select tests.login('Alice');
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 2);
select tests.login('Bob');
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 1);
select tests.login('Dana');
select public.update_preferences(p_show_on_leaderboard => false);
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 4);

-- ---------------------------------------------------------------------------
-- Coffee Heroes
-- ---------------------------------------------------------------------------
select tests.login('Alice');
select is((public.get_leaderboard(tests.gid('Lab'), 'week') ->> 'total_coffees')::integer, 7,
  'week: the group total includes hidden members');
select is((select string_agg(r ->> 'display_name' || '=' || (r ->> 'coffees'), ',')
           from jsonb_array_elements(public.get_leaderboard(tests.gid('Lab'), 'week') -> 'rows') r), 'Alice=2,Bob=1',
  'week: ranking without the member who opted out');
select is((select string_agg(r ->> 'display_name' || '=' || (r ->> 'coffees'), ',')
           from jsonb_array_elements(public.get_leaderboard(tests.gid('Lab'), 'all_time') -> 'rows') r),
  'Bob=6,Charlie=3,Alice=2', 'all time: Bob leads with 6');
select is((public.get_leaderboard(tests.gid('Lab'), 'month') ->> 'total_coffees')::integer, 7,
  'month: only this month''s coffees');
select is((public.get_leaderboard(tests.gid('Lab'), 'cycle') ->> 'total_coffees')::integer, 15, 'cycle: all 15 coffees');
select throws_ok($$ select public.get_leaderboard(tests.gid('Lab'), 'decade') $$, 'P0001', 'invalid_request',
  'unknown periods are rejected');

select tests.login('Dana');
select is((select (r ->> 'is_hidden')::boolean from jsonb_array_elements(
             public.get_leaderboard(tests.gid('Lab'), 'week') -> 'rows') r where (r ->> 'is_me')::boolean), true,
  'a hidden member still sees their own row, flagged as hidden');

-- ---------------------------------------------------------------------------
-- Monthly Coffee Hero
-- ---------------------------------------------------------------------------
select tests.login('Charlie');
create temporary table awards as select public.get_monthly_awards(tests.gid('Lab')) as a;
grant select on awards to authenticated;
select is(jsonb_array_length((select a from awards)), 1, 'one completed month had coffees');
select is((select a -> 0 -> 'winners' -> 0 ->> 'display_name' from awards), 'Bob', 'Bob is last month''s Coffee Hero');
select is(((select a -> 0 -> 'winners' -> 0 ->> 'coffees' from awards))::integer, 5, 'with 5 coffees');
select is(tests.notification_count('Alice', 'coffee_hero'), 1, 'members are told about the award');
select public.get_monthly_awards(tests.gid('Lab'));
select is(tests.notification_count('Alice', 'coffee_hero'), 1, 'awards are computed and announced only once');
select is((select count(*)::integer from public.monthly_award_runs where group_id = tests.gid('Lab')), 3,
  'every completed month since the group was created was evaluated once');

-- ---------------------------------------------------------------------------
-- Activity feed with cursor pagination
-- ---------------------------------------------------------------------------
select tests.login('Alice');
create temporary table page1 as select * from public.get_activity(tests.gid('Lab'), 2);
grant select on page1 to authenticated;
create temporary table page2 as
  select * from public.get_activity(tests.gid('Lab'), 2,
    (select created_at from page1 order by created_at, id limit 1), (select id from page1 order by created_at, id limit 1));
grant select on page2 to authenticated;
create temporary table page3 as
  select * from public.get_activity(tests.gid('Lab'), 10,
    (select created_at from page2 order by created_at, id limit 1), (select id from page2 order by created_at, id limit 1));
grant select on page3 to authenticated;

select is((select count(*)::integer from page1), 2, 'the first page has two items');
select is((select count(*)::integer from (select id from page1 union select id from page2 union select id from page3) x), 6,
  'three pages cover five transactions and the cycle opening without duplicates');
select ok((select max(created_at) from page2) <= (select min(created_at) from page1), 'pages are ordered newest first');
select is((select count(*)::integer from (select item_type from page1 union all select item_type from page2
                                            union all select item_type from page3) x where item_type = 'cycle_opened'), 1,
  'cycle events appear in the feed');
select is((select count(*)::integer from public.get_activity(tests.gid('Lab'), 50, p_types => array['coffee'])), 5,
  'filter by type');
select is((select count(*)::integer from public.get_activity(tests.gid('Lab'), 50, p_member_id => tests.uid('Bob'))), 2,
  'filter by member');
select is((select member_name from public.get_activity(tests.gid('Lab'), 1)), 'Dana',
  'feed rows carry display names for readable sentences');

-- ---------------------------------------------------------------------------
-- Analytics
-- ---------------------------------------------------------------------------
create temporary table an as
  select public.get_analytics(tests.gid('Lab'), (pg_temp.last_month_at(1, 0) at time zone 'Europe/Madrid')::date,
    (now() at time zone 'Europe/Madrid')::date) as a;
grant select on an to authenticated;
select is(((select a from an) -> 'totals' ->> 'group_coffees')::integer, 15, 'analytics: group total');
select is(((select a from an) -> 'totals' ->> 'my_coffees')::integer, 2, 'analytics: personal total');
select is((select sum((h ->> 'group_coffees')::integer)::integer from an, jsonb_array_elements(a -> 'hourly') h), 15,
  'analytics: the hourly histogram adds up');
select is((select sum((d ->> 'group_coffees')::integer)::integer from an, jsonb_array_elements(a -> 'daily') d), 15,
  'analytics: the daily series adds up');
select is(((select a from an) -> 'participation' ->> 'consuming_members')::integer, 4, 'analytics: four people drank coffee');
select is((select count(*)::integer from an, jsonb_array_elements(a -> 'participation' -> 'members') m
           where m ->> 'display_name' is null), 1, 'analytics: the hidden member is anonymous');
select throws_ok($$ select public.get_analytics(tests.gid('Lab'), current_date, current_date - 1) $$, 'P0001',
  'invalid_request', 'analytics validates the date range');

-- ---------------------------------------------------------------------------
-- Personal statistics and dashboard
-- ---------------------------------------------------------------------------
select tests.logout();
select tests.past_coffee('Lab', 'Charlie', 1,
  (((now() at time zone 'Europe/Madrid')::date - 1) + time '06:30') at time zone 'Europe/Madrid');
select tests.past_coffee('Lab', 'Charlie', 1,
  (((now() at time zone 'Europe/Madrid')::date - 2) + time '21:15') at time zone 'Europe/Madrid');
select tests.login('Charlie');
create temporary table st as select public.get_my_stats(tests.gid('Lab')) as s;
grant select on st to authenticated;
select is(((select s from st) ->> 'early_bird_coffees')::integer, 1, 'stats: one coffee before 08:00');
select is(((select s from st) ->> 'night_owl_coffees')::integer, 1, 'stats: one coffee after 20:00');
select is(((select s from st) ->> 'total_coffees')::integer, 5, 'stats: all-time coffees');

select tests.login('Bob');
select is((public.get_dashboard(tests.gid('Lab')) -> 'balance' ->> 'net_cents')::bigint, 120::bigint,
  'dashboard: Bob owes 1.20 for six coffees');

select * from finish();
rollback;
