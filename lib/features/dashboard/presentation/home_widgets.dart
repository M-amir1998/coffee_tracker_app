import 'dart:async';

import 'package:coffee_tracker/app/routes.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/app_card.dart';
import 'package:coffee_tracker/core/widgets/states.dart';
import 'package:coffee_tracker/features/accounting/application/report_providers.dart';
import 'package:coffee_tracker/features/dashboard/domain/dashboard.dart';
import 'package:coffee_tracker/features/transactions/presentation/activity_tile.dart';
import 'package:coffee_tracker/features/transactions/presentation/forms/transaction_forms.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Shortcuts to the money operations.
class QuickActions extends StatelessWidget {
  const QuickActions({required this.dashboard, super.key});

  final Dashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final groupId = dashboard.group.id;
    final owed = dashboard.allTimeNetCents < 0;
    final actions = [
      (Icons.savings_rounded, l10n.actionDeposit, () => showDepositForm(context, groupId: groupId)),
      (Icons.shopping_bag_rounded, l10n.actionBoughtBeans, () => showPurchaseForm(context, groupId: groupId)),
      (Icons.swap_horiz_rounded, l10n.actionPaidSomeone, () => showTransferForm(context, groupId: groupId)),
      if (dashboard.role.managesCash)
        (Icons.payments_rounded, l10n.actionReimburse, () => showReimbursementForm(context, groupId: groupId))
      else if (owed)
        (
          Icons.payments_rounded,
          l10n.actionRequestReimbursement,
          () => showReimbursementForm(context, groupId: groupId, suggestedCents: -dashboard.allTimeNetCents),
        ),
      (Icons.handshake_rounded, l10n.actionSettleUp, () async => context.go(Routes.settle)),
    ];
    return SectionCard(
      title: l10n.quickActionsTitle,
      child: Wrap(
        spacing: Spacing.sm,
        runSpacing: Spacing.sm,
        children: [
          for (final (icon, label, onTap) in actions)
            ActionChip(
              avatar: Icon(icon, size: 18),
              label: Text(label),
              onPressed: () => unawaited(onTap()),
            ),
        ],
      ),
    );
  }
}

/// Items that wait for the member's decision, and their own pending items.
class AttentionCard extends ConsumerWidget {
  const AttentionCard({required this.groupId, super.key});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final pending = ref.watch(pendingActionsProvider(groupId)).value;
    if (pending == null || pending.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return SectionCard(
      title: l10n.attentionTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pending.toReview.isNotEmpty) ...[
            Text(l10n.attentionToReview(pending.toReview.length), style: theme.textTheme.labelLarge),
            for (final item in pending.toReview.take(5)) ActivityTile(item: item, dense: true),
          ],
          if (pending.mySubmissions.isNotEmpty) ...[
            if (pending.toReview.isNotEmpty) const Divider(height: Spacing.lg),
            Text(l10n.attentionMine(pending.mySubmissions.length), style: theme.textTheme.labelLarge),
            for (final item in pending.mySubmissions.take(5)) ActivityTile(item: item, dense: true),
          ],
        ],
      ),
    );
  }
}

class RecentActivityCard extends StatelessWidget {
  const RecentActivityCard({required this.dashboard, super.key});

  final Dashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SectionCard(
      title: l10n.recentActivityTitle,
      trailing: TextButton(onPressed: () => context.go(Routes.activity), child: Text(l10n.seeAll)),
      child: dashboard.recent.isEmpty
          ? EmptyState(icon: Icons.coffee_outlined, title: l10n.recentEmptyTitle, message: l10n.recentEmptyMessage)
          : Column(children: [for (final item in dashboard.recent) ActivityTile(item: item, dense: true)]),
    );
  }
}

/// A rotating coffee quote, stable for the day.
class QuoteCard extends StatelessWidget {
  const QuoteCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final quotes = [l10n.quote1, l10n.quote2, l10n.quote3, l10n.quote4, l10n.quote5, l10n.quote6, l10n.quote7];
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year)).inDays;
    return AppCard(
      color: theme.colorScheme.secondaryContainer,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.format_quote_rounded, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              quotes[dayOfYear % quotes.length],
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
