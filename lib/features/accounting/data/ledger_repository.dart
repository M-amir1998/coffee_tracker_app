import 'package:coffee_tracker/core/data/rpc.dart';
import 'package:coffee_tracker/core/utils/json.dart';
import 'package:coffee_tracker/features/accounting/domain/balance_models.dart';
import 'package:coffee_tracker/features/accounting/domain/ledger_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum PurchaseFunding {
  personal('personal'),
  cashBox('cash_box');

  const PurchaseFunding(this.wireName);

  final String wireName;
}

/// Every balance-changing operation. All of them are idempotent: pass the same
/// [idempotencyKey] when retrying a request.
class LedgerRepository {
  LedgerRepository(this._client);

  final SupabaseClient _client;

  Future<TransactionResult> _result(String function, Map<String, Object?> params) async =>
      TransactionResult.fromJson(await _client.callJson(function, params));

  Future<TransactionResult> recordCoffee({
    required String groupId,
    required String idempotencyKey,
    int quantity = 1,
    DateTime? occurredAt,
    String? forMemberId,
  }) => _result('record_coffee', {
    'p_group_id': groupId,
    'p_idempotency_key': idempotencyKey,
    'p_quantity': quantity,
    'p_occurred_at': occurredAt?.toUtc().toIso8601String(),
    'p_member_id': forMemberId,
  });

  Future<TransactionResult> undoCoffee(String transactionId) =>
      _result('undo_coffee', {'p_transaction_id': transactionId, 'p_idempotency_key': newIdempotencyKey()});

  Future<TransactionResult> submitDeposit({
    required String groupId,
    required int amountCents,
    required String idempotencyKey,
    String? description,
    String? forMemberId,
  }) => _result('submit_deposit', {
    'p_group_id': groupId,
    'p_amount_cents': amountCents,
    'p_idempotency_key': idempotencyKey,
    'p_description': description,
    'p_member_id': forMemberId,
  });

  Future<TransactionResult> submitPurchase({
    required String groupId,
    required PurchaseFunding funding,
    required int amountCents,
    required String description,
    required String idempotencyKey,
    DateTime? purchasedAt,
    String? evidencePath,
    String? forMemberId,
  }) => _result('submit_purchase', {
    'p_group_id': groupId,
    'p_funding': funding.wireName,
    'p_amount_cents': amountCents,
    'p_description': description,
    'p_idempotency_key': idempotencyKey,
    'p_purchased_at': purchasedAt?.toUtc().toIso8601String(),
    'p_evidence_path': evidencePath,
    'p_member_id': forMemberId,
  });

  Future<TransactionResult> recordTransfer({
    required String groupId,
    required String fromMemberId,
    required String toMemberId,
    required int amountCents,
    required String idempotencyKey,
    String? description,
    bool adminOverride = false,
  }) => _result('record_transfer', {
    'p_group_id': groupId,
    'p_from_member_id': fromMemberId,
    'p_to_member_id': toMemberId,
    'p_amount_cents': amountCents,
    'p_idempotency_key': idempotencyKey,
    'p_description': description,
    'p_admin_override': adminOverride,
  });

  Future<TransactionResult> recordReimbursement({
    required String groupId,
    required String memberId,
    required int amountCents,
    required String idempotencyKey,
    String? description,
  }) => _result('record_reimbursement', {
    'p_group_id': groupId,
    'p_member_id': memberId,
    'p_amount_cents': amountCents,
    'p_idempotency_key': idempotencyKey,
    'p_description': description,
  });

  Future<TransactionResult> respond(String transactionId, {required bool approve, String? note}) =>
      _result('respond_to_transaction', {'p_transaction_id': transactionId, 'p_approve': approve, 'p_note': note});

  Future<TransactionResult> cancel(String transactionId, {String? note}) =>
      _result('cancel_transaction', {'p_transaction_id': transactionId, 'p_note': note});

  Future<TransactionResult> dispute(String transactionId, String note) =>
      _result('dispute_transaction', {'p_transaction_id': transactionId, 'p_note': note});

  Future<TransactionResult> resolveDispute(String transactionId, {required bool approve, required String note}) =>
      _result('resolve_dispute', {'p_transaction_id': transactionId, 'p_approve': approve, 'p_note': note});

  Future<TransactionResult> reverse(String transactionId, {required String note, required String idempotencyKey}) =>
      _result('reverse_transaction', {
        'p_transaction_id': transactionId,
        'p_note': note,
        'p_idempotency_key': idempotencyKey,
      });

  /// [direction] +1 charges the member, -1 credits them.
  Future<TransactionResult> adjustBalance({
    required String groupId,
    required String memberId,
    required int direction,
    required int amountCents,
    required String note,
    required String idempotencyKey,
  }) => _result('record_balance_adjustment', {
    'p_group_id': groupId,
    'p_member_id': memberId,
    'p_direction': direction,
    'p_amount_cents': amountCents,
    'p_note': note,
    'p_idempotency_key': idempotencyKey,
  });

  Future<ReconciliationResult> reconcileCashBox({
    required String groupId,
    required int countedCents,
    required String idempotencyKey,
    String? note,
    bool applyAdjustment = true,
  }) async {
    final json = await _client.callJson('reconcile_cash_box', {
      'p_group_id': groupId,
      'p_counted_cents': countedCents,
      'p_idempotency_key': idempotencyKey,
      'p_note': note,
      'p_apply_adjustment': applyAdjustment,
    });
    return ReconciliationResult.fromJson(json);
  }

  /// Closes the open cycle (typed confirmation required) and opens the next.
  Future<String> closeCycle({
    required String groupId,
    required String cycleId,
    required String confirmation,
    required String nextCycleName,
    String? note,
  }) async {
    final Json json = await _client.callJson('close_cycle', {
      'p_group_id': groupId,
      'p_cycle_id': cycleId,
      'p_confirmation': confirmation,
      'p_next_cycle_name': nextCycleName,
      'p_note': note,
    });
    return json.str('new_cycle_id');
  }
}
