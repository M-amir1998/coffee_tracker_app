import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/features/auth/application/auth_providers.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/notifications/domain/app_notification.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final notificationsProvider = FutureProvider<List<AppNotification>>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return const [];
  ref.watch(dataRevisionProvider);
  return ref.watch(notificationRepositoryProvider).recent();
});

final unreadNotificationsProvider = Provider<int>(
  (ref) => ref.watch(notificationsProvider).value?.where((n) => n.isUnread).length ?? 0,
);
