import 'dart:async';

import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/app/routes.dart';
import 'package:coffee_tracker/core/errors/failure_messages.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/money/money.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/app_card.dart';
import 'package:coffee_tracker/core/widgets/page_layout.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/groups/presentation/timezone_field.dart';
import 'package:coffee_tracker/features/transactions/presentation/forms/amount_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

class CreateGroupPage extends ConsumerStatefulWidget {
  const CreateGroupPage({super.key});

  @override
  ConsumerState<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends ConsumerState<CreateGroupPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _cycle = TextEditingController();
  String _timezone = 'Europe/Madrid';
  bool _busy = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cycle.text.isEmpty) {
      _cycle.text = toBeginningOfSentenceCase(DateFormat.yMMMM(context.localeTag).format(DateTime.now()));
    }
    if (_price.text.isEmpty) _price.text = Money.toInput(20, locale: context.localeTag);
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _cycle.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref
          .read(groupRepositoryProvider)
          .createGroup(
            name: _name.text.trim(),
            firstCycleName: _cycle.text.trim(),
            coffeePriceCents: Money.parse(_price.text)!,
            timezone: _timezone,
          );
      await ref.read(selectedGroupIdProvider.notifier).select(id);
      ref.invalidate(myGroupsProvider);
      if (mounted) context.go(Routes.home);
    } on Object catch (error) {
      if (mounted) setState(() => _error = describeFailure(context.l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppPage(
      title: l10n.createGroupTitle,
      maxWidth: 640,
      showBackButton: true,
      body: Form(
        key: _formKey,
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.createGroupIntro, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: Spacing.lg),
              TextFormField(
                controller: _name,
                maxLength: 60,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: l10n.fieldGroupName, hintText: l10n.groupNameHint),
                validator: (value) => (value?.trim().isEmpty ?? true) ? l10n.validationNameRequired : null,
              ),
              const SizedBox(height: Spacing.sm),
              AmountField(
                controller: _price,
                label: l10n.fieldCoffeePrice,
                helper: l10n.coffeePriceHelper,
                maxCents: 10000,
              ),
              const SizedBox(height: Spacing.md),
              TimezoneField(initialValue: _timezone, onChanged: (value) => _timezone = value),
              const SizedBox(height: Spacing.md),
              TextFormField(
                controller: _cycle,
                maxLength: 60,
                decoration: InputDecoration(labelText: l10n.fieldFirstCycleName, helperText: l10n.firstCycleHelper),
                validator: (value) => (value?.trim().isEmpty ?? true) ? l10n.validationNameRequired : null,
              ),
              const SizedBox(height: Spacing.md),
              if (_error != null) ...[
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: Spacing.sm),
              ],
              FilledButton(
                onPressed: _busy ? null : () => unawaited(_submit()),
                child: _busy
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(l10n.createGroupAction),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
