import 'package:coffee_tracker/app/routes.dart';
import 'package:coffee_tracker/features/admin/presentation/admin_page.dart';
import 'package:coffee_tracker/features/admin/presentation/audit_log_page.dart';
import 'package:coffee_tracker/features/admin/presentation/cash_box_page.dart';
import 'package:coffee_tracker/features/admin/presentation/exports_page.dart';
import 'package:coffee_tracker/features/admin/presentation/group_settings_page.dart';
import 'package:coffee_tracker/features/admin/presentation/invitations_page.dart';
import 'package:coffee_tracker/features/admin/presentation/members_admin_page.dart';
import 'package:coffee_tracker/features/admin/presentation/price_page.dart';
import 'package:coffee_tracker/features/analytics/presentation/analytics_page.dart';
import 'package:coffee_tracker/features/auth/application/auth_providers.dart';
import 'package:coffee_tracker/features/auth/presentation/forgot_password_page.dart';
import 'package:coffee_tracker/features/auth/presentation/reset_password_page.dart';
import 'package:coffee_tracker/features/auth/presentation/sign_in_page.dart';
import 'package:coffee_tracker/features/auth/presentation/sign_up_page.dart';
import 'package:coffee_tracker/features/auth/presentation/verify_email_page.dart';
import 'package:coffee_tracker/features/cycles/presentation/cycle_report_page.dart';
import 'package:coffee_tracker/features/cycles/presentation/cycles_page.dart';
import 'package:coffee_tracker/features/dashboard/presentation/home_page.dart';
import 'package:coffee_tracker/features/group_overview/presentation/group_page.dart';
import 'package:coffee_tracker/features/group_overview/presentation/member_detail_page.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/groups/presentation/create_group_page.dart';
import 'package:coffee_tracker/features/groups/presentation/join_group_page.dart';
import 'package:coffee_tracker/features/groups/presentation/welcome_page.dart';
import 'package:coffee_tracker/features/leaderboard/presentation/heroes_page.dart';
import 'package:coffee_tracker/features/notifications/presentation/notifications_page.dart';
import 'package:coffee_tracker/features/settings/presentation/settings_page.dart';
import 'package:coffee_tracker/features/settlements/presentation/settle_up_page.dart';
import 'package:coffee_tracker/features/shell/presentation/app_shell.dart';
import 'package:coffee_tracker/features/shell/presentation/more_page.dart';
import 'package:coffee_tracker/features/shell/presentation/splash_page.dart';
import 'package:coffee_tracker/features/transactions/presentation/activity_page.dart';
import 'package:coffee_tracker/features/transactions/presentation/transaction_detail_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Re-runs the router's redirect when auth or group membership changes.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref
      ..listen(authSessionProvider, (_, _) => notifyListeners())
      ..listen(myGroupsProvider, (_, _) => notifyListeners())
      ..listen(passwordRecoveryProvider, (_, _) => notifyListeners());
  }
}

String? _redirect(Ref ref, GoRouterState state) {
  final location = state.matchedLocation;
  final session = ref.read(authSessionProvider);
  if (!session.hasValue && !session.hasError) return location == Routes.splash ? null : Routes.splash;

  if (ref.read(passwordRecoveryProvider)) {
    return location == Routes.resetPassword ? null : Routes.resetPassword;
  }

  final signedIn = ref.read(currentUserIdProvider) != null;
  if (!signedIn) {
    if (Routes.authRoutes.contains(location) || location == Routes.resetPassword) return null;
    // Remember invitation links so the user lands on them after signing in.
    final next = location.startsWith(Routes.join) ? state.uri.toString() : null;
    return Uri(path: Routes.signIn, queryParameters: next == null ? null : {'next': next}).toString();
  }

  final groups = ref.read(myGroupsProvider);
  if (!groups.hasValue) return location == Routes.splash ? null : Routes.splash;
  final hasGroup = groups.requireValue.isNotEmpty;

  if (Routes.authRoutes.contains(location) || location == Routes.splash) {
    final next = state.uri.queryParameters['next'];
    if (next != null && next.startsWith('/')) return next;
    return hasGroup ? Routes.home : Routes.welcome;
  }
  if (!hasGroup && !Routes.allowedWithoutGroup(location)) return Routes.welcome;
  if (hasGroup && location == Routes.welcome) return Routes.home;
  return null;
}

