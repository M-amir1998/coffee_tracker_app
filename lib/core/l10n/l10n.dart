import 'package:coffee_tracker/core/money/money.dart';
import 'package:coffee_tracker/l10n/generated/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

export 'package:coffee_tracker/l10n/generated/app_localizations.dart';

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  /// BCP 47 tag of the active locale, e.g. `en` or `es`.
  String get localeTag => Localizations.localeOf(this).toLanguageTag();

  String money(int cents, {bool signed = false, String currency = 'EUR'}) =>
      Money.format(cents, locale: localeTag, currency: currency, signed: signed);

  String shortDate(DateTime value) => DateFormat.yMMMd(localeTag).format(value.toLocal());

  String dayMonth(DateTime value) => DateFormat.MMMd(localeTag).format(value.toLocal());

  String time(DateTime value) => DateFormat.Hm(localeTag).format(value.toLocal());

  String dateTime(DateTime value) => DateFormat.yMMMd(localeTag).add_Hm().format(value.toLocal());

  String monthYear(DateTime value) => DateFormat.yMMMM(localeTag).format(value);

  String monthShort(DateTime value) => DateFormat.MMM(localeTag).format(value);

  String weekdayName(int isoWeekday) =>
      DateFormat.EEEE(localeTag).format(DateTime(2024, 1, isoWeekday)); // 2024-01-01 is a Monday

  String weekdayShort(int isoWeekday) => DateFormat.E(localeTag).format(DateTime(2024, 1, isoWeekday));

  String number(num value) => NumberFormat.decimalPattern(localeTag).format(value);
}
