import 'dart:async';

import 'package:coffee_tracker/core/widgets/states.dart';
import 'package:coffee_tracker/features/accounting/application/report_providers.dart';
import 'package:coffee_tracker/features/accounting/domain/ledger_models.dart';
import 'package:coffee_tracker/features/auth/application/auth_providers.dart';
import 'package:coffee_tracker/features/auth/presentation/sign_in_page.dart';
import 'package:coffee_tracker/features/dashboard/presentation/home_page.dart';
import 'package:coffee_tracker/features/group_overview/presentation/balances_table.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/notifications/application/notification_providers.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/fakes.dart';
import '../helpers/samples.dart';
import '../helpers/test_app.dart';

/// Renders [child] with the system text size doubled.
Widget scaled(Widget child) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
    child: child,
  ),
);

void main() {
  late StreamController<bool> network;

  setUp(() => network = StreamController<bool>.broadcast());
  tearDown(() => network.close());

  Future<List<Override>> overrides() async => [
    ...queueOverrides(
      preferences: await inMemoryPreferences(),
      ledger: FakeLedgerRepository(),
      clock: TestClock(DateTime.utc(2026, 10, 22, 9)),
      network: network,
    ),
    currentUserIdProvider.overrideWithValue('alice'),
    currentGroupIdProvider.overrideWithValue('g1'),
    unreadNotificationsProvider.overrideWithValue(0),
    dashboardProvider.overrideWith((ref, groupId) async => sampleDashboard()),
    pendingActionsProvider.overrideWith((ref, groupId) async => PendingActions.empty),
  ];

  testWidgets('home works with 200% text on a phone', (tester) async {
    setScreenSize(tester, phone);
    await tester.pumpWidget(testApp(scaled(const HomePage()), overrides: await overrides()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('You owe'), findsOneWidget);
  });

  testWidgets('sign in works with 200% text on a phone', (tester) async {
    setScreenSize(tester, phone);
    await tester.pumpWidget(testApp(scaled(const SignInPage())));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('balances work with 200% text on a phone', (tester) async {
    setScreenSize(tester, phone);
    await tester.pumpWidget(
      testApp(
        scaled(
          Scaffold(
            body: SingleChildScrollView(
              child: BalancesTable(rows: sampleBalances(), currency: 'EUR'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the coffee button has a meaningful screen-reader label', (tester) async {
    setScreenSize(tester, phone);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(testApp(const HomePage(), overrides: await overrides()));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Add one coffee for €0.20'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('You owe €4.20')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('skeletons are hidden from screen readers but announce loading', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(testApp(const Scaffold(body: SkeletonList())));
    expect(find.bySemanticsLabel('Loading…'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('tap targets meet the Android guideline on the home screen', (tester) async {
    setScreenSize(tester, phone);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(testApp(const HomePage(), overrides: await overrides()));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('text contrast meets the guideline on the home screen', (tester) async {
    setScreenSize(tester, phone);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(testApp(const HomePage(), overrides: await overrides()));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
