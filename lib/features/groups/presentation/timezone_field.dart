import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Searchable IANA time-zone picker backed by the database's zone list.
class TimezoneField extends ConsumerWidget {
  const TimezoneField({required this.initialValue, required this.onChanged, super.key});

  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final zones = ref.watch(timezonesProvider).value ?? const ['Europe/Madrid', 'UTC'];
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: initialValue),
      optionsBuilder: (value) {
        final query = value.text.toLowerCase().replaceAll(' ', '_');
        if (query.isEmpty) return zones.take(30);
        return zones.where((zone) => zone.toLowerCase().contains(query)).take(30);
      },
      onSelected: onChanged,
      fieldViewBuilder: (context, controller, focusNode, onSubmit) => TextFormField(
        controller: controller,
        focusNode: focusNode,
        decoration: InputDecoration(
          labelText: l10n.fieldTimezone,
          helperText: l10n.timezoneHelper,
          prefixIcon: const Icon(Icons.public_rounded),
        ),
        validator: (value) => zones.contains(value) ? null : l10n.validationTimezone,
        onFieldSubmitted: (_) => onSubmit(),
      ),
    );
  }
}
