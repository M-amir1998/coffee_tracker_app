import 'dart:async';

import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/app_card.dart';
import 'package:coffee_tracker/core/widgets/page_layout.dart';
import 'package:coffee_tracker/core/widgets/states.dart';
import 'package:coffee_tracker/features/accounting/domain/balance_models.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class AuditLogPage extends ConsumerStatefulWidget {
  const AuditLogPage({super.key});

  @override
  ConsumerState<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends ConsumerState<AuditLogPage> {
  final _entries = <AuditEntry>[];
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  Future<void> _load() async {
    final groupId = ref.read(currentGroupIdProvider);
    if (groupId == null || _loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(reportsRepositoryProvider)
          .auditLog(groupId, beforeId: _entries.isEmpty ? null : _entries.last.id);
      if (!mounted) return;
      setState(() {
        _entries.addAll(page);
        _hasMore = page.length == 50;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _actionLabel(AppLocalizations l10n, String action) => switch (action) {
    'group_created' => l10n.auditGroupCreated,
    'group_settings_updated' => l10n.auditSettingsUpdated,
    'invitation_created' => l10n.auditInvitationCreated,
    'invitation_revoked' => l10n.auditInvitationRevoked,
    'member_joined' => l10n.auditMemberJoined,
    'member_left' => l10n.auditMemberLeft,
    'member_removed' => l10n.auditMemberRemoved,
    'role_changed' => l10n.auditRoleChanged,
    'price_changed' => l10n.auditPriceChanged,
    'price_cancelled' => l10n.auditPriceCancelled,
    'cycle_closed' => l10n.auditCycleClosed,
    'cash_reconciled' => l10n.auditCashReconciled,
    'balance_adjusted' => l10n.auditBalanceAdjusted,
    'transaction_reversed' => l10n.auditTransactionReversed,
    'dispute_resolved' => l10n.auditDisputeResolved,
    'transfer_admin_override' => l10n.auditTransferOverride,
    'transfer_decided_by_admin' => l10n.auditTransferDecided,
    'account_deleted' => l10n.auditAccountDeleted,
    _ => action,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return AppPage(
      title: l10n.adminAudit,
      showBackButton: true,
      maxWidth: 900,
      body: AppCard(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xs, horizontal: Spacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(Spacing.sm),
              child: Text(l10n.auditExplanation, style: theme.textTheme.bodySmall),
            ),
            if (_entries.isEmpty && !_loading && _error == null)
              EmptyState(icon: Icons.history_rounded, title: l10n.auditEmpty),
            for (final entry in _entries)
              ListTile(
                leading: const Icon(Icons.history_edu_rounded),
                title: Text(_actionLabel(l10n, entry.action)),
                subtitle: Text(
                  [
                    context.dateTime(entry.createdAt),
                    if (entry.actorName != null) entry.actorName!,
                    if (entry.details.isNotEmpty)
                      entry.details.entries
                          .where((e) => e.value != null && e.value is! Map)
                          .map((e) => '${e.key}: ${e.value}')
                          .join(', '),
                  ].join(' · '),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (_error != null) ErrorState(error: _error!, onRetry: () => unawaited(_load()), compact: true),
            if (_hasMore)
              Padding(
                padding: const EdgeInsets.all(Spacing.sm),
                child: Center(
                  child: _loading
                      ? const CircularProgressIndicator()
                      : OutlinedButton(onPressed: () => unawaited(_load()), child: Text(l10n.loadMore)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
