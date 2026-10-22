import 'dart:async';

import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/money/money.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/app_card.dart';
import 'package:coffee_tracker/core/widgets/feedback.dart';
import 'package:coffee_tracker/core/widgets/page_layout.dart';
import 'package:coffee_tracker/core/widgets/states.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/transactions/presentation/forms/amount_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class PricePage extends ConsumerStatefulWidget {
  const PricePage({super.key});

  @override
  ConsumerState<PricePage> createState() => _PricePageState();
}

class _PricePageState extends ConsumerState<PricePage> {
  final _formKey = GlobalKey<FormState>();
  final _price = TextEditingController();
  DateTime? _from;
  bool _busy = false;

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  Future<void> _save(String groupId, String currency) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = context.l10n;
    final cents = Money.parse(_price.text)!;
    final ok = await confirmAction(
      context,
      title: l10n.priceConfirmTitle,
      message: l10n.priceConfirmMessage(
        context.money(cents, currency: currency),
        _from == null ? l10n.priceFromNow : context.shortDate(_from!),
      ),
      confirmLabel: l10n.actionSave,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await ref.read(groupRepositoryProvider).setCoffeePrice(groupId, cents, effectiveFrom: _from);
      ref.read(dataRevisionProvider.notifier).bump();
      _price.clear();
      if (mounted) showToast(context, l10n.priceSaved, icon: Icons.check_rounded);
    } on Object catch (error) {
      if (mounted) showErrorToast(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final group = ref.watch(currentGroupProvider).value;
    if (group == null) return const SizedBox.shrink();
    final prices = ref.watch(pricesProvider(group.id));
    final now = DateTime.now();

    return AppPage(
      title: l10n.adminPrice,
      showBackButton: true,
      maxWidth: 760,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: l10n.newPrice,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.priceExplanation, style: theme.textTheme.bodySmall),
                  const SizedBox(height: Spacing.md),
                  AmountField(controller: _price, label: l10n.fieldCoffeePrice, maxCents: 10000, currency: group.currency),
                  const SizedBox(height: Spacing.sm),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _from ?? now.add(const Duration(days: 1)),
                        firstDate: now,
                        lastDate: now.add(const Duration(days: 365)),
                      );
                      setState(() => _from = picked == null ? null : DateTime(picked.year, picked.month, picked.day));
                    },
                    icon: const Icon(Icons.event_rounded),
                    label: Text(_from == null ? l10n.priceFromNow : l10n.priceFromDate(context.shortDate(_from!))),
                  ),
                  const SizedBox(height: Spacing.md),
                  FilledButton(
                    onPressed: _busy ? null : () => unawaited(_save(group.id, group.currency)),
                    child: Text(l10n.actionSave),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
          SectionCard(
            title: l10n.priceHistory,
            child: AsyncValueView(
              value: prices,
              data: (list) => Column(
                children: [
                  for (final price in list)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(price.effectiveFrom.isAfter(now) ? Icons.schedule_rounded : Icons.sell_rounded),
                      title: Text(context.money(price.priceCents, currency: group.currency)),
                      subtitle: Text(
                        price.effectiveFrom.isAfter(now)
                            ? l10n.priceScheduled(context.dateTime(price.effectiveFrom))
                            : l10n.priceSince(context.dateTime(price.effectiveFrom)),
                      ),
                      trailing: price.effectiveFrom.isAfter(now)
                          ? IconButton(
                              tooltip: l10n.cancelScheduledPrice,
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () async {
                                try {
                                  await ref.read(groupRepositoryProvider).cancelScheduledPrice(price.id);
                                  ref.read(dataRevisionProvider.notifier).bump();
                                } on Object catch (error) {
                                  if (context.mounted) showErrorToast(context, error);
                                }
                              },
                            )
                          : null,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
