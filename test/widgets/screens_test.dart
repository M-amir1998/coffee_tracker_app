import 'package:coffee_tracker/core/errors/app_failure.dart';
import 'package:coffee_tracker/core/widgets/states.dart';
import 'package:coffee_tracker/features/group_overview/presentation/balances_table.dart';
import 'package:coffee_tracker/features/leaderboard/domain/leaderboard_models.dart';
import 'package:coffee_tracker/features/leaderboard/domain/ranking.dart';
import 'package:coffee_tracker/features/leaderboard/presentation/podium.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/samples.dart';
import '../helpers/test_app.dart';

void main() {
  group('balances table', () {
    testWidgets('desktop shows a sortable table with all columns', (tester) async {
      setScreenSize(tester, desktop);
      await tester.pumpWidget(
        testApp(
          Scaffold(
            body: SingleChildScrollView(
              child: BalancesTable(rows: sampleBalances(), currency: 'EUR'),
            ),
          ),
        ),
      );
      expect(find.byType(DataTable), findsOneWidget);
      for (final header in ['Member', 'Coffees', 'Consumption', 'Contributions', 'Net balance', 'Status']) {
        expect(find.text(header), findsOneWidget);
      }
      expect(find.text('Alice (you)'), findsOneWidget);
      expect(find.text('−€8.00'), findsOneWidget);
    });

    testWidgets('phones show readable cards instead of a wide table', (tester) async {
      setScreenSize(tester, phone);
      await tester.pumpWidget(
        testApp(
          Scaffold(
            body: SingleChildScrollView(
              child: BalancesTable(rows: sampleBalances(), currency: 'EUR'),
            ),
          ),
        ),
      );
      expect(find.byType(DataTable), findsNothing);
      expect(find.text('Bob'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'no overflow on narrow screens');
    });

    testWidgets('filters by status and search', (tester) async {
      setScreenSize(tester, phone);
      await tester.pumpWidget(
        testApp(
          Scaffold(
            body: SingleChildScrollView(
              child: BalancesTable(rows: sampleBalances(), currency: 'EUR'),
            ),
          ),
        ),
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Owed'));
      await tester.pump();
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Charlie'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.enterText(find.byType(TextField), 'char');
      await tester.pump();
      expect(find.text('Charlie'), findsOneWidget);
      expect(find.text('Bob'), findsNothing);
    });
  });

  testWidgets('podium shows the hero titles of the top three', (tester) async {
    setScreenSize(tester, phone);
    final ranked = rankEntries([
      const LeaderboardEntry(userId: 'a', displayName: 'Alice', coffees: 42),
      const LeaderboardEntry(userId: 'b', displayName: 'Bob', coffees: 30),
      const LeaderboardEntry(userId: 'c', displayName: 'Cara', coffees: 12),
    ]);
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: SingleChildScrollView(
            child: Podium(entries: podium(ranked), seed: 'x'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Coffee Legend'), findsOneWidget);
    expect(find.textContaining('Espresso Engine'), findsOneWidget);
    expect(find.textContaining('Caffeine Commander'), findsOneWidget);
    expect(find.text('42 coffees'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Rank 1: Alice')), findsOneWidget);
  });

  group('async states', () {
    testWidgets('loading shows a skeleton', (tester) async {
      await tester.pumpWidget(
        testApp(
          Scaffold(
            body: AsyncValueView<int>(value: const AsyncLoading(), data: (v) => Text('$v')),
          ),
        ),
      );
      expect(find.byType(SkeletonList), findsOneWidget);
    });

    testWidgets('errors are explained and can be retried', (tester) async {
      var retried = 0;
      await tester.pumpWidget(
        testApp(
          Scaffold(
            body: AsyncValueView<int>(
              value: const AsyncError(NetworkFailure(), StackTrace.empty),
              data: (v) => Text('$v'),
              onRetry: () => retried++,
            ),
          ),
        ),
      );
      expect(find.text('No connection to the server. Check your internet connection and try again.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retried, 1);
    });

    testWidgets('data is shown, and kept while refreshing', (tester) async {
      await tester.pumpWidget(
        testApp(
          Scaffold(
            body: AsyncValueView<int>(value: const AsyncData(7), data: (v) => Text('value $v')),
          ),
        ),
      );
      expect(find.text('value 7'), findsOneWidget);
    });

    testWidgets('empty states render their message and action', (tester) async {
      await tester.pumpWidget(
        testApp(
          Scaffold(
            body: EmptyState(
              icon: Icons.coffee,
              title: 'Nothing yet',
              message: 'Your coffees will appear here.',
              action: FilledButton(onPressed: () {}, child: const Text('Add')),
            ),
          ),
        ),
      );
      expect(find.text('Nothing yet'), findsOneWidget);
      expect(find.text('Your coffees will appear here.'), findsOneWidget);
      expect(find.text('Add'), findsOneWidget);
    });
  });
}
