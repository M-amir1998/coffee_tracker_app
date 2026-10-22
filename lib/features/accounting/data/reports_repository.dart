import 'package:coffee_tracker/core/data/rpc.dart';
import 'package:coffee_tracker/features/accounting/domain/balance_models.dart';
import 'package:coffee_tracker/features/accounting/domain/ledger_models.dart';
import 'package:coffee_tracker/features/analytics/domain/analytics_models.dart';
import 'package:coffee_tracker/features/dashboard/domain/dashboard.dart';
import 'package:coffee_tracker/features/leaderboard/domain/leaderboard_models.dart';
import 'package:coffee_tracker/features/settlements/domain/settlement_planner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cursor for the activity feed: the position of the last item already shown.
class ActivityCursor {
  const ActivityCursor(this.createdAt, this.id);

  final DateTime createdAt;
  final String id;
}

class ActivityFilter {
  const ActivityFilter({this.types, this.memberId, this.from, this.to, this.cycleId, this.statuses});

  final Set<ActivityType>? types;
  final String? memberId;
  final DateTime? from;
  final DateTime? to;
  final String? cycleId;
  final Set<TransactionStatus>? statuses;

  static const none = ActivityFilter();

  bool get isEmpty =>
      (types == null || types!.isEmpty) &&
      memberId == null &&
      from == null &&
      to == null &&
      cycleId == null &&
      statuses == null;

  ActivityFilter copyWith({
    Set<ActivityType>? Function()? types,
    String? Function()? memberId,
    DateTime? Function()? from,
    DateTime? Function()? to,
    String? Function()? cycleId,
    Set<TransactionStatus>? Function()? statuses,
  }) {
    return ActivityFilter(
      types: types == null ? this.types : types(),
      memberId: memberId == null ? this.memberId : memberId(),
      from: from == null ? this.from : from(),
      to: to == null ? this.to : to(),
      cycleId: cycleId == null ? this.cycleId : cycleId(),
      statuses: statuses == null ? this.statuses : statuses(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ActivityFilter &&
      _setEquals(other.types, types) &&
      other.memberId == memberId &&
      other.from == from &&
      other.to == to &&
      other.cycleId == cycleId &&
      _setEquals(other.statuses, statuses);

  @override
  int get hashCode => Object.hash(
    types == null ? null : Object.hashAllUnordered(types!),
    memberId,
    from,
    to,
    cycleId,
    statuses == null ? null : Object.hashAllUnordered(statuses!),
  );

  static bool _setEquals<T>(Set<T>? a, Set<T>? b) =>
      a == null ? b == null : b != null && a.length == b.length && a.containsAll(b);
}

/// Read models. Every aggregate is computed in the database.
class ReportsRepository {
  ReportsRepository(this._client);

  final SupabaseClient _client;

  Future<Dashboard> dashboard(String groupId) async =>
      Dashboard.fromJson(await _client.callJson('get_dashboard', {'p_group_id': groupId}));

  Future<GroupOverview> overview(String groupId, {String? cycleId, bool allTime = false}) async =>
      GroupOverview.fromJson(
        await _client.callJson('get_group_overview', {
          'p_group_id': groupId,
          'p_cycle_id': cycleId,
          'p_all_time': allTime,
        }),
      );

  Future<List<MemberBalance>> memberBalances(String groupId, {String? cycleId, bool allTime = false}) async {
    final rows = await _client.callList('get_member_balances', {
      'p_group_id': groupId,
      'p_cycle_id': cycleId,
      'p_all_time': allTime,
    });
    return rows.map(MemberBalance.fromJson).toList();
  }

  Future<List<ActivityItem>> activity(
    String groupId, {
    ActivityFilter filter = ActivityFilter.none,
    ActivityCursor? before,
    int limit = 30,
  }) async {
    final rows = await _client.callList('get_activity', {
      'p_group_id': groupId,
      'p_limit': limit,
      'p_before_at': before?.createdAt.toUtc().toIso8601String(),
      'p_before_id': before?.id,
      'p_member_id': filter.memberId,
      'p_types': filter.types?.map((t) => t.wireName).toList(),
      'p_from': filter.from?.toUtc().toIso8601String(),
      'p_to': filter.to?.toUtc().toIso8601String(),
      'p_cycle_id': filter.cycleId,
      'p_statuses': filter.statuses?.map((s) => s.name).toList(),
    });
    return rows.map(ActivityItem.fromJson).toList();
  }

  Future<TransactionDetail> transaction(String transactionId) async =>
      TransactionDetail.fromJson(await _client.callJson('get_transaction', {'p_transaction_id': transactionId}));

  Future<PendingActions> pendingActions(String groupId) async =>
      PendingActions.fromJson(await _client.callJson('get_pending_actions', {'p_group_id': groupId}));

  Future<LeaderboardData> leaderboard(String groupId, LeaderboardPeriod period) async => LeaderboardData.fromJson(
    await _client.callJson('get_leaderboard', {'p_group_id': groupId, 'p_period': period.wireName}),
  );

  Future<List<MonthlyAward>> monthlyAwards(String groupId) async {
    final value = await _client.call('get_monthly_awards', {'p_group_id': groupId});
    return ((value as List?) ?? const <Object?>[])
        .map((award) => MonthlyAward.fromJson((award! as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<MyStats> myStats(String groupId) async =>
      MyStats.fromJson(await _client.callJson('get_my_stats', {'p_group_id': groupId}));

  Future<AnalyticsData> analytics(String groupId, DateTime from, DateTime to) async => AnalyticsData.fromJson(
    await _client.callJson('get_analytics', {'p_group_id': groupId, 'p_from': _date(from), 'p_to': _date(to)}),
  );

  Future<List<CycleListItem>> cycles(String groupId) async =>
      (await _client.callList('get_cycles', {'p_group_id': groupId})).map(CycleListItem.fromJson).toList();

  Future<CycleReport> cycleReport(String cycleId) async =>
      CycleReport.fromJson(await _client.callJson('get_cycle_report', {'p_cycle_id': cycleId}));

  Future<CashBoxInfo> cashBox(String groupId) async =>
      CashBoxInfo.fromJson(await _client.callJson('get_cash_box', {'p_group_id': groupId}));

  Future<SettlementInputs> settlementInputs(String groupId) async =>
      SettlementInputs.fromJson(await _client.callJson('get_settlement_inputs', {'p_group_id': groupId}));

  Future<List<AuditEntry>> auditLog(String groupId, {int? beforeId, int limit = 50}) async {
    final rows = await _client.callList('get_audit_log', {
      'p_group_id': groupId,
      'p_before_id': beforeId,
      'p_limit': limit,
    });
    return rows.map(AuditEntry.fromJson).toList();
  }

  Future<List<ExportTransaction>> exportTransactions(String groupId, {DateTime? from, DateTime? to}) async {
    final rows = await _client.callList('export_transactions', {
      'p_group_id': groupId,
      'p_from': from?.toUtc().toIso8601String(),
      'p_to': to?.toUtc().toIso8601String(),
    });
    return rows.map(ExportTransaction.fromJson).toList();
  }

  Future<LedgerIntegrity> verifyIntegrity(String groupId) async =>
      LedgerIntegrity.fromJson(await _client.callJson('verify_ledger_integrity', {'p_group_id': groupId}));

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
