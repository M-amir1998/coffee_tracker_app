import 'dart:async';

import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/app/routes.dart';
import 'package:coffee_tracker/core/errors/failure_messages.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/feedback.dart';
import 'package:coffee_tracker/features/auth/application/auth_providers.dart';
import 'package:coffee_tracker/features/auth/presentation/auth_layout.dart';
import 'package:coffee_tracker/features/auth/presentation/sign_in_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Sets a new password. Coming from the recovery email link the user is
/// already authenticated; otherwise they enter the six-digit code first.
class ResetPasswordPage extends ConsumerStatefulWidget {
  const ResetPasswordPage({super.key, this.email});

  final String? email;

  @override
  ConsumerState<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends ConsumerState<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.email ?? '');
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Whether the screen was opened from the recovery link (already signed in).
  late final bool _viaLink = ref.read(passwordRecoveryProvider);

  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    final l10n = context.l10n;
    final recovery = ref.read(passwordRecoveryProvider.notifier);
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = ref.read(authRepositoryProvider);
    try {
      if (!_viaLink) {
        // Verifying the code signs the user in; keep the router on this screen
        // until the new password is saved.
        recovery.start();
        await auth.verifyRecoveryCode(email: _email.text, code: _code.text);
      }
      await auth.updatePassword(_password.text);
      recovery.finish();
      if (!mounted) return;
      showToast(context, l10n.passwordUpdated, icon: Icons.check_circle_outline_rounded);
      context.go(Routes.home);
    } on Object catch (error) {
      if (!_viaLink && ref.read(authRepositoryProvider).currentSession == null) recovery.finish();
      if (mounted) setState(() => _error = describeFailure(l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final viaLink = _viaLink;
    return AuthLayout(
      title: l10n.resetTitle,
      subtitle: viaLink ? l10n.resetSubtitleLink : l10n.resetSubtitleCode,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!viaLink) ...[
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: l10n.fieldEmail, prefixIcon: const Icon(Icons.mail_outline_rounded)),
                validator: (value) => AuthValidators.email(l10n, value),
              ),
              const SizedBox(height: Spacing.md),
              TextFormField(
                controller: _code,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                decoration: InputDecoration(labelText: l10n.fieldCode, prefixIcon: const Icon(Icons.pin_outlined)),
                validator: (value) => AuthValidators.code(l10n, value),
              ),
              const SizedBox(height: Spacing.md),
            ],
            PasswordField(
              controller: _password,
              label: l10n.fieldNewPassword,
              autofillHints: const [AutofillHints.newPassword],
              validator: (value) => AuthValidators.newPassword(l10n, value),
              onSubmitted: (_) => unawaited(_submit()),
            ),
            const SizedBox(height: Spacing.xs),
            Text(l10n.passwordPolicy, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: Spacing.md),
            if (_error != null) ...[AuthErrorBanner(message: _error!), const SizedBox(height: Spacing.sm)],
            FilledButton(
              onPressed: _busy ? null : () => unawaited(_submit()),
              child: _busy
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l10n.savePassword),
            ),
            if (!viaLink)
              TextButton(onPressed: () => context.go(Routes.signIn), child: Text(l10n.backToSignIn)),
          ],
        ),
      ),
    );
  }
}
