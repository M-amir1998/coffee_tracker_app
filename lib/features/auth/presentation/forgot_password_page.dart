import 'dart:async';

import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/app/routes.dart';
import 'package:coffee_tracker/core/errors/failure_messages.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/features/auth/presentation/auth_layout.dart';
import 'package:coffee_tracker/features/auth/presentation/sign_in_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).requestPasswordReset(_email.text);
      if (!mounted) return;
      context.go(Uri(path: Routes.resetPassword, queryParameters: {'email': _email.text.trim()}).toString());
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
      title: l10n.forgotTitle,
      subtitle: l10n.forgotSubtitle,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(
                labelText: l10n.fieldEmail,
                prefixIcon: const Icon(Icons.mail_outline_rounded),
              ),
              validator: (value) => AuthValidators.email(l10n, value),
              onFieldSubmitted: (_) => unawaited(_submit()),
            ),
            const SizedBox(height: Spacing.md),
            if (_error != null) ...[AuthErrorBanner(message: _error!), const SizedBox(height: Spacing.sm)],
            FilledButton(
              onPressed: _busy ? null : () => unawaited(_submit()),
              child: _busy
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l10n.sendResetCode),
            ),
            const SizedBox(height: Spacing.sm),
            TextButton(onPressed: () => context.go(Routes.signIn), child: Text(l10n.backToSignIn)),
          ],
        ),
      ),
    );
  }
}
