import 'dart:async';

import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/money/money.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/app_card.dart';
import 'package:coffee_tracker/core/widgets/member_avatar.dart';
import 'package:coffee_tracker/core/widgets/money_text.dart';
import 'package:coffee_tracker/core/widgets/page_layout.dart';
import 'package:coffee_tracker/core/widgets/states.dart';
import 'package:coffee_tracker/features/accounting/application/report_providers.dart';
import 'package:coffee_tracker/features/auth/application/auth_providers.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/groups/domain/group_models.dart';
import 'package:coffee_tracker/features/settlements/domain/settlement_planner.dart';
import 'package:coffee_tracker/features/transactions/presentation/forms/transaction_forms.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class SettleUpPage extends ConsumerStatefulWidget {
  const SettleUpPage({super.key});

  @override
  ConsumerState<SettleUpPage> createState() => _SettleUpPageState();
}

class _SettleUpPageState extends ConsumerState<SettleUpPage> {
  bool _useCashBox = true;
  final _reserve = TextEditingController();

  @override
  void dispose() {
    _reserve.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final group = ref.watch(currentGroupProvider).value;
    if (group == null) return const SizedBox.shrink();
    final inputs = ref.watch(settlementInputsProvider(group.id));
    final reserveCents = Money.parse(_reserve.text) ?? 0;

    return AppPage(
      title: l10n.navSettleUp,
      subtitle: l10n.settleSubtitle,
      maxWidth: 960,
      onRefresh: () async => ref.invalidate(settlementInputsProvider(group.id)),
      body: AsyncValueView(
        value: inputs,
        onRetry: () => ref.invalidate(settlementInputsProvider(group.id)),
        data: (data) {
          final plan = planSettlements(data, reserveCents: reserveCents, useCashBox: _useCashBox);
          return ResponsiveColumns(
            minColumnWidth: 400,
            maxColumns: 2,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PlanList(plan: plan, group: group),
                  if (plan.unsettledCredits.isNotEmpty) ...[
                    const SizedBox(height: Spacing.md),
                    SectionCard(
                      title: l10n.settleUnsettledTitle,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(l10n.settleUnsettledExplanation, style: Theme.of(context).textTheme.bodySmall),
                          for (final credit in plan.unsettledCredits)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: MemberAvatar(name: credit.displayName),
                              title: Text(credit.displayName),
                              trailing: MoneyText(credit.amountCents, currency: group.currency),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionCard(
                    title: l10n.settleOptionsTitle,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.settleCashAvailable(
                            context.money(data.cashBoxCents, currency: group.currency),
                            context.money(plan.availableCashCents, currency: group.currency),
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.settleUseCashBox),
                          subtitle: Text(l10n.settleUseCashBoxHint),
                          value: _useCashBox,
                          onChanged: (value) => setState(() => _useCashBox = value),
                        ),
                        TextField(
                          controller: _reserve,
                          enabled: _useCashBox,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: l10n.settleReserve,
                            helperText: l10n.settleReserveHint,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                  AppCard(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded),
                        const SizedBox(width: Spacing.sm),
                        Expanded(
                          child: Text(
                            [
                              l10n.settleDisclaimer,
                              if (plan.consideredPendingItems) l10n.settlePendingConsidered,
                            ].join(' '),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (plan.inactiveWithBalance.isNotEmpty) ...[
                    const SizedBox(height: Spacing.md),
                    SectionCard(
                      title: l10n.settleInactiveTitle,
                      child: Column(
                        children: [
                          for (final member in plan.inactiveWithBalance)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(member.displayName),
                              subtitle: Text(l10n.settleInactiveHint),
                              trailing: MoneyText(member.netCents, currency: group.currency, colorBySign: true),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PlanList extends ConsumerWidget {
  const _PlanList({required this.plan, required this.group});

  final SettlementPlan plan;
  final GroupSummary group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final myId = ref.watch(currentUserIdProvider);
    if (plan.isSettled) {
      return AppCard(
        child: EmptyState(
          icon: Icons.celebration_rounded,
          title: l10n.settleAllDoneTitle,
          message: l10n.settleAllDoneMessage,
        ),
      );
    }
    String money(int cents) => context.money(cents, currency: group.currency);

    return SectionCard(
      title: l10n.settleSuggestionsTitle(plan.suggestions.length),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, s) in plan.suggestions.indexed) ...[
            if (index > 0) const Divider(height: Spacing.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(radius: 14, child: Text('${index + 1}', style: theme.textTheme.labelMedium)),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(switch (s.type) {
                        SuggestionType.reimbursement => l10n.suggestReimbursement(s.toName!, money(s.amountCents)),
                        SuggestionType.transfer => l10n.suggestTransfer(s.fromName!, s.toName!, money(s.amountCents)),
                        SuggestionType.deposit => l10n.suggestDeposit(s.fromName!, money(s.amountCents)),
                      }, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(switch (s.type) {
                        SuggestionType.reimbursement => l10n.explainReimbursement(
                          s.toName!,
                          money(s.toOutstandingCents),
                          money(s.cashBeforeCents),
                        ),
                        SuggestionType.transfer => l10n.explainTransfer(
                          s.fromName!,
                          money(s.fromOutstandingCents),
                          s.toName!,
                          money(s.toOutstandingCents),
                        ),
                        SuggestionType.deposit => l10n.explainDeposit(s.fromName!, money(s.fromOutstandingCents)),
                      }, style: theme.textTheme.bodySmall),
                      const SizedBox(height: Spacing.xs),
                      if (_canRecord(s, myId, group.role))
                        TextButton.icon(
                          onPressed: () => unawaited(_record(context, s)),
                          icon: const Icon(Icons.edit_note_rounded),
                          label: Text(l10n.recordThisStep),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  bool _canRecord(SettlementSuggestion s, String? myId, MemberRole role) => switch (s.type) {
    SuggestionType.reimbursement => role.managesCash || s.toUserId == myId,
    SuggestionType.transfer => s.fromUserId == myId || s.toUserId == myId || role.isAdmin,
    SuggestionType.deposit => s.fromUserId == myId || role.managesCash,
  };

  Future<void> _record(BuildContext context, SettlementSuggestion s) => switch (s.type) {
    SuggestionType.reimbursement => showReimbursementForm(
      context,
      groupId: group.id,
      memberId: s.toUserId,
      suggestedCents: s.amountCents,
    ),
    SuggestionType.transfer => showTransferForm(
      context,
      groupId: group.id,
      fromMemberId: s.fromUserId,
      toMemberId: s.toUserId,
      suggestedCents: s.amountCents,
    ),
    SuggestionType.deposit => showDepositForm(
      context,
      groupId: group.id,
      suggestedCents: s.amountCents,
      forMemberId: group.role.managesCash && s.fromUserId != null ? s.fromUserId : null,
    ),
  };
}
