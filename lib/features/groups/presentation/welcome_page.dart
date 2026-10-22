import 'dart:async';

import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/app/routes.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/app_card.dart';
import 'package:coffee_tracker/features/profile/application/profile_providers.dart';
import 'package:coffee_tracker/features/shell/presentation/app_logo.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// First screen for accounts that do not belong to a group yet.
class WelcomePage extends ConsumerWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final name = ref.watch(myProfileProvider).value?.displayName;
    final wide = WindowSize.of(context).isAtLeastMedium;

    final choices = [
      _Choice(
        icon: Icons.group_add_rounded,
        title: l10n.welcomeJoinTitle,
        body: l10n.welcomeJoinBody,
        action: l10n.welcomeJoinAction,
        onTap: () => context.push(Routes.join),
        primary: true,
      ),
      _Choice(
        icon: Icons.add_business_rounded,
        title: l10n.welcomeCreateTitle,
        body: l10n.welcomeCreateBody,
        action: l10n.welcomeCreateAction,
        onTap: () => context.push(Routes.createGroup),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppLogo(size: 64),
                  const SizedBox(height: Spacing.lg),
                  Semantics(
                    header: true,
                    child: Text(
                      name == null ? l10n.welcomeTitleGeneric : l10n.welcomeTitle(name),
                      style: theme.textTheme.displaySmall,
                    ),
                  ),
                  const SizedBox(height: Spacing.sm),
                  Text(
                    l10n.welcomeSubtitle,
                    style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: Spacing.xl),
                  if (wide)
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: choices[0]),
                          const SizedBox(width: Spacing.md),
                          Expanded(child: choices[1]),
                        ],
                      ),
                    )
                  else ...[
                    choices[0],
                    const SizedBox(height: Spacing.md),
                    choices[1],
                  ],
                  const SizedBox(height: Spacing.xl),
                  TextButton.icon(
                    onPressed: () => unawaited(ref.read(authRepositoryProvider).signOut()),
                    icon: const Icon(Icons.logout_rounded),
                    label: Text(l10n.signOut),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final String action;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 32, color: theme.colorScheme.secondary),
          const SizedBox(height: Spacing.md),
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: Spacing.xs),
          Text(body, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: Spacing.lg),
          if (primary)
            FilledButton(onPressed: onTap, child: Text(action))
          else
            OutlinedButton(onPressed: onTap, child: Text(action)),
        ],
      ),
    );
  }
}
