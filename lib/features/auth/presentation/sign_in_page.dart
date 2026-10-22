import 'dart:async';

import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/app/routes.dart';
import 'package:coffee_tracker/core/errors/app_failure.dart';
import 'package:coffee_tracker/core/errors/failure_messages.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/features/auth/presentation/auth_layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class SignInPage extends ConsumerStatefulWidget {
  const SignInPage({super.key, this.next});

  /// Location to continue to after signing in (e.g. an invitation link).
  final String? next;

  @override
  ConsumerState<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends ConsumerState<SignInPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _unconfirmed = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
      _unconfirmed = false;
    });
    try {
      await ref.read(authRepositoryProvider).signIn(email: _email.text, password: _password.text);
      // The router redirects once the session arrives.
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = describeFailure(context.l10n, failure);
        _unconfirmed = failure is AuthFailure && failure.code == 'email_not_confirmed';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final next = widget.next;
    return AuthLayout(
      title: l10n.signInTitle,
      subtitle: l10n.signInSubtitle,
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email, AutofillHints.username],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.fieldEmail,
                  prefixIcon: const Icon(Icons.mail_outline_rounded),
                ),
                validator: (value) => AuthValidators.email(l10n, value),
              ),
              const SizedBox(height: Spacing.md),
              PasswordField(
                controller: _password,
                label: l10n.fieldPassword,
                validator: (value) => (value ?? '').isEmpty ? l10n.validationPasswordRequired : null,
                onSubmitted: (_) => unawaited(_submit()),
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () => context.push(Routes.forgotPassword),
                  child: Text(l10n.forgotPasswordLink),
                ),
              ),
              if (_error != null) ...[
                _ErrorBanner(message: _error!),
                if (_unconfirmed)
                  TextButton(
                    onPressed: () => context.push(
                      Uri(path: Routes.verifyEmail, queryParameters: {'email': _email.text.trim()}).toString(),
                    ),
                    child: Text(l10n.enterConfirmationCode),
                  ),
                const SizedBox(height: Spacing.sm),
              ],
              FilledButton(
                onPressed: _busy ? null : () => unawaited(_submit()),
                child: _busy
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(l10n.signInAction),
              ),
              const SizedBox(height: Spacing.md),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(l10n.noAccountYet),
                  TextButton(
                    onPressed: () => context.go(
                      Uri(path: Routes.signUp, queryParameters: next == null ? null : {'next': next}).toString(),
                    ),
                    child: Text(l10n.createAccountLink),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(Radii.md)),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.sm),
          child: Row(
            children: [
              Icon(Icons.error_outline_rounded, color: scheme.onErrorContainer),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Exposed for the other auth screens.
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => _ErrorBanner(message: message);
}
