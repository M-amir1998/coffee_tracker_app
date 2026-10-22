import 'package:coffee_tracker/core/errors/app_failure.dart';
import 'package:coffee_tracker/core/utils/json.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

const _timeout = Duration(seconds: 20);
const _uuid = Uuid();

/// A fresh idempotency key for one user action. Retries of the same action
/// must reuse the key so the server records it only once.
String newIdempotencyKey() => _uuid.v4();

/// Thin wrapper around PostgREST RPC calls with timeouts and error mapping.
extension Rpc on SupabaseClient {
  Future<Object?> call(String function, [Map<String, Object?>? params]) =>
      guard(() => rpc<dynamic>(function, params: _clean(params)).timeout(_timeout));

  Future<Json> callJson(String function, [Map<String, Object?>? params]) async =>
      asJson(await call(function, params));

  Future<List<Json>> callList(String function, [Map<String, Object?>? params]) async =>
      asJsonList(await call(function, params));
}

/// Omits null values so that the database defaults apply.
Map<String, Object?>? _clean(Map<String, Object?>? params) {
  if (params == null) return null;
  return {
    for (final entry in params.entries)
      if (entry.value != null) entry.key: entry.value,
  };
}
