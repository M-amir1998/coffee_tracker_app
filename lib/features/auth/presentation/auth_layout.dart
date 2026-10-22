import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/app_theme.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/features/shell/presentation/app_logo.dart';
import 'package:material_ui/material_ui.dart';

/// Shared frame of the authentication screens: a centered form on phones and
/// a branded two-pane layout on wide screens.
class AuthLayout extends StatelessWidget {
  const AuthLayout({required this.title, required this.child, super.key, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final wide = WindowSize.of(context).isAtLeastExpanded;
    final form = _FormColumn(title: title, subtitle: subtitle, child: child);
    return Scaffold(
      body: SafeArea(
        child: wide
            ? Row(
                children: [
                  const Expanded(flex: 5, child: _BrandPanel()),
                  Expanded(flex: 4, child: form),
                ],
              )
            : form,
      ),
    );
  }
}

class _FormColumn extends StatelessWidget {
  const _FormColumn({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!WindowSize.of(context).isAtLeastExpanded) ...[
                const Align(alignment: Alignment.centerLeft, child: AppLogo(size: 56)),
                const SizedBox(height: Spacing.lg),
              ],
              Semantics(header: true, child: Text(title, style: theme.textTheme.headlineMedium)),
              if (subtitle != null) ...[
                const SizedBox(height: Spacing.xs),
                Text(subtitle!, style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
              const SizedBox(height: Spacing.lg),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A2F26), Palette.espresso, Palette.deepCoffee],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppLogo(size: 64),
            const Spacer(),
            Text(
              l10n.authBrandHeadline,
              style: text.displaySmall?.copyWith(color: Palette.cream, fontFamily: AppTheme.displayFont),
            ),
            const SizedBox(height: Spacing.md),
            Text(
              l10n.authBrandBody,
              style: text.bodyLarge?.copyWith(color: Palette.cream.withValues(alpha: 0.82)),
            ),
            const SizedBox(height: Spacing.xl),
            for (final line in [l10n.authBrandPoint1, l10n.authBrandPoint2, l10n.authBrandPoint3])
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.sm),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Palette.caramel, size: 20),
                    const SizedBox(width: Spacing.sm),
                    Expanded(child: Text(line, style: text.bodyLarge?.copyWith(color: Palette.cream))),
                  ],
                ),
              ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

/// Password field with a visibility toggle.
class PasswordField extends StatefulWidget {
  const PasswordField({
    required this.controller,
    required this.label,
    super.key,
    this.validator,
    this.autofillHints = const [AutofillHints.password],
    this.onSubmitted,
    this.textInputAction = TextInputAction.done,
  });

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String>? validator;
  final Iterable<String> autofillHints;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction textInputAction;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscured,
      autofillHints: widget.autofillHints,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onSubmitted,
      validator: widget.validator,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.lock_outline_rounded),
        suffixIcon: IconButton(
          tooltip: _obscured ? l10n.showPassword : l10n.hidePassword,
          icon: Icon(_obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _obscured = !_obscured),
        ),
      ),
    );
  }
}

abstract final class AuthValidators {
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? email(AppLocalizations l10n, String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return l10n.validationEmailRequired;
    if (!_email.hasMatch(text)) return l10n.validationEmailInvalid;
    return null;
  }

  /// Mirrors the server policy: at least 8 characters with letters and digits.
  static String? newPassword(AppLocalizations l10n, String? value) {
    final text = value ?? '';
    if (text.length < 8) return l10n.validationPasswordLength;
    if (!RegExp('[A-Za-z]').hasMatch(text) || !RegExp(r'\d').hasMatch(text)) return l10n.validationPasswordMix;
    return null;
  }

  static String? code(AppLocalizations l10n, String? value) {
    final text = value?.replaceAll(RegExp(r'\s'), '') ?? '';
    if (!RegExp(r'^\d{6}$').hasMatch(text)) return l10n.validationCode;
    return null;
  }
}
