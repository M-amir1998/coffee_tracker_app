import 'package:coffee_tracker/app/routes.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/money_text.dart';
import 'package:coffee_tracker/core/widgets/status_chip.dart';
import 'package:coffee_tracker/features/accounting/domain/ledger_models.dart';
import 'package:coffee_tracker/features/transactions/presentation/activity_text.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// One row of the activity feed.
class ActivityTile extends StatelessWidget {
  const ActivityTile({required this.item, super.key, this.dense = false});

  final ActivityItem item;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sentence = activitySentence(context, item);
    final status = item.status;
    final muted = status == TransactionStatus.rejected || status == TransactionStatus.cancelled || status == TransactionStatus.reversed;
    final subtitleParts = [
      context.dateTime(item.kind == TransactionKind.coffee ? item.occurredAt : item.createdAt),
      if (item.description != null && item.kind != TransactionKind.reversal) item.description!,
    ];

    return Semantics(
      button: item.isTransaction,
      label: '$sentence. ${subtitleParts.join('. ')}${status == null ? '' : '. ${_statusLabel(context, status)}'}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: item.isTransaction ? () => context.push(Routes.transaction(item.id)) : null,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: dense ? 6 : 10, horizontal: Spacing.xs),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: item.isTransaction ? scheme.secondaryContainer : scheme.tertiaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(9),
                  child: Icon(
                    activityIcon(item),
                    size: 20,
                    color: item.isTransaction ? scheme.onSecondaryContainer : scheme.onTertiaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sentence,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        decoration: status == TransactionStatus.reversed ? TextDecoration.lineThrough : null,
                        color: muted ? scheme.onSurfaceVariant : null,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitleParts.join(' · '),
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (item.amountCents != null)
                    MoneyText(item.amountCents!, style: theme.textTheme.titleSmall?.copyWith(color: muted ? scheme.onSurfaceVariant : null)),
                  if (status != null && status != TransactionStatus.posted) ...[
                    const SizedBox(height: 4),
                    TransactionStatusChip(status),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _statusLabel(BuildContext context, TransactionStatus status) {
    final l10n = context.l10n;
    return switch (status) {
      TransactionStatus.pending => l10n.txStatusPending,
      TransactionStatus.posted => l10n.txStatusPosted,
      TransactionStatus.rejected => l10n.txStatusRejected,
      TransactionStatus.cancelled => l10n.txStatusCancelled,
      TransactionStatus.disputed => l10n.txStatusDisputed,
      TransactionStatus.reversed => l10n.txStatusReversed,
    };
  }
}
