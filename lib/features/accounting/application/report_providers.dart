import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/features/accounting/data/reports_repository.dart';
import 'package:coffee_tracker/features/accounting/domain/balance_models.dart';
import 'package:coffee_tracker/features/accounting/domain/ledger_models.dart';
import 'package:coffee_tracker/features/analytics/domain/analytics_models.dart';
import 'package:coffee_tracker/features/dashboard/domain/dashboard.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/leaderboard/domain/leaderboard_models.dart';
import 'package:coffee_tracker/features/settlements/domain/settlement_planner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Scope of group figures: one cycle (null = the open one) or all time.
typedef BalanceScope = ({String groupId, String? cycleId, bool allTime});

final dashboardProvider = FutureProvider.autoDispose.family<Dashboard, String>((ref, groupId) {
  ref.watch(dataRevisionProvider);
  return ref.watch(reportsRepositoryProvider).dashboard(groupId);
});

final overviewProvider = FutureProvider.autoDispose.family<GroupOverview, BalanceScope>((ref, scope) {
  ref.watch(dataRevisionProvider);
  return ref
      .watch(reportsRepositoryProvider)
      .overview(scope.groupId, cycleId: scope.cycleId, allTime: scope.allTime);
});

final memberBalancesProvider = FutureProvider.autoDispose.family<List<MemberBalance>, BalanceScope>((ref, scope) {
  ref.watch(dataRevisionProvider);
  return ref
      .watch(reportsRepositoryProvider)
      .memberBalances(scope.groupId, cycleId: scope.cycleId, allTime: scope.allTime);
});

final pendingActionsProvider = FutureProvider.autoDispose.family<PendingActions, String>((ref, groupId) {
  ref.watch(dataRevisionProvider);
  return ref.watch(reportsRepositoryProvider).pendingActions(groupId);
});

final transactionDetailProvider = FutureProvider.autoDispose.family<TransactionDetail, String>((ref, id) {
  ref.watch(dataRevisionProvider);
  return ref.watch(reportsRepositoryProvider).transaction(id);
});

final leaderboardProvider = FutureProvider.autoDispose
    .family<LeaderboardData, ({String groupId, LeaderboardPeriod period})>((ref, args) {
      ref.watch(dataRevisionProvider);
      return ref.watch(reportsRepositoryProvider).leaderboard(args.groupId, args.period);
    });

final monthlyAwardsProvider = FutureProvider.autoDispose.family<List<MonthlyAward>, String>((ref, groupId) {
  return ref.watch(reportsRepositoryProvider).monthlyAwards(groupId);
});

final myStatsProvider = FutureProvider.autoDispose.family<MyStats, String>((ref, groupId) {
  ref.watch(dataRevisionProvider);
  return ref.watch(reportsRepositoryProvider).myStats(groupId);
});

final analyticsProvider = FutureProvider.autoDispose
    .family<AnalyticsData, ({String groupId, DateTime from, DateTime to})>((ref, args) {
      ref.watch(dataRevisionProvider);
      return ref.watch(reportsRepositoryProvider).analytics(args.groupId, args.from, args.to);
    });

final cyclesProvider = FutureProvider.autoDispose.family<List<CycleListItem>, String>((ref, groupId) {
  ref.watch(dataRevisionProvider);
  return ref.watch(reportsRepositoryProvider).cycles(groupId);
});

final cycleReportProvider = FutureProvider.autoDispose.family<CycleReport, String>((ref, cycleId) {
  ref.watch(dataRevisionProvider);
  return ref.watch(reportsRepositoryProvider).cycleReport(cycleId);
});

final cashBoxProvider = FutureProvider.autoDispose.family<CashBoxInfo, String>((ref, groupId) {
  ref.watch(dataRevisionProvider);
  return ref.watch(reportsRepositoryProvider).cashBox(groupId);
});

final settlementInputsProvider = FutureProvider.autoDispose.family<SettlementInputs, String>((ref, groupId) {
  ref.watch(dataRevisionProvider);
  return ref.watch(reportsRepositoryProvider).settlementInputs(groupId);
});

class ActivityFeedPage {
  const ActivityFeedPage({required this.items, required this.hasMore, this.loadingMore = false, this.loadMoreError});

  final List<ActivityItem> items;
  final bool hasMore;
  final bool loadingMore;

  /// Set when loading the next page failed; the loaded items stay visible.
  final Object? loadMoreError;
}

typedef ActivityArgs = ({String groupId, ActivityFilter filter});

/// Paginated activity feed. Refetches the first page when data changes.
final activityFeedProvider = AsyncNotifierProvider.autoDispose.family<ActivityFeed, ActivityFeedPage, ActivityArgs>(
  ActivityFeed.new,
);

class ActivityFeed extends AsyncNotifier<ActivityFeedPage> {
  ActivityFeed(this.args);

  static const pageSize = 30;

  final ActivityArgs args;

  @override
  Future<ActivityFeedPage> build() async {
    ref.watch(dataRevisionProvider);
    final items = await ref.watch(reportsRepositoryProvider).activity(args.groupId, filter: args.filter, limit: pageSize);
    return ActivityFeedPage(items: items, hasMore: items.length == pageSize);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore || current.items.isEmpty) return;
    state = AsyncData(ActivityFeedPage(items: current.items, hasMore: true, loadingMore: true));
    final last = current.items.last;
    try {
      final next = await ref
          .read(reportsRepositoryProvider)
          .activity(
            args.groupId,
            filter: args.filter,
            before: ActivityCursor(last.createdAt, last.id),
            limit: pageSize,
          );
      if (!ref.mounted) return;
      state = AsyncData(ActivityFeedPage(items: [...current.items, ...next], hasMore: next.length == pageSize));
    } catch (error) {
      if (!ref.mounted) return;
      state = AsyncData(ActivityFeedPage(items: current.items, hasMore: true, loadMoreError: error));
    }
  }
}
