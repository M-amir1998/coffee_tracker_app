import 'package:coffee_tracker/core/errors/app_failure.dart';
import 'package:coffee_tracker/features/accounting/domain/balance_models.dart';
import 'package:coffee_tracker/features/auth/data/auth_repository.dart';
import 'package:coffee_tracker/features/dashboard/domain/dashboard.dart';
import 'package:coffee_tracker/features/groups/domain/group_models.dart';

Dashboard sampleDashboard({int netCents = 420, MemberRole role = MemberRole.member, int todayCoffees = 2}) =>
    Dashboard.fromJson({
      'group': {
        'id': 'g1',
        'name': 'Robotics Lab',
        'currency': 'EUR',
        'timezone': 'Europe/Madrid',
        'require_deposit_confirmation': true,
        'require_purchase_approval': false,
        'member_undo_window_minutes': 15,
      },
      'me': {'user_id': 'alice', 'display_name': 'Alice', 'role': role.name, 'joined_at': '2026-09-01T08:00:00Z'},
      'cycle': {
        'id': 'c2',
        'sequence_no': 2,
        'name': 'October 2026',
        'status': 'open',
        'opened_at': '2026-10-01T06:00:00Z',
      },
      'price_cents': 20,
      'next_price': null,
      // 21 coffees (4.20) minus deposits gives the requested net balance.
      'balance': {
        'opening_cents': 0,
        'coffees': 21,
        'consumption_cents': 420,
        'deposits_cents': 420 - netCents,
        'net_cents': netCents,
      },
      'today_coffees': todayCoffees,
      'all_time': {'coffees': 80, 'net_cents': netCents},
      'pending': {'to_review': 0, 'my_submissions': 0},
      'unread_notifications': 0,
      'recent': <Object>[],
    });

List<MemberBalance> sampleBalances() => [
  _balance('alice', 'Alice', coffees: 45, consumption: 900, deposits: 500, net: 400, me: true),
  _balance('bob', 'Bob', coffees: 60, consumption: 1200, deposits: 2000, net: -800),
  _balance('charlie', 'Charlie', coffees: 30, consumption: 600, deposits: 600, net: 0),
];

MemberBalance _balance(
  String id,
  String name, {
  required int coffees,
  required int consumption,
  required int deposits,
  required int net,
  bool me = false,
}) => MemberBalance(
  userId: id,
  displayName: name,
  role: MemberRole.member,
  membershipStatus: MembershipStatus.active,
  isMe: me,
  breakdown: BalanceBreakdown(coffees: coffees, consumptionCents: consumption, depositsCents: deposits, netCents: net),
);

List<Member> sampleMembers() => [
  for (final (id, name) in [('alice', 'Alice'), ('bob', 'Bob'), ('charlie', 'Charlie')])
    Member(
      userId: id,
      displayName: name,
      role: id == 'alice' ? MemberRole.admin : MemberRole.member,
      status: MembershipStatus.active,
      joinedAt: DateTime.utc(2026, 9),
      isMe: id == 'alice',
    ),
];

class FakeAuthRepository implements AuthRepository {
  final signIns = <(String, String)>[];
  AppFailure? failWith;
  SignUpOutcome signUpOutcome = SignUpOutcome.confirmationRequired;

  @override
  Future<void> signIn({required String email, required String password}) async {
    signIns.add((email.trim(), password));
    if (failWith case final failure?) throw failure;
  }

  @override
  Future<SignUpOutcome> signUp({required String email, required String password, required String displayName}) async {
    if (failWith case final failure?) throw failure;
    return signUpOutcome;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
