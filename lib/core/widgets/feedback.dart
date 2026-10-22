import 'package:coffee_tracker/core/errors/failure_messages.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// Shows a short message at the bottom of the screen.
void showToast(BuildContext context, String message, {String? actionLabel, VoidCallback? onAction, IconData? icon}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: Theme.of(context).colorScheme.onInverseSurface, size: 20),
              const SizedBox(width: Spacing.sm),
            ],
            Expanded(child: Text(message)),
          ],
        ),
        action: actionLabel == null || onAction == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction),
        duration: Duration(seconds: actionLabel == null ? 4 : 7),
      ),
    );
}

void showErrorToast(BuildContext context, Object error) =>
    showToast(context, describeFailure(context.l10n, error), icon: Icons.error_outline_rounded);

/// Presents [child] as a bottom sheet on phones and as a dialog on larger
/// screens.
Future<T?> showAdaptiveSheet<T>(BuildContext context, {required WidgetBuilder builder}) {
  if (WindowSize.of(context).isCompact) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: builder(context),
      ),
    );
  }
  return showDialog<T>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: builder(context)),
    ),
  );
}

/// Asks the user to confirm a sensitive action.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.actionCancel)),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError)
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Asks for a short note (e.g. a rejection reason). Returns null if cancelled.
Future<String?> askForNote(
  BuildContext context, {
  required String title,
  required String label,
  required String confirmLabel,
  bool required = true,
  bool destructive = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _NoteDialog(
      title: title,
      label: label,
      confirmLabel: confirmLabel,
      required: required,
      destructive: destructive,
    ),
  );
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({
    required this.title,
    required this.label,
    required this.confirmLabel,
    required this.required,
    required this.destructive,
  });

  final String title;
  final String label;
  final String confirmLabel;
  final bool required;
  final bool destructive;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid => !widget.required || _controller.text.trim().length >= 3;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 500,
        minLines: 2,
        maxLines: 4,
        decoration: InputDecoration(labelText: widget.label),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.actionCancel)),
        FilledButton(
          style: widget.destructive
              ? FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError)
              : null,
          onPressed: _valid ? () => Navigator.pop(context, _controller.text.trim()) : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Requires typing [expected] (e.g. the cycle name) before confirming an
/// action that cannot be undone.
Future<bool> confirmByTyping(
  BuildContext context, {
  required String title,
  required String message,
  required String expected,
  required String confirmLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) =>
        _TypedConfirmDialog(title: title, message: message, expected: expected, confirmLabel: confirmLabel),
  );
  return result ?? false;
}

class _TypedConfirmDialog extends StatefulWidget {
  const _TypedConfirmDialog({
    required this.title,
    required this.message,
    required this.expected,
    required this.confirmLabel,
  });

  final String title;
  final String message;
  final String expected;
  final String confirmLabel;

  @override
  State<_TypedConfirmDialog> createState() => _TypedConfirmDialogState();
}

class _TypedConfirmDialogState extends State<_TypedConfirmDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final matches = _controller.text.trim() == widget.expected;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: Spacing.md),
          Text(l10n.typeToConfirm(widget.expected), style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: Spacing.xs),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(hintText: widget.expected),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.actionCancel)),
        FilledButton(onPressed: matches ? () => Navigator.pop(context, true) : null, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
