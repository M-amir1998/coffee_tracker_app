import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Failures the UI knows how to explain. Repositories translate every
/// exception into one of these so widgets never see raw backend errors.
sealed class AppFailure implements Exception {
  const AppFailure();

  /// Whether retrying the same request later may succeed.
  bool get isRetryable => false;
}

/// No connection, DNS failure, timeout or server unavailable.
class NetworkFailure extends AppFailure {
  const NetworkFailure([this.cause]);
  final Object? cause;

  @override
  bool get isRetryable => true;

  @override
  String toString() => 'NetworkFailure($cause)';
}

/// The session expired or was revoked; the user must sign in again.
class SessionExpiredFailure extends AppFailure {
  const SessionExpiredFailure();
}

/// A business rule enforced by the database (e.g. `insufficient_cash`).
class RuleFailure extends AppFailure {
  const RuleFailure(this.code, [this.detail]);

  /// Stable machine-readable key raised by the database functions.
  final String code;

  /// English explanation from the server, used when no translation exists.
  final String? detail;

  @override
  String toString() => 'RuleFailure($code: $detail)';
}

/// The database refused access (RLS / privileges).
class PermissionFailure extends AppFailure {
  const PermissionFailure();
}

/// Errors from Supabase Auth (sign-in, sign-up, verification).
class AuthFailure extends AppFailure {
  const AuthFailure(this.code, [this.message]);

  final String code;
  final String? message;

  @override
  bool get isRetryable => code == 'over_request_rate_limit';

  @override
  String toString() => 'AuthFailure($code: $message)';
}

class UnexpectedFailure extends AppFailure {
  const UnexpectedFailure(this.error);
  final Object error;

  @override
  String toString() => 'UnexpectedFailure($error)';
}

/// Maps any thrown object to an [AppFailure].
AppFailure toFailure(Object error) {
  if (error is AppFailure) return error;
  if (error is PostgrestException) return _fromPostgrest(error);
  if (error is AuthException) return _fromAuth(error);
  if (error is StorageException) {
    if (error.statusCode == '403' || error.statusCode == '401') return const PermissionFailure();
    return UnexpectedFailure(error);
  }
  if (error is TimeoutException) return NetworkFailure(error);
  if (_looksLikeNetworkError(error)) return NetworkFailure(error);
  return UnexpectedFailure(error);
}

AppFailure _fromPostgrest(PostgrestException error) {
  final code = error.code;
  if (code == 'P0001') return RuleFailure(error.message, error.details?.toString());
  if (code == '42501') return const PermissionFailure();
  if (code == 'PGRST301' || code == 'PGRST303') return const SessionExpiredFailure();
  final status = int.tryParse(code ?? '');
  if (status != null && status >= 500) return NetworkFailure(error);
  return UnexpectedFailure(error);
}

AppFailure _fromAuth(AuthException error) {
  if (error is AuthRetryableFetchException) return NetworkFailure(error);
  if (error is AuthSessionMissingException) return const SessionExpiredFailure();
  final code = error.code ?? _authCodeFromStatus(error.statusCode);
  return AuthFailure(code, error.message);
}

String _authCodeFromStatus(String? status) => switch (status) {
  '429' => 'over_request_rate_limit',
  '422' => 'validation_failed',
  _ => 'unknown',
};

bool _looksLikeNetworkError(Object error) {
  // Avoid importing dart:io so the check also works on the web.
  final type = error.runtimeType.toString();
  return type.contains('SocketException') ||
      type.contains('ClientException') ||
      type.contains('HandshakeException') ||
      type.contains('HttpException') ||
      type.contains('WebSocketChannelException');
}

/// Runs [action] and rethrows any error as an [AppFailure].
Future<T> guard<T>(Future<T> Function() action) async {
  try {
    return await action();
  } catch (error, stackTrace) {
    Error.throwWithStackTrace(toFailure(error), stackTrace);
  }
}
