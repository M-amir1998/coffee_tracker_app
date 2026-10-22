import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/app_card.dart';
import 'package:coffee_tracker/features/shell/presentation/app_logo.dart';
import 'package:material_ui/material_ui.dart';

/// Explains a missing or unsafe build configuration instead of crashing.
class SetupRequiredPage extends StatelessWidget {
  const SetupRequiredPage({required this.problems, super.key});

  final List<String> problems;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Spacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppLogo(size: 56),
                  const SizedBox(height: Spacing.md),
                  Text(l10n.setupTitle, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: Spacing.sm),
                  Text(l10n.setupMessage),
                  const SizedBox(height: Spacing.md),
                  for (final problem in problems)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.xs),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline_rounded, color: theme.colorScheme.error, size: 20),
                          const SizedBox(width: Spacing.xs),
                          Expanded(child: SelectableText(problem)),
                        ],
                      ),
                    ),
                  const SizedBox(height: Spacing.md),
                  SelectableText(
                    'flutter run --dart-define-from-file=config/development.json',
                    style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
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
