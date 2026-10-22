import 'dart:async';

import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/app/routes.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/app_card.dart';
import 'package:coffee_tracker/core/widgets/feedback.dart';
import 'package:coffee_tracker/core/widgets/money_text.dart';
import 'package:coffee_tracker/core/widgets/page_layout.dart';
import 'package:coffee_tracker/core/widgets/states.dart';
import 'package:coffee_tracker/features/accounting/application/report_providers.dart';
import 'package:coffee_tracker/features/accounting/domain/balance_models.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/groups/domain/group_models.dart';
import 'package:coffee_tracker/features/transactions/presentation/forms/form_scaffold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

class CyclesPage extends ConsumerWidget {
  const CyclesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final group = ref.watch(currentGroupProvider).value;
    if (group == null) return const SizedBox.shrink();
    final cycles = ref.watch(cyclesProvider(group.id));
    final theme = Theme.of(context);

    return AppPage(
      title: l10n.navCycles,
      subtitle: l10n.cyclesSubtitle,
      maxWidth: 900,
      onRefresh: () async => ref.invalidate(cyclesProvider(group.id)),
      body: AsyncValueView(
        value: cycles,
        onRetry: () => ref.invalidate(cyclesProvider(group.id)),
        data: (items) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final cycle in items) ...[
              AppCard(
                onTap: () => context.push(Routes.cycle(cycle.id)),
                child: Row(
                  children: [
                    Icon(
                      cycle.isOpen ? Icons.play_circle_rounded : Icons.lock_rounded,
                      color: cycle.isOpen ? theme.colorScheme.tertiary : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(cycle.name, style: theme.textTheme.titleMedium),
                          Text(
                            cycle.isOpen
                                ? l10n.cycleOpenSince(context.shortDate(cycle.openedAt))
                                : l10n.cycleClosedRange(context.shortDate(cycle.openedAt), context.shortDate(cycle.closedAt!)),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(l10n.coffeesCount(cycle.coffees), style: theme.textTheme.titleSmall),
                        MoneyText(cycle.consumptionCents, currency: group.currency, style: theme.textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(width: Spacing.xs),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
              if (cycle.isOpen && group.role.isAdmin) ...[
                const SizedBox(height: Spacing.sm),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton.tonalIcon(
                    onPressed: () => unawaited(
                      showAdaptiveSheet<void>(
                        context,
                        builder: (_) => CloseCycleWizard(group: group, cycleId: cycle.id, cycleName: cycle.name),
                      ),
                    ),
                    icon: const Icon(Icons.lock_clock_rounded),
                    label: Text(l10n.closeCycle),
                  ),
                ),
              ],
              const SizedBox(height: Spacing.sm),
            ],
          ],
        ),
      ),
    );
  }
}

/// Closing a cycle: shows exactly what will be carried forward, then asks for
/// the next cycle's name and a typed confirmation.
class CloseCycleWizard extends ConsumerStatefulWidget {
  const CloseCycleWizard({required this.group, required this.cycleId, required this.cycleName, super.key});

  final GroupSummary group;
  final String cycleId;
  final String cycleName;

  @override
  ConsumerState<CloseCycleWizard> createState() => _CloseCycleWizardState();
}

class _CloseCycleWizardState extends ConsumerState<CloseCycleWizard> with SubmitOnce {
  final _formKey = GlobalKey<FormState>();
  final _next = TextEditingController();
  final _note = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_next.text.isEmpty) {
      final now = DateTime.now();
      final nextMonth = DateTime(now.year, now.month + (now.day > 15 ? 1 : 0));
      _next.text = toBeginningOfSentenceCase(DateFormat.yMMMM(context.localeTag).format(nextMonth));
      if (_next.text == widget.cycleName) _next.text = '${widget.cycleName} (2)';
    }
  }

  @override
  void dispose() {
    _next.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = context.l10n;
    final confirmed = await confirmByTyping(
      context,
      title: l10n.closeCycleConfirmTitle,
      message: l10n.closeCycleConfirmMessage(widget.cycleName, _next.text.trim()),
      expected: widget.cycleName,
      confirmLabel: l10n.closeCycle,
    );
    if (!confirmed || !mounted) return;
    submitFrom(() async {
      await ref
          .read(ledgerRepositoryProvider)
          .closeCycle(
            groupId: widget.group.id,
            cycleId: widget.cycleId,
            confirmation: widget.cycleName,
            nextCycleName: _next.text.trim(),
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      if (!mounted) return;
      ref.read(dataRevisionProvider.notifier).bump();
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text(l10n.cycleClosedToast(widget.cycleName))));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final report = ref.watch(cycleReportProvider(widget.cycleId));
    return FormScaffold(
      formKey: _formKey,
      icon: Icons.lock_clock_rounded,
      title: l10n.closeCycleTitle(widget.cycleName),
      info: l10n.closeCycleInfo,
      busy: busy,
      error: error,
      submitLabel: l10n.closeCycleContinue,
      onSubmit: () => unawaited(_close()),
      children: [
        AsyncValueView(
          value: report,
          data: (data) => _ClosingPreview(report: data, currency: widget.group.currency),
        ),
        const SizedBox(height: Spacing.md),
        TextFormField(
          controller: _next,
          maxLength: 60,
          decoration: InputDecoration(labelText: l10n.fieldNextCycleName),
          validator: (value) {
            final text = value?.trim() ?? '';
            if (text.isEmpty) return l10n.validationNameRequired;
            if (text == widget.cycleName) return l10n.validationNextCycleName;
            return null;
          },
        ),
        TextFormField(
          controller: _note,
          maxLength: 500,
          decoration: InputDecoration(labelText: l10n.fieldNoteOptional),
        ),
        Text(l10n.closeCycleIrreversible, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
      ],
    );
  }
}

class _ClosingPreview extends StatelessWidget {
  const _ClosingPreview({required this.report, required this.currency});

  final CycleReport report;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final carried = report.carriedForward.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.closingCash(context.money(report.cash.closingCashCents, currency: currency)),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: Spacing.xs),
        if (carried.isEmpty)
          Text(l10n.closingEveryoneSettled)
        else ...[
          Text(l10n.closingCarriedForward(carried.length)),
          for (final row in carried)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(child: Text(row.displayName)),
                  MoneyText(row.breakdown.netCents, currency: currency, colorBySign: true),
                ],
              ),
            ),
        ],
        if ((report.pending?.count ?? 0) > 0) ...[
          const SizedBox(height: Spacing.xs),
          Text(l10n.closingPendingMoved(report.pending!.count), style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}
