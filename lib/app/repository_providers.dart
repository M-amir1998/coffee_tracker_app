import 'package:coffee_tracker/app/core_providers.dart';
import 'package:coffee_tracker/features/accounting/data/ledger_repository.dart';
import 'package:coffee_tracker/features/accounting/data/reports_repository.dart';
import 'package:coffee_tracker/features/auth/data/auth_repository.dart';
import 'package:coffee_tracker/features/groups/data/group_repository.dart';
import 'package:coffee_tracker/features/notifications/data/notification_repository.dart';
import 'package:coffee_tracker/features/profile/data/profile_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseClientProvider), ref.watch(appConfigProvider)),
);

final groupRepositoryProvider = Provider<GroupRepository>((ref) => GroupRepository(ref.watch(supabaseClientProvider)));

final ledgerRepositoryProvider = Provider<LedgerRepository>(
  (ref) => LedgerRepository(ref.watch(supabaseClientProvider)),
);

final reportsRepositoryProvider = Provider<ReportsRepository>(
  (ref) => ReportsRepository(ref.watch(supabaseClientProvider)),
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(supabaseClientProvider)),
);

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(ref.watch(supabaseClientProvider)),
);
