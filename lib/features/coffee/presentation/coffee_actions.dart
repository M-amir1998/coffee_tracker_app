import 'dart:async';

import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/core/errors/failure_messages.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/money/money.dart';
import 'package:coffee_tracker/features/coffee/application/coffee_queue.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Records coffees for the signed-in member and shows the outcome with an
/// Undo action. Returns the outcome so callers can animate accordingly.
Future<CoffeeOutcome> recordCoffee(
  BuildContext context,
  WidgetRef ref, {
  required String groupId,
  int quantity = 1,
}) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final locale = context.localeTag;
  unawaited(HapticFeedback.mediumImpact());

  final outcome = await ref.read(coffeeQueueProvider.notifier).record(groupId, quantity: quantity);

  void show(String message, {IconData? icon, VoidCallback? onUndo}) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 12)],
              Expanded(child: Text(message)),
            ],
          ),
          action: onUndo == null ? null : SnackBarAction(label: l10n.actionUndo, onPressed: onUndo),
          duration: const Duration(seconds: 6),
        ),
      );
  }

  switch (outcome) {
    case CoffeeRecorded(:final result):
      final balance = result.balanceCents;
      show(
        balance == null ? l10n.coffeeRecorded(quantity) : l10n.coffeeRecordedWithBalance(quantity, _balanceText(l10n, balance, locale)),
        icon: Icons.coffee_rounded,
        onUndo: () => unawaited(_undo(ref, messenger, l10n, result.transactionId)),
      );
    case CoffeeQueued(:final key):
      show(
        l10n.coffeeQueuedOffline(quantity),
        icon: Icons.cloud_upload_outlined,
        onUndo: () => unawaited(ref.read(coffeeQueueProvider.notifier).removeQueued(key)),
      );
    case CoffeeRejected(:final failure):
      unawaited(HapticFeedback.heavyImpact());
      show(describeFailure(l10n, failure), icon: Icons.error_outline_rounded);
  }
  return outcome;
}

String _balanceText(AppLocalizations l10n, int balanceCents, String locale) {
  if (balanceCents == 0) return l10n.balanceSettledShort;
  final amount = _format(balanceCents.abs(), locale);
  return balanceCents > 0 ? l10n.balanceYouOweShort(amount) : l10n.balanceOwedToYouShort(amount);
}

String _format(int cents, String locale) => Money.format(cents, locale: locale);

Future<void> _undo(WidgetRef ref, ScaffoldMessengerState messenger, AppLocalizations l10n, String transactionId) async {
  try {
    await ref.read(ledgerRepositoryProvider).undoCoffee(transactionId);
    ref.read(dataRevisionProvider.notifier).bump();
    messenger.showSnackBar(SnackBar(content: Text(l10n.coffeeUndone)));
  } on Object catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(describeFailure(l10n, error))));
  }
}
