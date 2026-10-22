import 'dart:async';

import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/core/data/rpc.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/money/money.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/app_card.dart';
import 'package:coffee_tracker/core/widgets/feedback.dart';
import 'package:coffee_tracker/core/widgets/member_avatar.dart';
import 'package:coffee_tracker/core/widgets/money_text.dart';
import 'package:coffee_tracker/core/widgets/page_layout.dart';
import 'package:coffee_tracker/core/widgets/states.dart';
import 'package:coffee_tracker/core/widgets/status_chip.dart';
import 'package:coffee_tracker/features/accounting/application/report_providers.dart';
import 'package:coffee_tracker/features/accounting/data/reports_repository.dart';
import 'package:coffee_tracker/features/accounting/domain/balance_models.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/groups/domain/group_models.dart';
import 'package:coffee_tracker/features/transactions/presentation/activity_tile.dart';
import 'package:coffee_tracker/features/transactions/presentation/forms/amount_field.dart';
import 'package:coffee_tracker/features/transactions/presentation/forms/form_scaffold.dart';
import 'package:coffee_tracker/features/transactions/presentation/forms/transaction_forms.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class MemberDetailPage extends ConsumerWidget {
  const MemberDetailPage({required this.userId, super.key});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final group = ref.watch(currentGroupProvider).value;
    if (group == null) return const SizedBox.shrink();
    final cycle = ref.watch(memberBalancesProvider((groupId: group.id, cycleId: null, allTime: false)));
    final allTime = ref.watch(memberBalancesProvider((groupId: group.id, cycleId: null, allTime: true)));
    final activity = ref.watch(activityFeedProvider((groupId: group.id, filter: ActivityFilter(memberId: userId))));

    MemberBalance? find(List<MemberBalance>? rows) => rows?.where((r) => r.userId == userId).firstOrNull;
    final current = find(cycle.value);
    final total = find(allTime.value);

    return AppPage(
      title: current?.displayName ?? total?.displayName ?? l10n.memberTitle,
      showBackButton: true,
      body: AsyncValueView(
        value: cycle,
        onRetry: () => ref.read(dataRevisionProvider.notifier).bump(),
        data: (_) {
          final member = current ?? total;
          if (member == null) return EmptyState(icon: Icons.person_off_rounded, title: l10n.memberNotFound);
          return ResponsiveColumns(
            minColumnWidth: 420,
            maxColumns: 2,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(member: member, currency: group.currency, role: group.role),
                  const SizedBox(height: Spacing.md),
                  _BreakdownCard(cycle: current?.breakdown, allTime: total?.breakdown, currency: group.currency),
                ],
              ),
              SectionCard(
                title: l10n.memberActivityTitle,
                child: AsyncValueView(
                  value: activity,
                  data: (page) => page.items.isEmpty
                      ? EmptyState(icon: Icons.receipt_long_outlined, title: l10n.activityEmptyTitle)
                      : Column(
                          children: [for (final item in page.items.take(15)) ActivityTile(item: item, dense: true)],
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.member, required this.currency, required this.role});

  final MemberBalance member;
  final String currency;

  /// The viewer's role.
  final MemberRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final net = member.breakdown.netCents;
    final groupId = ref.watch(currentGroupIdProvider)!;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MemberAvatar(name: member.displayName, radius: 28),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(member.displayName, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: Spacing.xs,
                      children: [
                        RolePill(label: roleLabel(l10n, member.role)),
                        BalanceStatusChip(member.status),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.lg),
          Text(l10n.netBalanceLabel, style: theme.textTheme.labelLarge),
          MoneyText(
            net,
            currency: currency,
            colorBySign: true,
            style: theme.textTheme.displaySmall?.copyWith(fontFamily: 'Inter'),
          ),
          Text(switch (member.status) {
            BalanceStatus.owes => l10n.memberOwesExplanation(member.displayName),
            BalanceStatus.owed => l10n.memberOwedExplanation(member.displayName),
            BalanceStatus.settled => l10n.memberSettledExplanation(member.displayName),
          }, style: theme.textTheme.bodySmall),
          const SizedBox(height: Spacing.md),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              if (!member.isMe && net < 0)
                OutlinedButton.icon(
                  onPressed: () => unawaited(
                    showTransferForm(context, groupId: groupId, toMemberId: member.userId, suggestedCents: -net),
                  ),
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: Text(l10n.payMember(member.displayName)),
                ),
              if (role.managesCash && net < 0)
                OutlinedButton.icon(
                  onPressed: () => unawaited(
                    showReimbursementForm(context, groupId: groupId, memberId: member.userId, suggestedCents: -net),
                  ),
                  icon: const Icon(Icons.payments_rounded),
                  label: Text(l10n.reimburseMember),
                ),
              if (role.managesCash && net > 0 && !member.isMe)
                OutlinedButton.icon(
                  onPressed: () => unawaited(
                    showDepositForm(context, groupId: groupId, forMemberId: member.userId, suggestedCents: net),
                  ),
                  icon: const Icon(Icons.savings_rounded),
                  label: Text(l10n.recordCashFromMember),
                ),
              if (role.isAdmin)
                OutlinedButton.icon(
                  onPressed: () => unawaited(
                    showAdaptiveSheet<void>(
                      context,
                      builder: (_) => AdjustmentForm(groupId: groupId, member: member),
                    ),
                  ),
                  icon: const Icon(Icons.tune_rounded),
                  label: Text(l10n.adjustBalance),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String roleLabel(AppLocalizations l10n, MemberRole role) => switch (role) {
  MemberRole.member => l10n.roleMember,
  MemberRole.treasurer => l10n.roleTreasurer,
  MemberRole.admin => l10n.roleAdmin,
};

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.cycle, required this.allTime, required this.currency});

  final BalanceBreakdown? cycle;
  final BalanceBreakdown? allTime;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final rows = <(String, int Function(BalanceBreakdown), bool)>[
      (l10n.breakdownOpening, (b) => b.openingCents, true),
      (l10n.breakdownCoffees, (b) => b.coffees, false),
      (l10n.breakdownConsumption, (b) => b.consumptionCents, true),
      (l10n.breakdownDeposits, (b) => -b.depositsCents, true),
      (l10n.breakdownPurchases, (b) => -b.personalPurchasesCents, true),
      (l10n.breakdownSent, (b) => -b.transfersSentCents, true),
      (l10n.breakdownReceived, (b) => b.transfersReceivedCents, true),
      (l10n.breakdownReimbursed, (b) => b.reimbursementsCents, true),
      (l10n.breakdownAdjustments, (b) => b.adjustmentsCents, true),
    ];
    String cell(BalanceBreakdown? b, int Function(BalanceBreakdown) read, bool money) {
      if (b == null) return '—';
      final value = read(b);
      return money ? context.money(value, currency: currency, signed: true) : context.number(value);
    }

    return SectionCard(
      title: l10n.breakdownTitle,
      child: Column(
        children: [
          Text(l10n.breakdownExplanation, style: theme.textTheme.bodySmall),
          const SizedBox(height: Spacing.sm),
          Table(
            columnWidths: const {0: FlexColumnWidth(2), 1: IntrinsicColumnWidth(), 2: IntrinsicColumnWidth()},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                children: [const SizedBox.shrink(), _HeaderCell(l10n.scopeCycle), _HeaderCell(l10n.scopeAllTime)],
              ),
              for (final (label, read, money) in rows)
                TableRow(
                  children: [
                    Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(label)),
                    _ValueCell(cell(cycle, read, money)),
                    _ValueCell(cell(allTime, read, money)),
                  ],
                ),
              TableRow(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(l10n.breakdownNet, style: theme.textTheme.titleSmall),
                  ),
                  _ValueCell(cell(cycle, (b) => b.netCents, true), bold: true),
                  _ValueCell(cell(allTime, (b) => b.netCents, true), bold: true),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: Spacing.md, bottom: 4),
    child: Text(text, textAlign: TextAlign.end, style: Theme.of(context).textTheme.labelMedium),
  );
}

class _ValueCell extends StatelessWidget {
  const _ValueCell(this.text, {this.bold = false});

  final String text;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: Spacing.md),
    child: Text(
      text,
      textAlign: TextAlign.end,
      style:
          (bold ? Theme.of(context).textTheme.titleSmall : null)?.copyWith(fontFeatures: tabularFigures) ??
          const TextStyle(fontFeatures: tabularFigures),
    ),
  );
}

