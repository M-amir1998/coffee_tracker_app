import 'package:coffee_tracker/core/data/rpc.dart';
import 'package:coffee_tracker/core/errors/app_failure.dart';
import 'package:coffee_tracker/core/utils/json.dart';
import 'package:coffee_tracker/features/groups/domain/group_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Groups, membership, invitations, prices and group settings.
class GroupRepository {
  GroupRepository(this._client);

  final SupabaseClient _client;

  Future<List<GroupSummary>> myGroups() async =>
      (await _client.callList('get_my_groups')).map(GroupSummary.fromJson).toList();

  Future<String> createGroup({
    required String name,
    required String firstCycleName,
    required int coffeePriceCents,
    required String timezone,
  }) async {
    final id = await _client.call('create_group', {
      'p_name': name,
      'p_first_cycle_name': firstCycleName,
      'p_coffee_price_cents': coffeePriceCents,
      'p_timezone': timezone,
    });
    return id! as String;
  }

  Future<InvitationPreview> previewInvitation(String code) async =>
      InvitationPreview.fromJson(await _client.callJson('preview_invitation', {'p_code': code}));

  Future<String> joinGroup(String code) async => (await _client.call('join_group', {'p_code': code}))! as String;

  Future<void> leaveGroup(String groupId) => _client.call('leave_group', {'p_group_id': groupId});

  Future<List<Member>> members(String groupId, {bool includeInactive = false}) async {
    final rows = await _client.callList('get_members', {'p_group_id': groupId, 'p_include_inactive': includeInactive});
    return rows.map(Member.fromJson).toList();
  }

  Future<void> setMemberRole(String groupId, String userId, MemberRole role) =>
      _client.call('set_member_role', {'p_group_id': groupId, 'p_user_id': userId, 'p_role': role.name});

  Future<void> removeMember(String groupId, String userId, {String? note}) =>
      _client.call('remove_member', {'p_group_id': groupId, 'p_user_id': userId, 'p_note': note});

  Future<List<Invitation>> invitations(String groupId) {
    return guard(() async {
      final rows = await _client
          .from('invitations')
          .select()
          .eq('group_id', groupId)
          .order('created_at', ascending: false)
          .limit(50);
      return asJsonList(rows).map(Invitation.fromJson).toList();
    });
  }

  Future<Invitation> createInvitation(
    String groupId, {
    MemberRole role = MemberRole.member,
    int? maxUses,
    int? expiresInDays = 14,
  }) async {
    final json = await _client.callJson('create_invitation', {
      'p_group_id': groupId,
      'p_role': role.name,
      'p_max_uses': maxUses,
      'p_expires_in_days': expiresInDays,
    });
    return Invitation.fromJson({...json, 'use_count': 0});
  }

  Future<void> revokeInvitation(String invitationId) =>
      _client.call('revoke_invitation', {'p_invitation_id': invitationId});

  Future<List<CoffeePrice>> prices(String groupId) {
    return guard(() async {
      final rows = await _client
          .from('coffee_prices')
          .select('id, price_cents, effective_from')
          .eq('group_id', groupId)
          .order('effective_from', ascending: false)
          .limit(50);
      return asJsonList(rows).map(CoffeePrice.fromJson).toList();
    });
  }

  Future<void> setCoffeePrice(String groupId, int priceCents, {DateTime? effectiveFrom}) => _client.call(
    'set_coffee_price',
    {'p_group_id': groupId, 'p_price_cents': priceCents, 'p_effective_from': effectiveFrom?.toUtc().toIso8601String()},
  );

  Future<void> cancelScheduledPrice(String priceId) => _client.call('cancel_scheduled_price', {'p_price_id': priceId});

  Future<void> updateSettings(
    String groupId, {
    String? name,
    String? timezone,
    bool? requireDepositConfirmation,
    bool? requirePurchaseApproval,
    int? undoWindowMinutes,
  }) => _client.call('update_group_settings', {
    'p_group_id': groupId,
    'p_name': name,
    'p_timezone': timezone,
    'p_require_deposit_confirmation': requireDepositConfirmation,
    'p_require_purchase_approval': requirePurchaseApproval,
    'p_member_undo_window_minutes': undoWindowMinutes,
  });

  Future<List<String>> timezones() async {
    final rows = await _client.call('list_timezones');
    return ((rows as List?) ?? const <Object?>[]).map((value) => value! as String).toList();
  }
}
