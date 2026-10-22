import 'dart:async';

import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/core/data/rpc.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/money/money.dart';
import 'package:coffee_tracker/core/theme/finance_colors.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/app_card.dart';
import 'package:coffee_tracker/core/widgets/feedback.dart';
import 'package:coffee_tracker/core/widgets/money_text.dart';
import 'package:coffee_tracker/core/widgets/page_layout.dart';
import 'package:coffee_tracker/core/widgets/stat_tile.dart';
import 'package:coffee_tracker/core/widgets/states.dart';
import 'package:coffee_tracker/features/accounting/application/report_providers.dart';
import 'package:coffee_tracker/features/accounting/domain/balance_models.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class CashBoxPage extends ConsumerWidget {
  const CashBoxPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final group = ref.watch(currentGroupProvider).value;
    if (group == null) return const SizedBox.shrink();
    final info = ref.watch(cashBoxProvider(group.id));

    return AppPage(
      title: l10n.adminCashBox,
      showBackButton: true,
      maxWidth: 900,
      onRefresh: () async => ref.invalidate(cashBoxProvider(group.id)),
      body: AsyncValueView(
        value: info,
        onRetry: () => ref.invalidate(cashBoxProvider(group.id)),
        data: (data) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TileGrid(
              children: [
                StatTile(
                  icon: Icons.inventory_2_rounded,
                  label: l10n.expectedCash,
                  value: context.money(data.expectedCents, currency: group.currency),
                  caption: l10n.expectedCashCaption,
                  emphasis: true,
                ),
                StatTile(
                  icon: Icons.schedule_rounded,
                  label: l10n.pendingDeposits,
                  value: context.money(data.pendingDepositsCents, currency: group.currency),
                  caption: l10n.pendingItemsCount(data.pendingDepositsCount),
                ),
                StatTile(
                  icon: Icons.outbox_rounded,
                  label: l10n.pendingOutflows,
                  value: context.money(data.pendingOutflowsCents, currency: group.currency),
                  caption: l10n.pendingItemsCount(data.pendingOutflowsCount),
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            ResponsiveColumns(
              minColumnWidth: 380,
              maxColumns: 2,
              children: [
                _ReconcileForm(groupId: group.id, expectedCents: data.expectedCents, currency: group.currency),
                _History(items: data.reconciliations, currency: group.currency),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReconcileForm extends ConsumerStatefulWidget {
  const _ReconcileForm({required this.groupId, required this.expectedCents, required this.currency});

  final String groupId;
  final int expectedCents;
  final String currency;

  @override
  ConsumerState<_ReconcileForm> createState() => _ReconcileFormState();
}

class _ReconcileFormState extends ConsumerState<_ReconcileForm> {
  final _counted = TextEditingController();
  final _note = TextEditingController();
  String _key = newIdempotencyKey();
  bool _apply = true;
  bool _busy = false;

  @override
  void dispose() {
    _counted.dispose();
    _note.dispose();
    super.dispose();
  }

  int? get _countedCents => Money.parse(_counted.text);

  Future<void> _submit() async {
    final l10n = context.l10n;
    final counted = _countedCents;
    if (counted == null) return;
    final difference = counted - widget.expectedCents;
    if (difference != 0 && _note.text.trim().length < 3) {
      showToast(context, l10n.reconcileNoteNeeded);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(ledgerRepositoryProvider)
          .reconcileCashBox(
            groupId: widget.groupId,
            countedCents: counted,
            idempotencyKey: _key,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            applyAdjustment: _apply,
          );
      ref.read(dataRevisionProvider.notifier).bump();
      _counted.clear();
      _note.clear();
      _key = newIdempotencyKey();
      if (mounted) showToast(context, l10n.reconciliationSaved, icon: Icons.check_rounded);
    } on Object catch (error) {
      if (mounted) showErrorToast(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final finance = FinanceColors.of(context);
    final counted = _countedCents;
    final difference = counted == null ? null : counted - widget.expectedCents;

    return SectionCard(
      title: l10n.reconcileTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.reconcileExplanation, style: theme.textTheme.bodySmall),
          const SizedBox(height: Spacing.md),
          TextField(
            controller: _counted,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: l10n.countedCash),
            onChanged: (_) => setState(() {}),
          ),
          if (difference != null) ...[
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                Expanded(child: Text(l10n.difference)),
                MoneyText(
                  difference,
                  currency: widget.currency,
                  signed: true,
                  style: theme.textTheme.titleMedium?.copyWith(color: difference == 0 ? finance.owed : finance.owes),
                ),
              ],
            ),
            Text(
              difference == 0
                  ? l10n.reconcileMatches
                  : difference > 0
                  ? l10n.reconcileSurplus
                  : l10n.reconcileShortfall,
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _note,
            maxLength: 500,
            decoration: InputDecoration(labelText: l10n.reconcileNote),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.applyAdjustment),
            subtitle: Text(l10n.applyAdjustmentHint),
            value: _apply,
            onChanged: (value) => setState(() => _apply = value),
          ),
          FilledButton(
            onPressed: _busy || counted == null ? null : () => unawaited(_submit()),
            child: Text(l10n.saveReconciliation),
          ),
        ],
      ),
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.items, required this.currency});

  final List<Reconciliation> items;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return SectionCard(
      title: l10n.reconciliationHistory,
      child: items.isEmpty
          ? EmptyState(icon: Icons.history_rounded, title: l10n.noReconciliations)
          : Column(
              children: [
                for (final r in items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      l10n.reconciliationLine(
                        context.money(r.countedCents, currency: currency),
                        context.money(r.expectedCents, currency: currency),
                      ),
                    ),
                    subtitle: Text(
                      [
                        context.dateTime(r.createdAt),
                        if (r.createdByName != null) r.createdByName!,
                        if (r.note != null) r.note!,
                        if (r.adjustmentTransactionId != null) l10n.adjustmentApplied,
                      ].join(' · '),
                    ),
                    trailing: MoneyText(
                      r.differenceCents,
                      currency: currency,
                      signed: true,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
              ],
            ),
    );
  }
}
