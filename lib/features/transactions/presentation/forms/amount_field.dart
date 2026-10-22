import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/money/money.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// Money input that accepts `4`, `4.5`, `4,50` and validates to exact cents.
class AmountField extends StatelessWidget {
  const AmountField({
    required this.controller,
    required this.label,
    super.key,
    this.helper,
    this.maxCents = 500000,
    this.autofocus = false,
    this.currency = 'EUR',
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;
  final int maxCents;
  final bool autofocus;
  final String currency;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final symbol = NumberFormat.simpleCurrency(locale: context.localeTag, name: currency).currencySymbol;
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')), LengthLimitingTextInputFormatter(10)],
      style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
      decoration: InputDecoration(labelText: label, helperText: helper, prefixText: '$symbol '),
      onChanged: onChanged,
      validator: (value) {
        final cents = Money.parse(value ?? '');
        if (cents == null) return l10n.validationAmountFormat;
        if (cents <= 0) return l10n.validationAmountPositive;
        if (cents > maxCents) return l10n.validationAmountMax(context.money(maxCents, currency: currency));
        return null;
      },
    );
  }
}
