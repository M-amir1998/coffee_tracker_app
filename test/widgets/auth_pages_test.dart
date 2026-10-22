import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/core/errors/app_failure.dart';
import 'package:coffee_tracker/features/auth/presentation/sign_in_page.dart';
import 'package:coffee_tracker/features/auth/presentation/sign_up_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/samples.dart';
import '../helpers/test_app.dart';

void main() {
  late FakeAuthRepository auth;

  setUp(() => auth = FakeAuthRepository());

  Future<void> pump(WidgetTester tester, Widget page, {Size size = phone}) async {
    setScreenSize(tester, size);
    await tester.pumpWidget(testApp(page, overrides: [authRepositoryProvider.overrideWithValue(auth)]));
    await tester.pumpAndSettle();
  }

  group('sign in', () {
    testWidgets('validates the form before calling the server', (tester) async {
      await pump(tester, const SignInPage());
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your email address.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
      expect(auth.signIns, isEmpty);

      await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'not-an-email');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email address.'), findsOneWidget);
    });

    testWidgets('signs in with the trimmed email', (tester) async {
      await pump(tester, const SignInPage());
      await tester.enterText(find.widgetWithText(TextFormField, 'Email'), '  alice@lab.org ');
      await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'coffee123');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(auth.signIns, [('alice@lab.org', 'coffee123')]);
    });

    testWidgets('explains failures in plain language', (tester) async {
      auth.failWith = const AuthFailure('invalid_credentials');
      await pump(tester, const SignInPage());
      await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'alice@lab.org');
      await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'wrong');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('The email or password is not correct.'), findsOneWidget);
    });

    testWidgets('offers the confirmation code when the email is unconfirmed', (tester) async {
      auth.failWith = const AuthFailure('email_not_confirmed');
      await pump(tester, const SignInPage());
      await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'alice@lab.org');
      await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'coffee123');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Enter my confirmation code'), findsOneWidget);
    });

    testWidgets('uses the two-pane layout on wide screens', (tester) async {
      await pump(tester, const SignInPage(), size: desktop);
      expect(find.text('Coffee, shared fairly.'), findsOneWidget);
    });
  });

  group('sign up', () {
    testWidgets('enforces the password policy of the server', (tester) async {
      await pump(tester, const SignUpPage());
      await tester.enterText(find.widgetWithText(TextFormField, 'Display name'), 'Alice');
      await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'alice@lab.org');
      await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'short');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();
      expect(find.text('Use at least 8 characters.'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'onlyletters');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();
      expect(find.text('Use both letters and digits.'), findsOneWidget);
    });

    testWidgets('requires a display name', (tester) async {
      await pump(tester, const SignUpPage());
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name.'), findsOneWidget);
    });
  });
}
