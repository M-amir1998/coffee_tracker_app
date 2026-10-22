import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/money/money.dart';
import 'package:coffee_tracker/core/theme/app_theme.dart';
import 'package:coffee_tracker/core/theme/finance_colors.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/app_card.dart';
import 'package:coffee_tracker/core/widgets/money_text.dart';
import 'package:coffee_tracker/features/dashboard/domain/dashboard.dart';
import 'package:material_ui/material_ui.dart';

/// The member's position in plain words: "You owe", "The group owes you" or
/// "You're all settled", with the figures that explain it.
class BalanceCard extends StatelessWidget {
  const BalanceCard({required this.dashboard, super.key});

  final Dashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final finance = FinanceColors.of(context);
    final balance = dashboard.balance;
    final status = balance.status;
    final currency = dashboard.group.currency;

    final (headline, color, container) = switch (status) {
      BalanceStatus.owes => (l10n.balanceYouOwe, finance.owes, finance.owesContainer),
      BalanceStatus.owed => (l10n.balanceGroupOwesYou, finance.owed, finance.owedContainer),
      BalanceStatus.settled => (l10n.balanceSettled, finance.settled, finance.settledContainer),
    };

    final amount = context.money(balance.netCents.abs(), currency: currency);
    return AppCard(
      semanticLabel: status == BalanceStatus.settled ? headline : '$headline $amount',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(color: container, borderRadius: BorderRadius.circular(Radii.pill)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Text(dashboard.cycle.name, style: theme.textTheme.labelMedium?.copyWith(color: color)),
                ),
              ),
              const Spacer(),
              Text(l10n.pricePerCoffee(context.money(dashboard.priceCents, currency: currency)), style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: Spacing.md),
          Text(headline, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: Spacing.xxs),
          ExcludeSemantics(
            child: Text(
              status == BalanceStatus.settled ? context.money(0, currency: currency) : amount,
              style: theme.textTheme.displayMedium?.copyWith(
                color: color,
                fontFamily: AppTheme.bodyFont,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.5,
                fontFeatures: tabularFigures,
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
          Wrap(
            spacing: Spacing.lg,
            runSpacing: Spacing.sm,
            children: [
              _Figure(label: l10n.figureCoffees, value: context.number(balance.coffees)),
              _Figure(label: l10n.figureConsumption, value: context.money(balance.consumptionCents, currency: currency)),
              _Figure(label: l10n.figureContributed, value: context.money(balance.contributionsCents, currency: currency)),
              if (balance.transfersSentCents != 0 || balance.transfersReceivedCents != 0)
                _Figure(
                  label: l10n.figureSettlements,
                  value: context.money(balance.transfersReceivedCents - balance.transfersSentCents, currency: currency, signed: true),
                ),
              if (balance.reimbursementsCents != 0)
                _Figure(label: l10n.figureReimbursed, value: context.money(balance.reimbursementsCents, currency: currency)),
            ],
          ),
          if (balance.openingCents != 0) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              balance.openingCents > 0
                  ? l10n.carriedOverDebt(context.money(balance.openingCents, currency: currency))
                  : l10n.carriedOverCredit(context.money(-balance.openingCents, currency: currency)),
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (dashboard.nextPrice case final next?) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              l10n.nextPriceNotice(context.money(next.priceCents, currency: currency), context.shortDate(next.from)),
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (!balance.isConsistent) ...[
            const SizedBox(height: Spacing.sm),
            Text(l10n.balanceInconsistent, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          ],
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(value, style: theme.textTheme.titleMedium?.copyWith(fontFeatures: tabularFigures)),
        ],
      ),
    );
  }
}
