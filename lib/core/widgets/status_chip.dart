import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/money/money.dart';
import 'package:coffee_tracker/core/theme/finance_colors.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/features/accounting/domain/ledger_models.dart';
import 'package:material_ui/material_ui.dart';

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.foreground, required this.background, this.icon});

  final String label;
  final Color foreground;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(Radii.pill)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 14, color: foreground), const SizedBox(width: 4)],
            Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: foreground)),
          ],
        ),
      ),
    );
  }
}

class BalanceStatusChip extends StatelessWidget {
  const BalanceStatusChip(this.status, {super.key});

  final BalanceStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = FinanceColors.of(context);
    final l10n = context.l10n;
    return switch (status) {
      BalanceStatus.owes => _Pill(label: l10n.statusOwes, foreground: colors.owes, background: colors.owesContainer),
      BalanceStatus.owed => _Pill(label: l10n.statusOwed, foreground: colors.owed, background: colors.owedContainer),
      BalanceStatus.settled => _Pill(
        label: l10n.statusSettled,
        foreground: colors.settled,
        background: colors.settledContainer,
        icon: Icons.check_rounded,
      ),
    };
  }
}

/// Shown for every transaction that is not simply "posted", so unconfirmed
/// money is never mistaken for final money.
class TransactionStatusChip extends StatelessWidget {
  const TransactionStatusChip(this.status, {super.key});

  final TransactionStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = FinanceColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return switch (status) {
      TransactionStatus.pending => _Pill(
        label: l10n.txStatusPending,
        foreground: colors.pending,
        background: colors.pendingContainer,
        icon: Icons.schedule_rounded,
      ),
      TransactionStatus.posted => _Pill(
        label: l10n.txStatusPosted,
        foreground: colors.owed,
        background: colors.owedContainer,
        icon: Icons.check_rounded,
      ),
      TransactionStatus.rejected => _Pill(
        label: l10n.txStatusRejected,
        foreground: colors.owes,
        background: colors.owesContainer,
        icon: Icons.block_rounded,
      ),
      TransactionStatus.cancelled => _Pill(
        label: l10n.txStatusCancelled,
        foreground: scheme.onSurfaceVariant,
        background: scheme.surfaceContainerHigh,
      ),
      TransactionStatus.disputed => _Pill(
        label: l10n.txStatusDisputed,
        foreground: colors.pending,
        background: colors.pendingContainer,
        icon: Icons.gavel_rounded,
      ),
      TransactionStatus.reversed => _Pill(
        label: l10n.txStatusReversed,
        foreground: scheme.onSurfaceVariant,
        background: scheme.surfaceContainerHigh,
        icon: Icons.undo_rounded,
      ),
    };
  }
}

class RolePill extends StatelessWidget {
  const RolePill({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Pill(label: label, foreground: scheme.onSecondaryContainer, background: scheme.secondaryContainer);
  }
}
