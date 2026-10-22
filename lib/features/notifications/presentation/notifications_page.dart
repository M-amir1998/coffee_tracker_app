import 'dart:async';

import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/app/routes.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/app_card.dart';
import 'package:coffee_tracker/core/widgets/feedback.dart';
import 'package:coffee_tracker/core/widgets/page_layout.dart';
import 'package:coffee_tracker/core/widgets/states.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/notifications/application/notification_providers.dart';
import 'package:coffee_tracker/features/notifications/domain/app_notification.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Localized text of a notification, built from its kind and payload.
String notificationText(BuildContext context, AppNotification n) {
  final l10n = context.l10n;
  final actor = n.actorName ?? l10n.someone;
  final member = n.memberName ?? l10n.someone;
  final amount = n.amountCents == null ? '' : context.money(n.amountCents!);
  final note = n.note;
  String withNote(String text) => note == null || note.isEmpty ? text : '$text “$note”';

  return switch (n.kind) {
    'transfer_requested' => l10n.nTransferRequested(actor, amount),
    'transfer_confirmed' => l10n.nTransferConfirmed(n.counterpartyName ?? actor, amount),
    'transfer_rejected' => withNote(l10n.nTransferRejected(n.counterpartyName ?? actor, amount)),
    'deposit_pending' => l10n.nDepositPending(member, amount),
    'deposit_confirmed' => l10n.nDepositConfirmed(amount),
    'deposit_rejected' => withNote(l10n.nDepositRejected(amount)),
    'deposit_recorded' => l10n.nDepositRecorded(actor, amount),
    'purchase_pending' => l10n.nPurchasePending(member, amount),
    'purchase_approved' => l10n.nPurchaseApproved(amount),
    'purchase_rejected' => withNote(l10n.nPurchaseRejected(amount)),
    'reimbursement_requested' => l10n.nReimbursementRequested(member, amount),
    'reimbursement_paid' => l10n.nReimbursementPaid(actor, amount),
    'reimbursement_rejected' => withNote(l10n.nReimbursementRejected(amount)),
    'transaction_cancelled' => l10n.nTransactionCancelled(actor, amount),
    'transaction_reversed' => withNote(l10n.nTransactionReversed(actor, amount)),
    'dispute_opened' => withNote(l10n.nDisputeOpened(actor, amount)),
    'dispute_resolved' => withNote(
      n.payload['approved'] == true ? l10n.nDisputeApproved(amount) : l10n.nDisputeRejected(amount),
    ),
    'balance_adjusted' => withNote(l10n.nBalanceAdjusted(actor, amount)),
    'coffee_recorded_for_you' => l10n.nCoffeeForYou(actor, (n.payload['quantity'] as num?)?.toInt() ?? 1),
    'price_changed' => l10n.nPriceChanged(context.money((n.payload['price_cents'] as num?)?.toInt() ?? 0)),
    'cycle_closed' => _cycleClosedText(context, n),
    'role_changed' => l10n.nRoleChanged(n.payload['role'] as String? ?? ''),
    'member_joined' => l10n.nMemberJoined(member),
    'coffee_hero' => l10n.nCoffeeHero(
      ((n.payload['winners'] as List?) ?? const <Object?>[])
          .map((w) => (w! as Map)['display_name'] as String? ?? '')
          .join(', '),
    ),
    _ => l10n.nGeneric,
  };
}

String _cycleClosedText(BuildContext context, AppNotification n) {
  final closing = (n.payload['closing_cents'] as num?)?.toInt() ?? 0;
  final status = closing > 0 ? 'owes' : (closing < 0 ? 'owed' : 'settled');
  return context.l10n.nCycleClosed(n.payload['cycle_name'] as String? ?? '', context.money(closing.abs()), status);
}

IconData notificationIcon(String kind) => switch (kind) {
  'transfer_requested' || 'transfer_confirmed' || 'transfer_rejected' => Icons.swap_horiz_rounded,
  'deposit_pending' || 'deposit_confirmed' || 'deposit_rejected' || 'deposit_recorded' => Icons.savings_rounded,
  'purchase_pending' || 'purchase_approved' || 'purchase_rejected' => Icons.shopping_bag_rounded,
  'reimbursement_requested' || 'reimbursement_paid' || 'reimbursement_rejected' => Icons.payments_rounded,
  'cycle_closed' => Icons.lock_clock_rounded,
  'coffee_hero' => Icons.workspace_premium_rounded,
  'price_changed' => Icons.sell_rounded,
  'dispute_opened' || 'dispute_resolved' => Icons.gavel_rounded,
  _ => Icons.notifications_rounded,
};

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, AppNotification n) async {
    if (n.isUnread) {
      try {
        await ref.read(notificationRepositoryProvider).markRead([n.id]);
        ref.invalidate(notificationsProvider);
      } on Object {
        // Marking as read is best effort.
      }
    }
    if (!context.mounted) return;
    if (n.groupId != null && n.groupId != ref.read(currentGroupIdProvider)) {
      await ref.read(selectedGroupIdProvider.notifier).select(n.groupId!);
    }
    if (!context.mounted) return;
    if (n.transactionId != null) {
      unawaited(context.push(Routes.transaction(n.transactionId!)));
    } else if (n.kind == 'cycle_closed') {
      context.go(Routes.cycles);
    } else if (n.kind == 'coffee_hero') {
      context.go(Routes.heroes);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final notifications = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadNotificationsProvider);

    return AppPage(
      title: l10n.navNotifications,
      maxWidth: 760,
      onRefresh: () async => ref.invalidate(notificationsProvider),
      actions: [
        if (unread > 0)
          TextButton.icon(
            onPressed: () async {
              try {
                await ref.read(notificationRepositoryProvider).markRead();
                ref.invalidate(notificationsProvider);
              } on Object catch (error) {
                if (context.mounted) showErrorToast(context, error);
              }
            },
            icon: const Icon(Icons.done_all_rounded),
            label: Text(l10n.markAllRead),
          ),
      ],
      body: AsyncValueView(
        value: notifications,
        onRetry: () => ref.invalidate(notificationsProvider),
        data: (items) => items.isEmpty
            ? EmptyState(
                icon: Icons.notifications_none_rounded,
                title: l10n.notificationsEmpty,
                message: l10n.notificationsEmptyHint,
              )
            : AppCard(
                padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                child: Column(
                  children: [
                    for (final n in items)
                      ListTile(
                        leading: Badge(
                          isLabelVisible: n.isUnread,
                          smallSize: 10,
                          child: Icon(notificationIcon(n.kind), color: theme.colorScheme.secondary),
                        ),
                        title: Text(
                          notificationText(context, n),
                          style: n.isUnread ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium,
                        ),
                        subtitle: Text(context.dateTime(n.createdAt)),
                        onTap: () => unawaited(_open(context, ref, n)),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
