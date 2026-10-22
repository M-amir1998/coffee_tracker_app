import 'package:coffee_tracker/core/config/app_config.dart';
import 'package:coffee_tracker/core/errors/app_failure.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Outcome of a sign-up. With email confirmation enabled there is no session
/// until the address is verified.
enum SignUpOutcome { signedIn, confirmationRequired }

class AuthRepository {
  AuthRepository(this._client, this._config);

  final SupabaseClient _client;
  final AppConfig _config;

  GoTrueClient get _auth => _client.auth;

  Stream<AuthState> authStateChanges() => _auth.onAuthStateChange;

  Session? get currentSession => _auth.currentSession;

  User? get currentUser => _auth.currentUser;

  /// Where email links send the user back to, or null on desktop where the
  /// six-digit code is used instead.
  String? get emailRedirectUrl {
    if (kIsWeb) {
      return _config.webRedirectUrl.isNotEmpty ? _config.webRedirectUrl : Uri.base.origin;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => AppConfig.mobileRedirectUrl,
      _ => null,
    };
  }

  Future<void> signIn({required String email, required String password}) =>
      guard(() => _auth.signInWithPassword(email: email.trim(), password: password));

  Future<SignUpOutcome> signUp({required String email, required String password, required String displayName}) {
    return guard(() async {
      final response = await _auth.signUp(
        email: email.trim(),
        password: password,
        data: {'display_name': displayName.trim()},
        emailRedirectTo: emailRedirectUrl,
      );
      return response.session == null ? SignUpOutcome.confirmationRequired : SignUpOutcome.signedIn;
    });
  }

  Future<void> verifySignUpCode({required String email, required String code}) =>
      guard(() => _auth.verifyOTP(type: OtpType.signup, email: email.trim(), token: code.trim()));

  Future<void> resendConfirmation(String email) =>
      guard(() => _auth.resend(type: OtpType.signup, email: email.trim(), emailRedirectTo: emailRedirectUrl));

  Future<void> requestPasswordReset(String email) =>
      guard(() => _auth.resetPasswordForEmail(email.trim(), redirectTo: emailRedirectUrl));

  /// Verifies the recovery code from the email, which signs the user in so
  /// that the password can be changed.
  Future<void> verifyRecoveryCode({required String email, required String code}) =>
      guard(() => _auth.verifyOTP(type: OtpType.recovery, email: email.trim(), token: code.trim()));

  Future<void> updatePassword(String password) => guard(() => _auth.updateUser(UserAttributes(password: password)));

  Future<void> signOut() => guard(() => _auth.signOut());
}
