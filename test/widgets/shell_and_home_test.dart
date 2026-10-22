import 'dart:async';

import 'package:coffee_tracker/app/router.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/app_theme.dart';
import 'package:coffee_tracker/features/accounting/application/report_providers.dart';
import 'package:coffee_tracker/features/accounting/domain/ledger_models.dart';
import 'package:coffee_tracker/features/auth/application/auth_providers.dart';
import 'package:coffee_tracker/features/dashboard/presentation/home_page.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/groups/domain/group_models.dart';
import 'package:coffee_tracker/features/notifications/application/notification_providers.dart';
import 'package:coffee_tracker/features/profile/application/profile_providers.dart';
import 'package:coffee_tracker/features/profile/domain/profile_models.dart';
import 'package:coffee_tracker/features/realtime/realtime_sync.dart';
import 'package:coffee_tracker/features/shell/presentation/app_shell.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/fakes.dart';
import '../helpers/samples.dart';
import '../helpers/test_app.dart';

void main() {
  late StreamController<bool> network;

  setUp(() => network = StreamController<bool>.broadcast());
  tearDown(() => network.close());

  Future<List<Override>> overrides({MemberRole role = MemberRole.member, int netCents = 420}) async => [
    ...queueOverrides(
      preferences: await inMemoryPreferences(),
      ledger: FakeLedgerRepository(),
      clock: TestClock(DateTime.utc(2026, 10, 22, 9)),
      network: network,
    ),
    currentUserIdProvider.overrideWithValue('alice'),
    myGroupsProvider.overrideWith(
      (ref) async => [
        GroupSummary(
          id: 'g1',
          name: 'Robotics Lab',
          role: role,
          memberCount: 12,
          cycleName: 'October 2026',
          currency: 'EUR',
        ),
      ],
    ),
    myProfileProvider.overrideWith((ref) async => const Profile(id: 'alice', displayName: 'Alice')),
    unreadNotificationsProvider.overrideWithValue(2),
    realtimeSyncProvider.overrideWith((ref, groupId) {}),
    dashboardProvider.overrideWith((ref, groupId) async => sampleDashboard(netCents: netCents, role: role)),
    pendingActionsProvider.overrideWith((ref, groupId) async => PendingActions.empty),
  ];

  Widget shellApp(List<Override> overrides) {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => AppShell(navigationShell: shell),
          branches: [
            for (final branch in ShellBranch.values)
              StatefulShellBranch(
                routes: [GoRoute(path: '/${branch.name}', builder: (context, state) => Text('page ${branch.name}'))],
              ),
          ],
        ),
      ],
    );
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
  }

  group('navigation adapts to the screen', () {
    testWidgets('phones use a bottom bar with four destinations and More', (tester) async {
      setScreenSize(tester, phone);
      await tester.pumpWidget(shellApp(await overrides()));
      await tester.pumpAndSettle();
      final bar = find.byType(NavigationBar);
      expect(bar, findsOneWidget);
      for (final label in ['Home', 'Group', 'Activity', 'Coffee Heroes', 'More']) {
        expect(find.descendant(of: bar, matching: find.text(label)), findsOneWidget);
      }
      await tester.tap(find.descendant(of: bar, matching: find.text('Group')));
      await tester.pumpAndSettle();
      expect(find.text('page group'), findsOneWidget);
    });

    testWidgets('tablets use a navigation rail', (tester) async {
      setScreenSize(tester, tablet);
      await tester.pumpWidget(shellApp(await overrides()));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('desktop uses a sidebar with administration for treasurers', (tester) async {
      setScreenSize(tester, desktop);
      await tester.pumpWidget(shellApp(await overrides(role: MemberRole.treasurer)));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('Robotics Lab'), findsOneWidget);
      expect(find.text('Administration'), findsWidgets);
      await tester.tap(find.text('Analytics'));
      await tester.pumpAndSettle();
      expect(find.text('page analytics'), findsOneWidget);
    });

    testWidgets('members do not see administration', (tester) async {
      setScreenSize(tester, desktop);
      await tester.pumpWidget(shellApp(await overrides()));
      await tester.pumpAndSettle();
      expect(find.text('Administration'), findsNothing);
    });
  });

  group('home', () {
    testWidgets('states the balance in plain words and shows the coffee button first on phones', (tester) async {
      setScreenSize(tester, phone);
      await tester.pumpWidget(testApp(const HomePage(), overrides: await overrides()));
      await tester.pumpAndSettle();
      expect(find.text('You owe'), findsOneWidget);
      expect(find.text('€4.20'), findsWidgets);
      expect(find.text('+1 Coffee'), findsOneWidget);
      final button = tester.getTopLeft(find.text('+1 Coffee'));
      final balance = tester.getTopLeft(find.text('You owe'));
      expect(button.dy, lessThan(balance.dy), reason: 'one tap from opening the app');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a member who is owed money sees that clearly', (tester) async {
      setScreenSize(tester, phone);
      await tester.pumpWidget(testApp(const HomePage(), overrides: await overrides(netCents: -800)));
      await tester.pumpAndSettle();
      expect(find.text('The group owes you'), findsOneWidget);
      expect(find.text('Request reimbursement'), findsOneWidget);
    });

    testWidgets('wide screens use two columns', (tester) async {
      setScreenSize(tester, desktop);
      await tester.pumpWidget(testApp(const HomePage(), overrides: await overrides()));
      await tester.pumpAndSettle();
      final balance = tester.getTopLeft(find.text('You owe'));
      final recent = tester.getTopLeft(find.text('Your recent activity'));
      expect(recent.dx, greaterThan(balance.dx + 300), reason: 'activity sits beside the balance');
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in Spanish and in dark mode', (tester) async {
      setScreenSize(tester, phone);
      await tester.pumpWidget(
        testApp(const HomePage(), overrides: await overrides(), locale: const Locale('es'), dark: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('Debes'), findsOneWidget);
      expect(find.text('+1 Café'), findsOneWidget);
    });
  });
}
