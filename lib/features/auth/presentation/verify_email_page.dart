import 'dart:async';

import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/app/routes.dart';
import 'package:coffee_tracker/core/errors/failure_messages.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/feedback.dart';
import 'package:coffee_tracker/features/auth/presentation/auth_layout.dart';
import 'package:coffee_tracker/features/auth/presentation/sign_in_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Confirms the email address with the six-digit code (works on every
/// platform, including desktop apps that cannot open email links).
class VerifyEmailPage extends ConsumerStatefulWidget {
  const VerifyEmailPage({required this.email, super.key});

  final String email;

  @override
  ConsumerState<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends ConsumerState<VerifyEmailPage> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.email);
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).verifySignUpCode(email: _email.text, code: _code.text.replaceAll(' ', ''));
    } on Object catch (error) {
      if (mounted) setState(() => _error = describeFailure(context.l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final l10n = context.l10n;
    if (AuthValidators.email(l10n, _email.text) != null) return;
    try {
      await ref.read(authRepositoryProvider).resendConfirmation(_email.text);
      if (mounted) showToast(context, l10n.confirmationResent, icon: Icons.mark_email_read_outlined);
    } on Object catch (error) {
      if (mounted) showErrorToast(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AuthLayout(
      title: l10n.verifyTitle,
      subtitle: l10n.verifySubtitle,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(letterSpacing: 8),
              decoration: InputDecoration(labelText: l10n.fieldCode, prefixIcon: const Icon(Icons.pin_outlined)),
              validator: (value) => AuthValidators.code(l10n, value),
              onFieldSubmitted: (_) => unawaited(_verify()),
            ),
            const SizedBox(height: Spacing.md),
            if (_error != null) ...[AuthErrorBanner(message: _error!), const SizedBox(height: Spacing.sm)],
            FilledButton(
              onPressed: _busy ? null : () => unawaited(_verify()),
              child: _busy
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l10n.verifyAction),
            ),
            const SizedBox(height: Spacing.sm),
            TextButton(onPressed: () => unawaited(_resend()), child: Text(l10n.resendCode)),
            TextButton(onPressed: () => context.go(Routes.signIn), child: Text(l10n.backToSignIn)),
          ],
        ),
      ),
    );
  }
}
