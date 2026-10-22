import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

Future<void> showShortcutsHelp(BuildContext context) {
  final l10n = context.l10n;
  final shortcuts = [
    ('Alt + C', l10n.shortcutAddCoffee),
    ('Alt + 1 … 9', l10n.shortcutNavigate),
    ('Alt + R', l10n.shortcutRefresh),
    ('Alt + /', l10n.shortcutHelp),
  ];
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.shortcutsTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (keys, description) in shortcuts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
              child: Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      child: Text(keys, style: Theme.of(context).textTheme.labelLarge),
                    ),
                  ),
                  const SizedBox(width: Spacing.md),
                  Expanded(child: Text(description)),
                ],
              ),
            ),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.actionClose))],
    ),
  );
}
