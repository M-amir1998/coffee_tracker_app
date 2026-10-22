import 'dart:async';

import 'package:coffee_tracker/core/errors/app_failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('database rule errors keep their key and detail', () {
    final failure = toFailure(
      const PostgrestException(
        message: 'insufficient_cash',
        code: 'P0001',
        details: 'The cash box does not contain enough.',
      ),
    );
    expect(failure, isA<RuleFailure>());
    expect((failure as RuleFailure).code, 'insufficient_cash');
    expect(failure.detail, 'The cash box does not contain enough.');
    expect(failure.isRetryable, isFalse);
  });

  test('privilege errors become permission failures', () {
    expect(toFailure(const PostgrestException(message: 'permission denied', code: '42501')), isA<PermissionFailure>());
  });

  test('expired JWTs become session failures', () {
    expect(toFailure(const PostgrestException(message: 'JWT expired', code: 'PGRST303')), isA<SessionExpiredFailure>());
  });

  test('auth errors keep their code', () {
    final failure = toFailure(
      const AuthApiException('Invalid login credentials', statusCode: '400', code: 'invalid_credentials'),
    );
    expect(failure, isA<AuthFailure>());
    expect((failure as AuthFailure).code, 'invalid_credentials');
  });

  test('connection problems are retryable network failures', () {
    expect(toFailure(http.ClientException('Failed host lookup')), isA<NetworkFailure>());
    expect(toFailure(TimeoutException('slow')), isA<NetworkFailure>());
    expect(toFailure(http.ClientException('x')).isRetryable, isTrue);
  });

  test('anything else is unexpected', () {
    expect(toFailure(StateError('boom')), isA<UnexpectedFailure>());
  });

  test('guard converts thrown errors', () async {
    await expectLater(
      guard<void>(() async => throw const PostgrestException(message: 'not_member', code: 'P0001')),
      throwsA(isA<RuleFailure>().having((f) => f.code, 'code', 'not_member')),
    );
  });
}
