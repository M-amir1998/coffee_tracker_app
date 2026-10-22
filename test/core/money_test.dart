import 'package:coffee_tracker/core/money/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money.parse', () {
    test('accepts whole euros, dot and comma decimals', () {
      expect(Money.parse('12'), 1200);
      expect(Money.parse('12.5'), 1250);
      expect(Money.parse('12,75'), 1275);
      expect(Money.parse('0.20'), 20);
      expect(Money.parse('0,2'), 20);
      expect(Money.parse('0'), 0);
    });

    test('ignores currency symbols and spaces', () {
      expect(Money.parse('€ 3,20'), 320);
      expect(Money.parse(' 4.10 € '), 410);
      expect(Money.parse('5 €'), 500);
    });

    test('rejects malformed, negative or too precise input', () {
      expect(Money.parse(''), isNull);
      expect(Money.parse('abc'), isNull);
      expect(Money.parse('-3'), isNull);
      expect(Money.parse('1.234'), isNull);
      expect(Money.parse('1,000.50'), isNull);
      expect(Money.parse('1.2.3'), isNull);
      expect(Money.parse('1234567'), isNull);
    });

    test('is exact for every cent value (no floating point)', () {
      for (var cents = 0; cents <= 100000; cents += 7) {
        final text = '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
        expect(Money.parse(text), cents, reason: text);
      }
    });
  });

  group('Money.format', () {
    test('formats euros in English and Spanish', () {
      expect(Money.format(420, locale: 'en'), '€4.20');
      expect(Money.format(420, locale: 'es'), contains('4,20'));
      expect(Money.format(123456, locale: 'en'), '€1,234.56');
    });

    test('uses a real minus sign for negative amounts', () {
      expect(Money.format(-800, locale: 'en'), '−€8.00');
    });

    test('shows a plus sign only when asked', () {
      expect(Money.format(150, locale: 'en', signed: true), '+€1.50');
      expect(Money.format(150, locale: 'en'), '€1.50');
      expect(Money.format(0, locale: 'en', signed: true), '€0.00');
    });

    test('round-trips through input text', () {
      for (final cents in [0, 1, 20, 99, 100, 1275, 500000]) {
        expect(Money.parse(Money.toInput(cents, locale: 'en')), cents);
        expect(Money.parse(Money.toInput(cents, locale: 'es')), cents);
      }
    });
  });

  group('BalanceStatus', () {
    test('positive owes, negative is owed, zero is settled', () {
      expect(BalanceStatus.fromNet(400), BalanceStatus.owes);
      expect(BalanceStatus.fromNet(-800), BalanceStatus.owed);
      expect(BalanceStatus.fromNet(0), BalanceStatus.settled);
    });

    test('parses server values', () {
      expect(BalanceStatus.tryParse('owes'), BalanceStatus.owes);
      expect(BalanceStatus.tryParse('owed'), BalanceStatus.owed);
      expect(BalanceStatus.tryParse('settled'), BalanceStatus.settled);
      expect(BalanceStatus.tryParse('other'), isNull);
    });
  });
}