/// Administrative balance correction (charge or credit) with a mandatory reason.
class AdjustmentForm extends ConsumerStatefulWidget {
  const AdjustmentForm({required this.groupId, required this.member, super.key});

  final String groupId;
  final MemberBalance member;

  @override
  ConsumerState<AdjustmentForm> createState() => _AdjustmentFormState();
}

class _AdjustmentFormState extends ConsumerState<AdjustmentForm> with SubmitOnce {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _key = newIdempotencyKey();
  int _direction = -1;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = context.l10n;
    submitFrom(() async {
      await ref
          .read(ledgerRepositoryProvider)
          .adjustBalance(
            groupId: widget.groupId,
            memberId: widget.member.userId,
            direction: _direction,
            amountCents: Money.parse(_amount.text)!,
            note: _note.text.trim(),
            idempotencyKey: _key,
          );
      if (!mounted) return;
      ref.read(dataRevisionProvider.notifier).bump();
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text(l10n.adjustmentRecorded)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FormScaffold(
      formKey: _formKey,
      icon: Icons.tune_rounded,
      title: l10n.adjustBalanceTitle(widget.member.displayName),
      info: l10n.adjustBalanceInfo,
      busy: busy,
      error: error,
      submitLabel: l10n.adjustBalanceSubmit,
      onSubmit: _submit,
      children: [
        SegmentedButton<int>(
          segments: [
            ButtonSegment(value: -1, label: Text(l10n.adjustCredit), icon: const Icon(Icons.remove_circle_outline)),
            ButtonSegment(value: 1, label: Text(l10n.adjustCharge), icon: const Icon(Icons.add_circle_outline)),
          ],
          selected: {_direction},
          onSelectionChanged: (value) => setState(() => _direction = value.first),
        ),
        const SizedBox(height: Spacing.md),
        AmountField(controller: _amount, label: l10n.fieldAmount),
        const SizedBox(height: Spacing.md),
        TextFormField(
          controller: _note,
          maxLength: 500,
          decoration: InputDecoration(labelText: l10n.fieldReasonRequired),
          validator: (value) => (value?.trim().length ?? 0) < 3 ? l10n.validationNoteRequired : null,
        ),
      ],
    );
  }
}
