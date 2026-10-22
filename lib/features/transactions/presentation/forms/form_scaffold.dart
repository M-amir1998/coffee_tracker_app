import 'dart:async';

import 'package:coffee_tracker/core/errors/failure_messages.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// Common frame for transaction forms shown in sheets/dialogs.
class FormScaffold extends StatelessWidget {
  const FormScaffold({
    required this.icon,
    required this.title,
    required this.children,
    required this.submitLabel,
    required this.onSubmit,
    required this.busy,
    super.key,
    this.formKey,
    this.error,
    this.info,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;
  final String submitLabel;
  final VoidCallback onSubmit;
  final bool busy;
  final GlobalKey<FormState>? formKey;
  final String? error;

  /// Explains what the operation does to balances and the cash box.
  final String? info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xs, Spacing.lg, Spacing.lg),
      child: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(color: scheme.secondaryContainer, shape: BoxShape.circle),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(icon, color: scheme.onSecondaryContainer),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Semantics(header: true, child: Text(title, style: theme.textTheme.headlineSmall)),
                ),
              ],
            ),
            if (info != null) ...[
              const SizedBox(height: Spacing.md),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 20, color: scheme.onSurfaceVariant),
                      const SizedBox(width: Spacing.xs),
                      Expanded(
                        child: Text(info!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurface)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: Spacing.lg),
            ...children,
            if (error != null) ...[
              const SizedBox(height: Spacing.sm),
              Semantics(
                liveRegion: true,
                child: Text(error!, style: TextStyle(color: scheme.error)),
              ),
            ],
            const SizedBox(height: Spacing.lg),
            FilledButton(
              onPressed: busy ? null : onSubmit,
              child: busy
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(submitLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// State helper for forms that submit once and close.
mixin SubmitOnce<T extends StatefulWidget> on State<T> {
  bool busy = false;
  String? error;

  Future<void> runSubmit(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } on Object catch (e) {
      if (mounted) setState(() => error = describeFailure(context.l10n, e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void submitFrom(Future<void> Function() action) => unawaited(runSubmit(action));
}
