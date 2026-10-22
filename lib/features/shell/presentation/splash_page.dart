import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/states.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/shell/presentation/app_logo.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Shown while the session and the user's groups load (and when that fails).
class SplashPage extends ConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(myGroupsProvider);
    return Scaffold(
      body: Center(
        child: groups.hasError && !groups.isLoading
            ? ErrorState(error: groups.error!, onRetry: () => ref.invalidate(myGroupsProvider))
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLogo(size: 72),
                  const SizedBox(height: Spacing.lg),
                  Semantics(
                    label: context.l10n.loading,
                    child: const SizedBox(width: 120, child: LinearProgressIndicator()),
                  ),
                ],
              ),
      ),
    );
  }
}
