import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/widgets/member_avatar.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/groups/domain/group_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Dropdown of active group members.
class MemberPicker extends ConsumerWidget {
  const MemberPicker({
    required this.groupId,
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
    this.exclude = const {},
    this.subtitleFor,
  });

  final String groupId;
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final Set<String> exclude;

  /// Optional extra information per member (e.g. their balance).
  final String? Function(Member member)? subtitleFor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final members = (ref.watch(membersProvider(groupId)).value ?? const <Member>[])
        .where((m) => m.isActive && !exclude.contains(m.userId))
        .toList();
    return DropdownButtonFormField<String>(
      initialValue: members.any((m) => m.userId == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      validator: (selected) => selected == null ? l10n.validationMemberRequired : null,
      items: [
        for (final member in members)
          DropdownMenuItem(
            value: member.userId,
            child: Row(
              children: [
                MemberAvatar(name: member.displayName, radius: 12),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    [member.displayName, ?subtitleFor?.call(member)].join(' · '),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}
