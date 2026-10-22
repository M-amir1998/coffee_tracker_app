import 'dart:async';

import 'package:coffee_tracker/app/core_providers.dart';
import 'package:coffee_tracker/features/auth/application/auth_providers.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Subscribes to changes of the current group (and the user's notifications)
/// while the app shell is visible. Events only trigger a debounced refetch of
/// the aggregates; the payloads themselves are not trusted for display.
final realtimeSyncProvider = Provider.autoDispose.family<void, String>((ref, groupId) {
  final client = ref.watch(supabaseClientProvider);
  final userId = ref.watch(currentUserIdProvider);
  Timer? debounce;

  void onChange(PostgresChangePayload _) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 700), () {
      if (ref.mounted) ref.read(dataRevisionProvider.notifier).bump();
    });
  }

  final channel = client.channel('group:$groupId');
  for (final table in const ['transactions', 'accounting_cycles', 'group_members', 'coffee_prices']) {
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: table,
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'group_id', value: groupId),
      callback: onChange,
    );
  }
  if (userId != null) {
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'notifications',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: userId),
      callback: onChange,
    );
  }
  channel.subscribe();

  ref.onDispose(() {
    debounce?.cancel();
    unawaited(client.removeChannel(channel));
  });
});
