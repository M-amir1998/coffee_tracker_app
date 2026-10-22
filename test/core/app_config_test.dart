import 'dart:convert';

import 'package:coffee_tracker/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

String _jwt(Map<String, Object?> payload) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part(payload)}.signature';
}

AppConfig _config({
  String url = 'https://abc.supabase.co',
  String key = 'sb_publishable_abc',
  String environment = 'production',
}) => AppConfig(supabaseUrl: url, supabasePublishableKey: key, environment: environment, webRedirectUrl: '');

void main() {
  test('a complete production configuration is valid', () {
    expect(_config().problems, isEmpty);
  });

  test('missing or malformed values are reported', () {
    expect(_config(url: '').problems, ['SUPABASE_URL is not set.']);
    expect(_config(url: 'not a url').problems, ['SUPABASE_URL is not a valid URL.']);
    expect(_config(key: '').problems, ['SUPABASE_PUBLISHABLE_KEY is not set.']);
  });

  test('production requires https while development allows a local stack', () {
    expect(_config(url: 'http://127.0.0.1:54321').problems, ['Production builds must use an https Supabase URL.']);
    expect(_config(url: 'http://127.0.0.1:54321', environment: 'development').problems, isEmpty);
  });

  test('secret keys are refused in every environment', () {
    for (final environment in ['development', 'production']) {
      expect(_config(key: 'sb_secret_abc', environment: environment).isValid, isFalse);
      expect(_config(key: _jwt({'role': 'service_role'}), environment: environment).isValid, isFalse);
      expect(_config(key: _jwt({'role': 'anon'}), environment: environment).isValid, isTrue);
      expect(_config(key: 'not.a.jwt', environment: environment).isValid, isTrue);
    }
  });
}
