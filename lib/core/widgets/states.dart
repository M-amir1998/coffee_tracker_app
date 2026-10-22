import 'package:coffee_tracker/core/errors/failure_messages.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({required this.icon, required this.title, super.key, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(color: theme.colorScheme.secondaryContainer, shape: BoxShape.circle),
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.md),
                  child: Icon(icon, size: 32, color: theme.colorScheme.onSecondaryContainer),
                ),
              ),
              const SizedBox(height: Spacing.md),
              Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: Spacing.xs),
                Text(
                  message!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...[const SizedBox(height: Spacing.md), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({required this.error, super.key, this.onRetry, this.compact = false});

  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final message = describeFailure(l10n, error);
    if (compact) {
      return Row(
        children: [
          Icon(Icons.error_outline_rounded, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: Spacing.xs),
          Expanded(child: Text(message)),
          if (onRetry != null) TextButton(onPressed: onRetry, child: Text(l10n.actionRetry)),
        ],
      );
    }
    return EmptyState(
      icon: Icons.cloud_off_rounded,
      title: l10n.errorTitle,
      message: message,
      action: onRetry == null
          ? null
          : FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.actionRetry),
            ),
    );
  }
}

/// A shimmering placeholder block shown while content loads.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.height = 16, this.width, this.radius = Radii.sm});

  final double height;
  final double? width;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            color: Color.lerp(scheme.surfaceContainerHigh, scheme.surfaceContainerHighest, _controller.value),
          ),
        ),
      ),
    );
  }
}

/// Loading placeholder resembling a list of rows.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.rows = 4});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.loading,
      child: Column(
        children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
              child: Row(
                children: [
                  const Skeleton(height: 36, width: 36, radius: 18),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Skeleton(height: 14, width: 120.0 + (i % 3) * 40),
                        const SizedBox(height: 6),
                        const Skeleton(height: 12, width: 90),
                      ],
                    ),
                  ),
                  const Skeleton(height: 14, width: 56),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Renders an [AsyncValue] without flicker: once data exists it stays visible
/// while refreshing; errors with existing data show a small banner.
class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({required this.value, required this.data, super.key, this.loading, this.onRetry});

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final Widget? loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (value.hasValue) {
      final content = data(value.requireValue);
      if (value.hasError && !value.isLoading) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: ErrorState(error: value.error!, onRetry: onRetry, compact: true),
            ),
            Flexible(child: content),
          ],
        );
      }
      return content;
    }
    if (value.hasError) return ErrorState(error: value.error!, onRetry: onRetry);
    return loading ?? const Padding(padding: EdgeInsets.all(Spacing.lg), child: SkeletonList());
  }
}