/// Shell branches, in navigation order.
enum ShellBranch { home, group, activity, heroes, analytics, settle, cycles, admin, settings, notifications, more }

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.home,
    refreshListenable: refresh,
    redirect: (context, state) => _redirect(ref, state),
    routes: [
      GoRoute(path: Routes.splash, builder: (context, state) => const SplashPage()),
      GoRoute(
        path: Routes.signIn,
        builder: (context, state) => SignInPage(next: state.uri.queryParameters['next']),
      ),
      GoRoute(
        path: Routes.signUp,
        builder: (context, state) => SignUpPage(next: state.uri.queryParameters['next']),
      ),
      GoRoute(
        path: Routes.verifyEmail,
        builder: (context, state) => VerifyEmailPage(email: state.uri.queryParameters['email'] ?? ''),
      ),
      GoRoute(path: Routes.forgotPassword, builder: (context, state) => const ForgotPasswordPage()),
      GoRoute(
        path: Routes.resetPassword,
        builder: (context, state) => ResetPasswordPage(email: state.uri.queryParameters['email']),
      ),
      GoRoute(path: Routes.welcome, builder: (context, state) => const WelcomePage()),
      GoRoute(path: Routes.createGroup, builder: (context, state) => const CreateGroupPage()),
      GoRoute(
        path: Routes.join,
        builder: (context, state) => const JoinGroupPage(),
        routes: [
          GoRoute(
            path: ':code',
            builder: (context, state) => JoinGroupPage(code: state.pathParameters['code']),
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
        branches: [
          _branch(Routes.home, const HomePage()),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.group,
                builder: (context, state) => const GroupPage(),
                routes: [
                  GoRoute(
                    path: 'member/:userId',
                    builder: (context, state) => MemberDetailPage(userId: state.pathParameters['userId']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.activity,
                builder: (context, state) => const ActivityPage(),
                routes: [
                  GoRoute(
                    path: ':transactionId',
                    builder: (context, state) =>
                        TransactionDetailPage(transactionId: state.pathParameters['transactionId']!),
                  ),
                ],
              ),
            ],
          ),
          _branch(Routes.heroes, const HeroesPage()),
          _branch(Routes.analytics, const AnalyticsPage()),
          _branch(Routes.settle, const SettleUpPage()),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.cycles,
                builder: (context, state) => const CyclesPage(),
                routes: [
                  GoRoute(
                    path: ':cycleId',
                    builder: (context, state) => CycleReportPage(cycleId: state.pathParameters['cycleId']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.admin,
                builder: (context, state) => const AdminPage(),
                routes: [
                  GoRoute(path: 'members', builder: (context, state) => const MembersAdminPage()),
                  GoRoute(path: 'invitations', builder: (context, state) => const InvitationsPage()),
                  GoRoute(path: 'price', builder: (context, state) => const PricePage()),
                  GoRoute(path: 'cash-box', builder: (context, state) => const CashBoxPage()),
                  GoRoute(path: 'audit', builder: (context, state) => const AuditLogPage()),
                  GoRoute(path: 'exports', builder: (context, state) => const ExportsPage()),
                  GoRoute(path: 'settings', builder: (context, state) => const GroupSettingsPage()),
                ],
              ),
            ],
          ),
          _branch(Routes.settings, const SettingsPage()),
          _branch(Routes.notifications, const NotificationsPage()),
          _branch(Routes.more, const MorePage()),
        ],
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

StatefulShellBranch _branch(String path, Widget page) => StatefulShellBranch(
  routes: [GoRoute(path: path, builder: (context, state) => page)],
);
