import 'dart:async';

import 'package:coffee_tracker/features/accounting/application/report_providers.dart';
import 'package:coffee_tracker/features/accounting/data/ledger_repository.dart';
import 'package:coffee_tracker/features/accounting/domain/ledger_models.dart';
import 'package:coffee_tracker/features/coffee/presentation/coffee_button.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/transactions/presentation/forms/transaction_forms.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/fakes.dart';
import '../helpers/samples.dart';
import '../helpers/test_app.dart';

class _FormLedger extends FakeLedgerRepository {
  final deposits = <({int cents, String key})>[];
  final purchases = <({PurchaseFunding funding, int cents, String description})>[];

  @override
  Future<TransactionResult> submitDeposit({
    required String groupId,
    required int amountCents,
    required String idempotencyKey,
    String? description,
    String? forMemberId,
  }) async {
    deposits.add((cents: amountCents, key: idempotencyKey));
    return const TransactionResult(transactionId: 'd1', status: TransactionStatus.pending, replayed: false);
  }

  @override
  Future<TransactionResult> submitPurchase({
    required String groupId,
    required PurchaseFunding funding,
    required int amountCents,
    required String description,
    required String idempotencyKey,
    DateTime? purchasedAt,
    String? evidencePath,
    String? forMemberId,
  }) async {
    purchases.add((funding: funding, cents: amountCents, description: description));
    return const TransactionResult(transactionId: 'p1', status: TransactionStatus.posted, replayed: false);
  }
}

void main() {
  late _FormLedger ledger;
  late StreamController<bool> network;

  setUp(() {
    ledger = _FormLedger();
    network = StreamController<bool>.broadcast();
  });

  tearDown(() => network.close());

  Future<List<Override>> overrides() async => [
    ...queueOverrides(
      preferences: await inMemoryPreferences(),
      ledger: ledger,
      clock: TestClock(DateTime.utc(2026, 10, 22, 9)),
      network: network,
    ),
    dashboardProvider.overrideWith((ref, groupId) async => sampleDashboard()),
    membersProvider.overrideWith((ref, groupId) async => sampleMembers()),
  ];

  testWidgets('one tap records a coffee, confirms it and offers Undo', (tester) async {
    setScreenSize(tester, phone);
    await tester.pumpWidget(
      testApp(
        const Scaffold(
          body: CoffeeButton(groupId: 'g1', todayCoffees: 2, priceLabel: '€0.20'),
        ),
        overrides: await overrides(),
      ),
    );
    expect(find.text('+1 Coffee'), findsOneWidget);
    expect(find.text('2 coffees today · €0.20 each'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-coffee-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(ledger.calls, hasLength(1));
    expect(find.text('Coffee recorded — you owe €0.20.'), findsOneWidget);
    expect(find.text('Enjoy!'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500)); // let the snackbar finish sliding in
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(ledger.undone, ['txn-${ledger.calls.single.key}']);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('several coffees at once', (tester) async {
    setScreenSize(tester, phone);
    await tester.pumpWidget(
      testApp(
        const Scaffold(
          body: CoffeeButton(groupId: 'g1', todayCoffees: 0, priceLabel: '€0.20'),
        ),
        overrides: await overrides(),
      ),
    );
    await tester.tap(find.text('Several'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.tap(find.text('Record 3 coffees'));
    await tester.pumpAndSettle();
    expect(ledger.calls.single.quantity, 3);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('deposit form validates the amount and submits exact cents', (tester) async {
    setScreenSize(tester, phone);
    await tester.pumpWidget(
      testApp(
        const Scaffold(body: DepositForm(groupId: 'g1')),
        overrides: await overrides(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('A treasurer confirms it'), findsOneWidget);

    await tester.tap(find.text('Record deposit'));
    await tester.pumpAndSettle();
    expect(find.text('Enter an amount like 4.50.'), findsOneWidget);
    expect(ledger.deposits, isEmpty);

    await tester.enterText(find.byType(TextFormField).first, '5,50');
    await tester.tap(find.text('Record deposit'));
    await tester.pumpAndSettle();
    expect(ledger.deposits.single.cents, 550);
  });

  testWidgets('purchase form explains the difference between personal and box funding', (tester) async {
    setScreenSize(tester, phone);
    await tester.pumpWidget(
      testApp(
        const Scaffold(body: PurchaseForm(groupId: 'g1')),
        overrides: await overrides(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('You are credited the amount you paid'), findsOneWidget);

    await tester.tap(find.text('Cash box'));
    await tester.pumpAndSettle();
    expect(find.textContaining('The money comes out of the cash box'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '15');
    await tester.tap(find.text('Record purchase'));
    await tester.pumpAndSettle();
    expect(ledger.purchases.single, (funding: PurchaseFunding.cashBox, cents: 1500, description: 'Coffee beans'));
  });
}
