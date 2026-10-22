-- Scenario 14: a new user joins without affecting historical balances.
-- Also invitations, roles, leaving and rejoining.
begin;
select plan(26);

select tests.make_group('Lab', array['Alice', 'Bob', 'Charlie']);
select tests.create_user('Dana');
select tests.create_user('Eve');

select tests.login('Bob');
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 7);
select tests.login('Charlie');
select public.submit_purchase(tests.gid('Lab'), 'personal', 900, 'Beans', gen_random_uuid());
select tests.login('Alice');
select public.close_cycle(tests.gid('Lab'),
  (select id from public.accounting_cycles where group_id = tests.gid('Lab') and status = 'open'),
  'Cycle 1', 'Cycle 2');

-- ---------------------------------------------------------------------------
-- Scenario 14
-- ---------------------------------------------------------------------------
create temporary table inv as select public.create_invitation(tests.gid('Lab'), 'member', 2, 7) ->> 'code' as code;
grant select on inv to authenticated;

select tests.login('Dana');
select is((public.preview_invitation((select code from inv)) ->> 'group_name'), 'Lab',
  'S14: the invitation shows which group it is for');
select is(public.join_group(lower((select code from inv))), tests.gid('Lab'),
  'S14: Dana joins with the code (case-insensitive)');
select is(tests.balance('Lab', 'Dana'), 0::bigint, 'S14: the newcomer starts at zero');
select is(tests.balance('Lab', 'Bob'), 140::bigint, 'S14: Bob''s balance is unchanged');
select is(tests.balance('Lab', 'Charlie'), -900::bigint, 'S14: Charlie''s balance is unchanged');
select is((select count(*)::integer from public.cycle_member_balances b
           join public.accounting_cycles c on c.id = b.cycle_id
           where c.group_id = tests.gid('Lab') and b.user_id = tests.uid('Dana')), 0,
  'S14: the closed cycle report does not gain a row for the newcomer');
select is((select opening_cents from public.get_member_balances(tests.gid('Lab')) where user_id = tests.uid('Dana')),
  0::bigint, 'S14: no opening balance is invented for the newcomer');
select is(public.join_group((select code from inv)), tests.gid('Lab'), 'joining twice is harmless');
select is(tests.invitation_uses((select code from inv)), 1,
  'a repeated join does not consume another use');

-- Invitation limits
select tests.login('Eve');
select public.join_group((select code from inv));
select tests.login('Alice');
select tests.create_user('Frank');
select tests.login('Frank');
select throws_ok($$ select public.join_group((select code from inv)) $$, 'P0001', 'invitation_used_up',
  'an invitation cannot be used more often than allowed');
select is(public.preview_invitation('NOPE2345') ->> 'reason', 'invalid_invitation', 'unknown codes are reported');
select tests.login('Alice');
select public.revoke_invitation((select id from public.invitations where code = (select code from inv)));
select is((select revoked_at is not null from public.invitations where code = (select code from inv)), true,
  'administrators can revoke invitations');
select tests.login('Bob');
select throws_ok($$ select public.create_invitation(tests.gid('Lab')) $$, 'P0001', 'forbidden',
  'members cannot create invitations');

-- Roles
select tests.login('Alice');
select throws_ok($$ select public.set_member_role(tests.gid('Lab'), tests.uid('Alice'), 'member') $$,
  'P0001', 'last_admin', 'the last administrator cannot be demoted');
select lives_ok($$ select public.set_member_role(tests.gid('Lab'), tests.uid('Bob'), 'treasurer') $$,
  'administrators assign roles');
select is(tests.notification_count('Bob', 'role_changed'), 1, 'the member is told about the new role');
select throws_ok($$ select public.leave_group(tests.gid('Lab')) $$, 'P0001', 'last_admin',
  'the last administrator cannot leave while others remain');

-- Leaving requires a settled balance.
select tests.login('Bob');
select throws_ok($$ select public.leave_group(tests.gid('Lab')) $$, 'P0001', 'outstanding_balance',
  'members with a debt cannot leave');
select public.submit_deposit(tests.gid('Lab'), 140, gen_random_uuid());
select is(tests.balance('Lab', 'Bob'), 0::bigint, 'Bob (treasurer) settles');
select lives_ok($$ select public.leave_group(tests.gid('Lab')) $$, 'a settled member can leave');
select throws_ok($$ select public.record_coffee(tests.gid('Lab'), gen_random_uuid()) $$, 'P0001', 'not_member',
  'former members can no longer record coffees');
select is((select count(*)::integer from public.transactions where group_id = tests.gid('Lab')), 0,
  'former members lose access to the group history');

-- Rejoining continues the same membership and history.
select tests.login('Alice');
create temporary table inv2 as select public.create_invitation(tests.gid('Lab')) ->> 'code' as code;
grant select on inv2 to authenticated;
select tests.login('Bob');
select public.join_group((select code from inv2));
select is((select role::text from public.group_members where group_id = tests.gid('Lab') and user_id = tests.uid('Bob')),
  'member', 'a returning member gets the role of the new invitation');
select is((select count(*)::integer from public.transactions
           where group_id = tests.gid('Lab') and member_id = tests.uid('Bob')), 2,
  'a returning member sees their history again');

-- Removal by an administrator keeps the balance in the ledger.
select tests.login('Charlie');
select public.record_coffee(tests.gid('Lab'), gen_random_uuid(), 1);
select tests.login('Alice');
select public.remove_member(tests.gid('Lab'), tests.uid('Charlie'), 'Left the lab');
select is(tests.balance('Lab', 'Charlie'), -880::bigint, 'removing a member does not erase their balance');

select tests.logout();
select is(tests.ledger_total('Lab'), 0::bigint, 'the ledger sums to zero');

select * from finish();
rollback;
