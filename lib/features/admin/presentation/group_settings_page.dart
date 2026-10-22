import 'dart:async';

import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/app_card.dart';
import 'package:coffee_tracker/core/widgets/feedback.dart';
import 'package:coffee_tracker/core/widgets/page_layout.dart';
import 'package:coffee_tracker/core/widgets/states.dart';
import 'package:coffee_tracker/features/accounting/application/report_providers.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/groups/domain/group_models.dart';
import 'package:coffee_tracker/features/groups/presentation/timezone_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class GroupSettingsPage extends ConsumerWidget {
  const GroupSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final groupId = ref.watch(currentGroupIdProvider);
    if (groupId == null) return const SizedBox.shrink();
    final dashboard = ref.watch(dashboardProvider(groupId));
    return AppPage(
      title: l10n.adminSettings,
      showBackButton: true,
      maxWidth: 720,
      body: AsyncValueView(
        value: dashboard,
        data: (data) => _SettingsForm(settings: data.group),
      ),
    );
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.settings});

  final GroupSettings settings;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.settings.name);
  late String _timezone = widget.settings.timezone;
  late bool _depositConfirmation = widget.settings.requireDepositConfirmation;
  late bool _purchaseApproval = widget.settings.requirePurchaseApproval;
  late double _undo = widget.settings.undoWindowMinutes.toDouble();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(groupRepositoryProvider)
          .updateSettings(
            widget.settings.id,
            name: _name.text.trim(),
            timezone: _timezone,
            requireDepositConfirmation: _depositConfirmation,
            requirePurchaseApproval: _purchaseApproval,
            undoWindowMinutes: _undo.round(),
          );
      ref.read(dataRevisionProvider.notifier).bump();
      if (mounted) showToast(context, context.l10n.settingsSaved, icon: Icons.check_rounded);
    } on Object catch (error) {
      if (mounted) showErrorToast(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Form(
      key: _formKey,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _name,
              maxLength: 60,
              decoration: InputDecoration(labelText: l10n.fieldGroupName),
              validator: (value) => (value?.trim().isEmpty ?? true) ? l10n.validationNameRequired : null,
            ),
            const SizedBox(height: Spacing.sm),
            TimezoneField(initialValue: _timezone, onChanged: (value) => _timezone = value),
            const SizedBox(height: Spacing.md),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.settingDepositConfirmation),
              subtitle: Text(l10n.settingDepositConfirmationHint),
              value: _depositConfirmation,
              onChanged: (value) => setState(() => _depositConfirmation = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.settingPurchaseApproval),
              subtitle: Text(l10n.settingPurchaseApprovalHint),
              value: _purchaseApproval,
              onChanged: (value) => setState(() => _purchaseApproval = value),
            ),
            const SizedBox(height: Spacing.sm),
            Text(l10n.settingUndoWindow(_undo.round()), style: Theme.of(context).textTheme.titleSmall),
            Slider(
              value: _undo,
              max: 60,
              divisions: 12,
              label: l10n.minutesShort(_undo.round()),
              onChanged: (value) => setState(() => _undo = value),
            ),
            Text(l10n.settingUndoWindowHint, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: Spacing.lg),
            FilledButton(onPressed: _busy ? null : () => unawaited(_save()), child: Text(l10n.actionSave)),
          ],
        ),
      ),
    );
  }
}
