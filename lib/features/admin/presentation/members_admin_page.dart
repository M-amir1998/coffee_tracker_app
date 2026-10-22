import 'dart:async';

import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/app_card.dart';
import 'package:coffee_tracker/core/widgets/feedback.dart';
import 'package:coffee_tracker/core/widgets/member_avatar.dart';
import 'package:coffee_tracker/core/widgets/page_layout.dart';
import 'package:coffee_tracker/core/widgets/states.dart';
import 'package:coffee_tracker/features/group_overview/presentation/member_detail_page.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/groups/domain/group_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class MembersAdminPage extends ConsumerWidget {
  const MembersAdminPage({super.key});

  Future<void> _setRole(BuildContext context, WidgetRef ref, String groupId, Member member, MemberRole role) async {
    try {
      await ref.read(groupRepositoryProvider).setMemberRole(groupId, member.userId, role);
      ref.read(dataRevisionProvider.notifier).bump();
      if (context.mounted) showToast(context, context.l10n.roleUpdated(member.displayName));
    } on Object catch (error) {
      if (context.mounted) showErrorToast(context, error);
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, String groupId, Member member) async {
    final l10n = context.l10n;
    final note = await askForNote(
      context,
      title: l10n.removeMemberTitle(member.displayName),
      label: l10n.removeMemberReason,
      confirmLabel: l10n.removeMember,
      required: false,
      destructive: true,
    );
    if (note == null) return;
    try {
      await ref.read(groupRepositoryProvider).removeMember(groupId, member.userId, note: note.isEmpty ? null : note);
      ref.read(dataRevisionProvider.notifier).bump();
      if (context.mounted) showToast(context, l10n.memberRemoved(member.displayName));
    } on Object catch (error) {
      if (context.mounted) showErrorToast(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final groupId = ref.watch(currentGroupIdProvider);
    if (groupId == null) return const SizedBox.shrink();
    final members = ref.watch(membersProvider(groupId));

    return AppPage(
      title: l10n.adminMembers,
      showBackButton: true,
      maxWidth: 900,
      body: AsyncValueView(
        value: members,
        onRetry: () => ref.invalidate(membersProvider(groupId)),
        data: (list) => AppCard(
          padding: const EdgeInsets.symmetric(vertical: Spacing.xs, horizontal: Spacing.sm),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(Spacing.sm),
                child: Text(l10n.rolesExplanation, style: theme.textTheme.bodySmall),
              ),
              for (final member in list)
                ListTile(
                  leading: MemberAvatar(name: member.displayName),
                  title: Text(member.isMe ? l10n.youSuffix(member.displayName) : member.displayName),
                  subtitle: Text(
                    member.isActive
                        ? l10n.memberSince(context.shortDate(member.joinedAt))
                        : l10n.formerMemberSince(context.shortDate(member.leftAt ?? member.joinedAt)),
                  ),
                  trailing: !member.isActive
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DropdownButton<MemberRole>(
                              value: member.role,
                              underline: const SizedBox.shrink(),
                              items: [
                                for (final role in MemberRole.values)
                                  DropdownMenuItem(value: role, child: Text(roleLabel(l10n, role))),
                              ],
                              onChanged: (role) {
                                if (role != null && role != member.role) {
                                  unawaited(_setRole(context, ref, groupId, member, role));
                                }
                              },
                            ),
                            if (!member.isMe)
                              IconButton(
                                tooltip: l10n.removeMember,
                                icon: const Icon(Icons.person_remove_outlined),
                                onPressed: () => unawaited(_remove(context, ref, groupId, member)),
                              ),
                          ],
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
