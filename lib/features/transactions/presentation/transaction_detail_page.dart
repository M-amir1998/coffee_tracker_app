import 'dart:async';

import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/core/data/rpc.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/app_card.dart';
import 'package:coffee_tracker/core/widgets/feedback.dart';
import 'package:coffee_tracker/core/widgets/money_text.dart';
import 'package:coffee_tracker/core/widgets/page_layout.dart';
import 'package:coffee_tracker/core/widgets/states.dart';
import 'package:coffee_tracker/core/widgets/status_chip.dart';
import 'package:coffee_tracker/features/accounting/application/report_providers.dart';
import 'package:coffee_tracker/features/accounting/domain/ledger_models.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/transactions/presentation/activity_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class TransactionDetailPage extends ConsumerWidget {
  const TransactionDetailPage({required this.transactionId, super.key});

  final String transactionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final detail = ref.watch(transactionDetailProvider(transactionId));
    return AppPage(
      title: l10n.transactionTitle,
      showBackButton: true,
      maxWidth: 960,
      body: AsyncValueView(
        value: detail,
        onRetry: () => ref.invalidate(transactionDetailProvider(transactionId)),
        data: (data) => ResponsiveColumns(
          minColumnWidth: 420,
          maxColumns: 2,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Summary(detail: data),
                if (data.permissions.any) ...[const SizedBox(height: Spacing.md), _Actions(detail: data)],
              ],
            ),
            _History(detail: data),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.detail});

  final TransactionDetail detail;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final item = detail.item;
    final facts = <(String, String)>[
      (l10n.factType, kindLabel(l10n, item.kind)),
      if (item.kind == TransactionKind.coffee && item.quantity != null && item.unitPriceCents != null)
        (l10n.factCoffees, l10n.coffeesAtPrice(item.quantity!, context.money(item.unitPriceCents!))),
      if (item.memberName != null)
        (
          switch (item.kind) {
            TransactionKind.transfer => l10n.factFrom,
            TransactionKind.reimbursement => l10n.factReimbursedMember,
            TransactionKind.purchasePersonal || TransactionKind.purchaseBox => l10n.factBuyer,
            _ => l10n.factMember,
          },
          item.memberName!,
        ),
      if (item.counterpartyName != null) (l10n.factTo, item.counterpartyName!),
      if (item.initiatorName != null) (l10n.factRecordedBy, item.initiatorName!),
      (item.kind == TransactionKind.coffee ? l10n.factDrunkAt : l10n.factDate, context.dateTime(item.occurredAt)),
      (l10n.factRecordedAt, context.dateTime(item.createdAt)),
      if (item.cycleName != null) (l10n.factCycle, item.cycleName!),
      if (item.kind == TransactionKind.purchaseBox) (l10n.factFunding, l10n.purchaseFundingBox),
      if (item.kind == TransactionKind.purchasePersonal) (l10n.factFunding, l10n.purchaseFundingPersonal),
      if (detail.reversesKind != null) (l10n.factReverses, kindLabel(l10n, detail.reversesKind)),
      if (item.description != null) (l10n.factDescription, item.description!),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(activitySentence(context, item), style: theme.textTheme.titleLarge)),
              if (item.status != null) TransactionStatusChip(item.status!),
            ],
          ),
          if (item.amountCents != null) ...[
            const SizedBox(height: Spacing.sm),
            MoneyText(item.amountCents!, style: theme.textTheme.displaySmall?.copyWith(fontFamily: 'Inter')),
          ],
          if (item.status?.isOpen ?? false) ...[
            const SizedBox(height: Spacing.xs),
            Text(l10n.pendingNotCounted, style: theme.textTheme.bodySmall),
          ],
          if (detail.reversalId != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(l10n.reversedNotice(detail.reversalNote ?? ''), style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: Spacing.md),
          for (final (label, value) in facts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 140, child: Text(label, style: theme.textTheme.bodySmall)),
                  Expanded(child: SelectableText(value, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Actions extends ConsumerStatefulWidget {
  const _Actions({required this.detail});

  final TransactionDetail detail;

  @override
  ConsumerState<_Actions> createState() => _ActionsState();
}

class _ActionsState extends ConsumerState<_Actions> {
  bool _busy = false;

  Future<void> _run(Future<TransactionResult> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.read(dataRevisionProvider.notifier).bump();
      if (mounted) showToast(context, success, icon: Icons.check_circle_outline_rounded);
    } on Object catch (error) {
      if (mounted) showErrorToast(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ledger = ref.read(ledgerRepositoryProvider);
    final item = widget.detail.item;
    final p = widget.detail.permissions;
    final id = item.id;

    final buttons = <Widget>[
      if (p.canDecide) ...[
        FilledButton.icon(
          onPressed: _busy ? null : () => unawaited(_run(() => ledger.respond(id, approve: true), l10n.confirmedToast)),
          icon: const Icon(Icons.check_rounded),
          label: Text(item.kind == TransactionKind.transfer ? l10n.confirmReceived : l10n.approve),
        ),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  final note = await askForNote(
                    context,
                    title: l10n.rejectTitle,
                    label: l10n.rejectReason,
                    confirmLabel: l10n.reject,
                    destructive: true,
                  );
                  if (note != null) {
                    await _run(() => ledger.respond(id, approve: false, note: note), l10n.rejectedToast);
                  }
                },
          icon: const Icon(Icons.close_rounded),
          label: Text(l10n.reject),
        ),
      ],
      if (p.canCancel)
        OutlinedButton.icon(
          onPressed: _busy ? null : () => unawaited(_run(() => ledger.cancel(id), l10n.cancelledToast)),
          icon: const Icon(Icons.cancel_outlined),
          label: Text(l10n.cancelSubmission),
        ),
      if (p.canDispute)
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  final note = await askForNote(
                    context,
                    title: l10n.disputeTitle,
                    label: l10n.disputeReason,
                    confirmLabel: l10n.dispute,
                  );
                  if (note != null) await _run(() => ledger.dispute(id, note), l10n.disputedToast);
                },
          icon: const Icon(Icons.gavel_rounded),
          label: Text(l10n.dispute),
        ),
      if (p.canResolve) ...[
        FilledButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  final note = await askForNote(
                    context,
                    title: l10n.resolveApproveTitle,
                    label: l10n.resolutionNote,
                    confirmLabel: l10n.approve,
                  );
                  if (note != null) {
                    await _run(() => ledger.resolveDispute(id, approve: true, note: note), l10n.confirmedToast);
                  }
                },
          icon: const Icon(Icons.check_rounded),
          label: Text(l10n.resolveApprove),
        ),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  final note = await askForNote(
                    context,
                    title: l10n.resolveRejectTitle,
                    label: l10n.resolutionNote,
                    confirmLabel: l10n.reject,
                    destructive: true,
                  );
                  if (note != null) {
                    await _run(() => ledger.resolveDispute(id, approve: false, note: note), l10n.rejectedToast);
                  }
                },
          icon: const Icon(Icons.close_rounded),
          label: Text(l10n.resolveReject),
        ),
      ],
      if (p.canUndo)
        OutlinedButton.icon(
          onPressed: _busy ? null : () => unawaited(_run(() => ledger.undoCoffee(id), l10n.coffeeUndone)),
          icon: const Icon(Icons.undo_rounded),
          label: Text(l10n.undoCoffee),
        ),
      if (p.canReverse)
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
          onPressed: _busy
              ? null
              : () async {
                  final note = await askForNote(
                    context,
                    title: l10n.reverseTitle,
                    label: l10n.reverseReason,
                    confirmLabel: l10n.reverse,
                    destructive: true,
                  );
                  if (note != null) {
                    final key = newIdempotencyKey();
                    await _run(() => ledger.reverse(id, note: note, idempotencyKey: key), l10n.reversedToast);
                  }
                },
          icon: const Icon(Icons.undo_rounded),
          label: Text(l10n.reverse),
        ),
    ];

    return SectionCard(
      title: l10n.actionsTitle,
      child: Wrap(spacing: Spacing.sm, runSpacing: Spacing.sm, children: buttons),
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.detail});

  final TransactionDetail detail;

  String _statusText(AppLocalizations l10n, TransactionEvent event) {
    if (event.isAnnotation) return l10n.historyNote;
    if (event.fromStatus == null) {
      return event.toStatus == TransactionStatus.pending ? l10n.historySubmitted : l10n.historyRecorded;
    }
    return switch (event.toStatus) {
      TransactionStatus.posted => l10n.historyConfirmed,
      TransactionStatus.rejected => l10n.historyRejected,
      TransactionStatus.cancelled => l10n.historyCancelled,
      TransactionStatus.disputed => l10n.historyDisputed,
      TransactionStatus.reversed => l10n.historyReversed,
      TransactionStatus.pending => l10n.historySubmitted,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return SectionCard(
      title: l10n.historyTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, event) in detail.events.indexed)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    children: [
                      Icon(Icons.circle, size: 12, color: theme.colorScheme.secondary),
                      if (index < detail.events.length - 1)
                        Expanded(child: VerticalDivider(width: 12, color: theme.colorScheme.outlineVariant)),
                    ],
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_statusText(l10n, event), style: theme.textTheme.titleSmall),
                          Text(
                            [
                              if (event.actorName != null) event.actorName!,
                              context.dateTime(event.createdAt),
                            ].join(' · '),
                            style: theme.textTheme.bodySmall,
                          ),
                          if (event.note != null) ...[const SizedBox(height: 2), Text('“${event.note!}”')],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
