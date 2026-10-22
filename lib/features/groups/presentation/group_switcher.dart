import 'dart:async';

import 'package:coffee_tracker/app/routes.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/app_theme.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Shows the current group and lets members of several groups switch.
class GroupSwitcher extends ConsumerWidget {
  const GroupSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final groups = ref.watch(myGroupsProvider).value ?? const [];
    final current = ref.watch(currentGroupProvider).value;
    if (current == null) return const SizedBox.shrink();

    return MenuAnchor(
      menuChildren: [
        for (final group in groups)
          MenuItemButton(
            leadingIcon: Icon(group.id == current.id ? Icons.check_rounded : Icons.groups_outlined),
            onPressed: () => unawaited(ref.read(selectedGroupIdProvider.notifier).select(group.id)),
            child: Text(group.name),
          ),
        const Divider(),
        MenuItemButton(
          leadingIcon: const Icon(Icons.group_add_outlined),
          onPressed: () => context.push(Routes.join),
          child: Text(l10n.joinAnotherGroup),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.add_rounded),
          onPressed: () => context.push(Routes.createGroup),
          child: Text(l10n.createAnotherGroup),
        ),
      ],
      builder: (context, controller, _) => Material(
        color: AppTheme.cardBackground(theme.colorScheme),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.md),
          onTap: () => controller.isOpen ? controller.close() : controller.open(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.groups_rounded, color: theme.colorScheme.secondary),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(current.name, style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis),
                      Text(l10n.membersCount(current.memberCount), style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                Icon(Icons.unfold_more_rounded, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
