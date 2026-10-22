import 'dart:async';

import 'package:coffee_tracker/app/core_providers.dart';
import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/app/routes.dart';
import 'package:coffee_tracker/core/config/app_config.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/app_card.dart';
import 'package:coffee_tracker/core/widgets/feedback.dart';
import 'package:coffee_tracker/core/widgets/page_layout.dart';
import 'package:coffee_tracker/core/widgets/states.dart';
import 'package:coffee_tracker/features/group_overview/presentation/member_detail_page.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/groups/domain/group_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Link that opens the join screen with the code filled in, or null when the
/// public web address is unknown (native builds without PUBLIC_APP_URL).
String? invitationLink(AppConfig config, String code) {
  final origin = config.publicAppUrl.isNotEmpty ? config.publicAppUrl : (kIsWeb ? Uri.base.origin : null);
  return origin == null ? null : '${origin.replaceAll(RegExp(r'/+$'), '')}${Routes.joinWithCode(code)}';
}

class InvitationsPage extends ConsumerStatefulWidget {
  const InvitationsPage({super.key});

  @override
  ConsumerState<InvitationsPage> createState() => _InvitationsPageState();
}

class _InvitationsPageState extends ConsumerState<InvitationsPage> {
  MemberRole _role = MemberRole.member;
  int? _maxUses;
  int _days = 14;
  bool _busy = false;

  Future<void> _create(String groupId) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(groupRepositoryProvider)
          .createInvitation(groupId, role: _role, maxUses: _maxUses, expiresInDays: _days);
      ref.invalidate(invitationsProvider(groupId));
    } on Object catch (error) {
      if (mounted) showErrorToast(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showToast(context, context.l10n.copied, icon: Icons.content_copy_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final groupId = ref.watch(currentGroupIdProvider);
    if (groupId == null) return const SizedBox.shrink();
    final invitations = ref.watch(invitationsProvider(groupId));
    final config = ref.watch(appConfigProvider);
    final now = DateTime.now();

    return AppPage(
      title: l10n.adminInvitations,
      showBackButton: true,
      maxWidth: 900,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: l10n.newInvitation,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: Spacing.md,
                  runSpacing: Spacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SegmentedButton<MemberRole>(
                      segments: [
                        ButtonSegment(value: MemberRole.member, label: Text(l10n.roleMember)),
                        ButtonSegment(value: MemberRole.treasurer, label: Text(l10n.roleTreasurer)),
                      ],
                      selected: {_role},
                      onSelectionChanged: (value) => setState(() => _role = value.first),
                    ),
                    DropdownButton<int?>(
                      value: _maxUses,
                      items: [
                        DropdownMenuItem(child: Text(l10n.unlimitedUses)),
                        for (final uses in [1, 5, 10, 25, 50]) DropdownMenuItem(value: uses, child: Text(l10n.maxUses(uses))),
                      ],
                      onChanged: (value) => setState(() => _maxUses = value),
                    ),
                    DropdownButton<int>(
                      value: _days,
                      items: [
                        for (final days in [1, 7, 14, 30, 90]) DropdownMenuItem(value: days, child: Text(l10n.validDays(days))),
                      ],
                      onChanged: (value) => setState(() => _days = value ?? 14),
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.md),
                FilledButton.icon(
                  onPressed: _busy ? null : () => unawaited(_create(groupId)),
                  icon: const Icon(Icons.add_link_rounded),
                  label: Text(l10n.createInvitation),
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.md),
          AsyncValueView(
            value: invitations,
            onRetry: () => ref.invalidate(invitationsProvider(groupId)),
            data: (list) => list.isEmpty
                ? EmptyState(icon: Icons.qr_code_2_rounded, title: l10n.noInvitations)
                : Column(
                    children: [
                      for (final invitation in list)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Spacing.sm),
                          child: AppCard(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SelectableText(
                                        invitation.displayCode,
                                        style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 3, fontFamily: 'Inter'),
                                      ),
                                      Text(
                                        [
                                          roleLabel(l10n, invitation.role),
                                          l10n.usesCount(invitation.useCount, invitation.maxUses ?? 0),
                                          if (invitation.revokedAt != null)
                                            l10n.invitationRevoked
                                          else if (invitation.expiresAt != null)
                                            l10n.validUntil(context.shortDate(invitation.expiresAt!)),
                                        ].join(' · '),
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                if (invitation.isActiveAt(now)) ...[
                                  IconButton(
                                    tooltip: l10n.copyCode,
                                    icon: const Icon(Icons.content_copy_rounded),
                                    onPressed: () => unawaited(_copy(invitation.code)),
                                  ),
                                  if (invitationLink(config, invitation.code) case final link?)
                                    IconButton(
                                      tooltip: l10n.copyLink,
                                      icon: const Icon(Icons.link_rounded),
                                      onPressed: () => unawaited(_copy(link)),
                                    ),
                                  IconButton(
                                    tooltip: l10n.revoke,
                                    icon: const Icon(Icons.block_rounded),
                                    onPressed: () async {
                                      final ok = await confirmAction(
                                        context,
                                        title: l10n.revokeInvitationTitle,
                                        message: l10n.revokeInvitationMessage,
                                        confirmLabel: l10n.revoke,
                                        destructive: true,
                                      );
                                      if (!ok) return;
                                      try {
                                        await ref.read(groupRepositoryProvider).revokeInvitation(invitation.id);
                                        ref.invalidate(invitationsProvider(groupId));
                                      } on Object catch (error) {
                                        if (context.mounted) showErrorToast(context, error);
                                      }
                                    },
                                  ),
                                ],
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
