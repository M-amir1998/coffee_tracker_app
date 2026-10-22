import 'dart:async';

import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/app/routes.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/finance_colors.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/app_card.dart';
import 'package:coffee_tracker/core/widgets/feedback.dart';
import 'package:coffee_tracker/core/widgets/page_layout.dart';
import 'package:coffee_tracker/core/widgets/states.dart';
import 'package:coffee_tracker/features/accounting/application/report_providers.dart';
import 'package:coffee_tracker/features/accounting/domain/balance_models.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/transactions/presentation/activity_tile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class AdminPage extends ConsumerWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final group = ref.watch(currentGroupProvider).value;
    if (group == null) return const SizedBox.shrink();
    final role = group.role;
    if (!role.managesCash) {
      return AppPage(
        title: l10n.navAdmin,
        body: EmptyState(icon: Icons.lock_outline_rounded, title: l10n.adminOnlyTitle, message: l10n.adminOnlyMessage),
      );
    }
    final pending = ref.watch(pendingActionsProvider(group.id));

    final tools = [
      if (role.isAdmin) (Icons.manage_accounts_rounded, l10n.adminMembers, l10n.adminMembersHint, 'members'),
      if (role.isAdmin) (Icons.qr_code_rounded, l10n.adminInvitations, l10n.adminInvitationsHint, 'invitations'),
      if (role.isAdmin) (Icons.sell_rounded, l10n.adminPrice, l10n.adminPriceHint, 'price'),
      (Icons.inventory_2_rounded, l10n.adminCashBox, l10n.adminCashBoxHint, 'cash-box'),
      (Icons.download_rounded, l10n.adminExports, l10n.adminExportsHint, 'exports'),
      if (role.isAdmin) (Icons.history_rounded, l10n.adminAudit, l10n.adminAuditHint, 'audit'),
      if (role.isAdmin) (Icons.tune_rounded, l10n.adminSettings, l10n.adminSettingsHint, 'settings'),
    ];

    return AppPage(
      title: l10n.navAdmin,
      subtitle: group.name,
      onRefresh: () async => ref.read(dataRevisionProvider.notifier).bump(),
      body: ResponsiveColumns(
        minColumnWidth: 420,
        maxColumns: 2,
        children: [
          SectionCard(
            title: l10n.approvalsTitle,
            child: AsyncValueView(
              value: pending,
              data: (data) => data.toReview.isEmpty
                  ? EmptyState(icon: Icons.task_alt_rounded, title: l10n.approvalsEmpty)
                  : Column(children: [for (final item in data.toReview) ActivityTile(item: item)]),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                child: Column(
                  children: [
                    for (final (icon, title, subtitle, section) in tools)
                      ListTile(
                        leading: Icon(icon),
                        title: Text(title),
                        subtitle: Text(subtitle),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push(Routes.adminSection(section)),
                      ),
                    ListTile(
                      leading: const Icon(Icons.event_repeat_rounded),
                      title: Text(l10n.navCycles),
                      subtitle: Text(l10n.adminCyclesHint),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.go(Routes.cycles),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.md),
              _IntegrityCard(groupId: group.id),
            ],
          ),
        ],
      ),
    );
  }
}

class _IntegrityCard extends ConsumerStatefulWidget {
  const _IntegrityCard({required this.groupId});

  final String groupId;

  @override
  ConsumerState<_IntegrityCard> createState() => _IntegrityCardState();
}

class _IntegrityCardState extends ConsumerState<_IntegrityCard> {
  LedgerIntegrity? _result;
  bool _busy = false;

  Future<void> _check() async {
    setState(() => _busy = true);
    try {
      final result = await ref.read(reportsRepositoryProvider).verifyIntegrity(widget.groupId);
      if (mounted) setState(() => _result = result);
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
    final result = _result;
    return SectionCard(
      title: l10n.integrityTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.integrityExplanation, style: theme.textTheme.bodySmall),
          const SizedBox(height: Spacing.sm),
          if (result != null) ...[
            Row(
              children: [
                Icon(
                  result.ok ? Icons.verified_rounded : Icons.report_rounded,
                  color: result.ok ? finance.owed : finance.owes,
                ),
                const SizedBox(width: Spacing.xs),
                Expanded(
                  child: Text(result.ok ? l10n.integrityOk : l10n.integrityProblems, style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            for (final check in result.checks)
              Row(
                children: [
                  Icon(check.ok ? Icons.check_rounded : Icons.close_rounded, size: 18),
                  const SizedBox(width: Spacing.xs),
                  Expanded(child: Text(check.key, style: theme.textTheme.bodySmall)),
                  if (!check.ok) Text('${check.value}', style: theme.textTheme.bodySmall),
                ],
              ),
            const SizedBox(height: Spacing.sm),
          ],
          OutlinedButton.icon(
            onPressed: _busy ? null : () => unawaited(_check()),
            icon: _busy
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.fact_check_rounded),
            label: Text(l10n.integrityRun),
          ),
        ],
      ),
    );
  }
}
