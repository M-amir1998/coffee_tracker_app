import 'dart:async';

import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/app/routes.dart';
import 'package:coffee_tracker/core/errors/failure_messages.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/features/auth/data/auth_repository.dart';
import 'package:coffee_tracker/features/auth/presentation/auth_layout.dart';
import 'package:coffee_tracker/features/auth/presentation/sign_in_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class SignUpPage extends ConsumerStatefulWidget {
  const SignUpPage({super.key, this.next});

  final String? next;

  @override
  ConsumerState<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends ConsumerState<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final outcome = await ref
          .read(authRepositoryProvider)
          .signUp(email: _email.text, password: _password.text, displayName: _name.text);
      if (!mounted) return;
      if (outcome == SignUpOutcome.confirmationRequired) {
        context.go(Uri(path: Routes.verifyEmail, queryParameters: {'email': _email.text.trim()}).toString());
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = describeFailure(context.l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AuthLayout(
      title: l10n.signUpTitle,
      subtitle: l10n.signUpSubtitle,
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.nickname, AutofillHints.name],
                textInputAction: TextInputAction.next,
                maxLength: 40,
                decoration: InputDecoration(
                  labelText: l10n.fieldDisplayName,
                  helperText: l10n.displayNameHelper,
                  prefixIcon: const Icon(Icons.badge_outlined),
                ),
                validator: (value) => (value?.trim().isEmpty ?? true) ? l10n.validationNameRequired : null,
              ),
              const SizedBox(height: Spacing.sm),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: l10n.fieldEmail, prefixIcon: const Icon(Icons.mail_outline_rounded)),
                validator: (value) => AuthValidators.email(l10n, value),
              ),
              const SizedBox(height: Spacing.md),
              PasswordField(
                controller: _password,
                label: l10n.fieldPassword,
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
                    : Text(l10n.signUpAction),
              ),
              const SizedBox(height: Spacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(child: Text(l10n.alreadyHaveAccount)),
                  TextButton(
                    onPressed: () => context.go(
                      Uri(path: Routes.signIn, queryParameters: widget.next == null ? null : {'next': widget.next}).toString(),
                    ),
                    child: Text(l10n.signInLink),
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
