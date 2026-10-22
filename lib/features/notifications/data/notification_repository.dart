import 'package:coffee_tracker/core/data/rpc.dart';
import 'package:coffee_tracker/core/errors/app_failure.dart';
import 'package:coffee_tracker/core/utils/json.dart';
import 'package:coffee_tracker/features/notifications/domain/app_notification.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationRepository {
  NotificationRepository(this._client);

  final SupabaseClient _client;

  /// Most recent notifications of the signed-in user (RLS limits rows to them).
  Future<List<AppNotification>> recent({DateTime? before, int limit = 40}) {
    return guard(() async {
      var query = _client.from('notifications').select();
      if (before != null) query = query.lt('created_at', before.toUtc().toIso8601String());
      final rows = await query.order('created_at', ascending: false).limit(limit);
      return asJsonList(rows).map(AppNotification.fromJson).toList();
    });
  }

  Future<int> markRead([List<String>? ids]) async =>
      ((await _client.call('mark_notifications_read', {'p_ids': ids})) as num?)?.toInt() ?? 0;
}
