import 'dart:async';

import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/app/routes.dart';
import 'package:coffee_tracker/core/errors/app_failure.dart';
import 'package:coffee_tracker/core/errors/failure_messages.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/app_card.dart';
import 'package:coffee_tracker/core/widgets/page_layout.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/groups/domain/group_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Join a group with an invitation code (typed, or from an invitation link).
class JoinGroupPage extends ConsumerStatefulWidget {
  const JoinGroupPage({super.key, this.code});

  final String? code;

  @override
  ConsumerState<JoinGroupPage> createState() => _JoinGroupPageState();
}

class _JoinGroupPageState extends ConsumerState<JoinGroupPage> {
  late final _code = TextEditingController(text: widget.code ?? '');
  InvitationPreview? _preview;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if ((widget.code ?? '').isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_check()));
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String get _normalized => _code.text.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

  Future<void> _check() async {
    if (_normalized.length != 8) {
      setState(() => _error = context.l10n.validationInvitationCode);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preview = await ref.read(groupRepositoryProvider).previewInvitation(_normalized);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _error = preview.valid ? null : describeFailure(context.l10n, _ruleError(preview.reason));
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = describeFailure(context.l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Object _ruleError(String? reason) => RuleFailure(reason ?? 'invalid_invitation');

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final groupId = await ref.read(groupRepositoryProvider).joinGroup(_normalized);
      await ref.read(selectedGroupIdProvider.notifier).select(groupId);
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
    final theme = Theme.of(context);
    final preview = _preview;
    return AppPage(
      title: l10n.joinGroupTitle,
      maxWidth: 560,
      showBackButton: true,
      body: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.joinGroupIntro),
            const SizedBox(height: Spacing.lg),
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9-]')), LengthLimitingTextInputFormatter(9)],
              style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 4),
              decoration: InputDecoration(labelText: l10n.fieldInvitationCode, hintText: 'ABCD-EFGH'),
              onChanged: (_) => setState(() => _preview = null),
              onSubmitted: (_) => unawaited(_check()),
            ),
            const SizedBox(height: Spacing.md),
            if (_error != null) ...[
              Semantics(liveRegion: true, child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
              const SizedBox(height: Spacing.sm),
            ],
            if (preview != null && preview.valid) ...[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: ListTile(
                  leading: const Icon(Icons.groups_rounded),
                  title: Text(preview.groupName ?? ''),
                  subtitle: Text(
                    preview.alreadyMember ? l10n.alreadyMember : l10n.membersCount(preview.memberCount ?? 0),
                  ),
                ),
              ),
              const SizedBox(height: Spacing.md),
              FilledButton(
                onPressed: _busy ? null : () => unawaited(_join()),
                child: Text(preview.alreadyMember ? l10n.openGroup : l10n.joinGroupAction(preview.groupName ?? '')),
              ),
            ] else
              FilledButton.tonal(
                onPressed: _busy ? null : () => unawaited(_check()),
                child: _busy
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(l10n.checkCode),
              ),
          ],
        ),
      ),
    );
  }
}
