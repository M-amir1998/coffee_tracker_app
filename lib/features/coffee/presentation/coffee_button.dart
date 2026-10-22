import 'dart:async';

import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/feedback.dart';
import 'package:coffee_tracker/features/coffee/application/coffee_queue.dart';
import 'package:coffee_tracker/features/coffee/presentation/coffee_actions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// The primary action of the app: one tap records one coffee.
class CoffeeButton extends ConsumerStatefulWidget {
  const CoffeeButton({required this.groupId, required this.todayCoffees, required this.priceLabel, super.key});

  final String groupId;
  final int todayCoffees;
  final String priceLabel;

  @override
  ConsumerState<CoffeeButton> createState() => _CoffeeButtonState();
}

class _CoffeeButtonState extends ConsumerState<CoffeeButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: Motion.slow);
  bool _success = false;
  bool _busy = false;
  Timer? _reset;

  @override
  void dispose() {
    _pulse.dispose();
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _record({int quantity = 1}) async {
    if (_busy) return;
    setState(() => _busy = true);
    if (!MediaQuery.disableAnimationsOf(context)) unawaited(_pulse.forward(from: 0));
    final outcome = await recordCoffee(context, ref, groupId: widget.groupId, quantity: quantity);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _success = outcome is! CoffeeRejected;
    });
    _reset?.cancel();
    _reset = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _success = false);
    });
  }

  Future<void> _several() async {
    final quantity = await showAdaptiveSheet<int>(context, builder: (_) => const _QuantitySheet());
    if (quantity != null && mounted) await _record(quantity: quantity);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final press = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1, end: 0.94).chain(CurveTween(curve: Curves.easeOut)), weight: 35),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.94, end: 1).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 65,
      ),
    ]).animate(_pulse);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScaleTransition(
          scale: press,
          child: SizedBox(
            height: 76,
            child: FilledButton(
              key: const Key('add-coffee-button'),
              style: FilledButton.styleFrom(
                backgroundColor: _success ? scheme.tertiary : scheme.primary,
                foregroundColor: _success ? scheme.onTertiary : scheme.onPrimary,
                textStyle: theme.textTheme.titleLarge,
              ),
              onPressed: _busy ? null : () => unawaited(_record()),
              child: AnimatedSwitcher(
                duration: Motion.of(context, Motion.medium),
                transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                // Scales down instead of overflowing with very large text. The
                // label merges into the button, which keeps its tap action
                // for screen readers.
                child: Semantics(
                  key: ValueKey(_success),
                  label: _success ? l10n.coffeeAdded : l10n.addCoffeeSemantic(widget.priceLabel),
                  excludeSemantics: true,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_success ? Icons.check_circle_rounded : Icons.coffee_rounded, size: 30),
                        const SizedBox(width: Spacing.sm),
                        Text(_success ? l10n.coffeeAdded : l10n.addCoffee),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Spacing.sm),
        Row(
          children: [
            Expanded(
              child: Text(l10n.todayCoffees(widget.todayCoffees, widget.priceLabel), style: theme.textTheme.bodySmall),
            ),
            TextButton.icon(
              onPressed: _busy ? null : () => unawaited(_several()),
              icon: const Icon(Icons.exposure_plus_2_rounded),
              label: Text(l10n.addSeveral),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuantitySheet extends StatefulWidget {
  const _QuantitySheet();

  @override
  State<_QuantitySheet> createState() => _QuantitySheetState();
}

class _QuantitySheetState extends State<_QuantitySheet> {
  int _quantity = 2;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xs, Spacing.lg, Spacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.addSeveralTitle, style: theme.textTheme.headlineSmall),
          const SizedBox(height: Spacing.xs),
          Text(l10n.addSeveralHint, style: theme.textTheme.bodyMedium),
          const SizedBox(height: Spacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                tooltip: l10n.decrease,
                iconSize: 28,
                onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                icon: const Icon(Icons.remove_rounded),
              ),
              SizedBox(
                width: 96,
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    '$_quantity',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displayMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: l10n.increase,
                iconSize: 28,
                onPressed: _quantity < 20 ? () => setState(() => _quantity++) : null,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: Spacing.lg),
          FilledButton(onPressed: () => Navigator.pop(context, _quantity), child: Text(l10n.recordCoffees(_quantity))),
        ],
      ),
    );
  }
}

/// Offline coffees waiting for the server, and coffees it refused.
class PendingCoffeesBanner extends ConsumerWidget {
  const PendingCoffeesBanner({required this.groupId, super.key});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final queue = ref.watch(coffeeQueueProvider);
    final waiting = queue.waitingCoffees(groupId);
    final failed = queue.failed(groupId);
    if (waiting == 0 && failed.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final controller = ref.read(coffeeQueueProvider.notifier);

    return Column(
      children: [
        if (waiting > 0)
          _Banner(
            icon: Icons.cloud_upload_outlined,
            color: scheme.secondaryContainer,
            text: l10n.coffeesWaitingToSync(waiting),
            action: queue.syncing
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : TextButton(onPressed: () => unawaited(controller.syncAll()), child: Text(l10n.syncNow)),
          ),
        for (final item in failed)
          _Banner(
            icon: Icons.error_outline_rounded,
            color: scheme.errorContainer,
            text: l10n.coffeeSyncFailed(item.quantity, context.dateTime(item.occurredAt)),
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(onPressed: () => unawaited(controller.retry(item.key)), child: Text(l10n.actionRetry)),
                TextButton(
                  onPressed: () => unawaited(controller.removeQueued(item.key)),
                  child: Text(l10n.actionDiscard),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text, required this.action});

  final IconData icon;
  final Color color;
  final String text;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(Radii.md)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.sm, Spacing.xs, Spacing.xs, Spacing.xs),
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: Spacing.sm),
              Expanded(child: Semantics(liveRegion: true, child: Text(text))),
              action,
            ],
          ),
        ),
      ),
    );
  }
}
