import 'package:intl/intl.dart';

/// Money is always handled as integer cents. Conversion to text happens only
/// at the edges (display and input parsing).
abstract final class Money {
  static final _input = RegExp(r'^(\d{1,6})(?:[.,](\d{1,2}))?$');

  /// Parses user input such as `12`, `12.5`, `12,75` or `€ 3,20` into cents.
  /// Returns null for empty, negative, malformed or overly precise input.
  static int? parse(String input) {
    final cleaned = input.trim().replaceAll(RegExp(r'[€\s  ]'), '');
    final match = _input.firstMatch(cleaned);
    if (match == null) return null;
    final euros = int.parse(match.group(1)!);
    final fraction = match.group(2);
    final cents = fraction == null ? 0 : int.parse(fraction.padRight(2, '0'));
    return euros * 100 + cents;
  }

  /// Formats cents as a currency amount, e.g. `€4.20` (en) or `4,20 €` (es).
  /// The sign is only shown when [signed] is true or the amount is negative.
  static String format(int cents, {required String locale, String currency = 'EUR', bool signed = false}) {
    final formatter = NumberFormat.simpleCurrency(locale: locale, name: currency, decimalDigits: 2);
    final magnitude = formatter.format(cents.abs() / 100);
    if (cents < 0) return '−$magnitude';
    if (signed && cents > 0) return '+$magnitude';
    return magnitude;
  }

  /// Text for an input field (no currency symbol, locale decimal separator).
  static String toInput(int cents, {required String locale}) {
    final separator = NumberFormat.decimalPattern(locale).symbols.DECIMAL_SEP;
    final whole = cents.abs() ~/ 100;
    final fraction = (cents.abs() % 100).toString().padLeft(2, '0');
    return '${cents < 0 ? '-' : ''}$whole$separator$fraction';
  }
}

/// How a member stands with the group. Positive net = owes the group.
enum BalanceStatus {
  owes,
  owed,
  settled;

  static BalanceStatus fromNet(int netCents) {
    if (netCents > 0) return BalanceStatus.owes;
    if (netCents < 0) return BalanceStatus.owed;
    return BalanceStatus.settled;
  }

  static BalanceStatus? tryParse(String? value) => switch (value) {
    'owes' => BalanceStatus.owes,
    'owed' => BalanceStatus.owed,
    'settled' => BalanceStatus.settled,
    _ => null,
  };
}
