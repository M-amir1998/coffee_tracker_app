import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/money/money.dart';
import 'package:coffee_tracker/core/theme/finance_colors.dart';
import 'package:material_ui/material_ui.dart';

const tabularFigures = [FontFeature.tabularFigures()];

/// A money amount with tabular figures. With [colorBySign] a member balance is
/// colored by its meaning: owes (positive), owed (negative) or settled.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.cents, {
    super.key,
    this.style,
    this.colorBySign = false,
    this.signed = false,
    this.currency = 'EUR',
  });

  final int cents;
  final TextStyle? style;
  final bool colorBySign;
  final bool signed;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final colors = FinanceColors.of(context);
    final color = !colorBySign
        ? base.color
        : switch (BalanceStatus.fromNet(cents)) {
            BalanceStatus.owes => colors.owes,
            BalanceStatus.owed => colors.owed,
            BalanceStatus.settled => colors.settled,
          };
    return Text(
      context.money(cents, signed: signed, currency: currency),
      style: base.copyWith(color: color, fontFeatures: tabularFigures),
      maxLines: 1,
      softWrap: false,
    );
  }
}
