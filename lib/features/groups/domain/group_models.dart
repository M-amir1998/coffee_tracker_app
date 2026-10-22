import 'package:coffee_tracker/core/utils/json.dart';

enum MemberRole {
  member,
  treasurer,
  admin;

  static MemberRole parse(String value) => MemberRole.values.byName(value);

  bool get isAdmin => this == MemberRole.admin;

  /// Treasurers and administrators handle the physical cash box.
  bool get managesCash => this != MemberRole.member;
}

enum MembershipStatus {
  active,
  left,
  removed;

  static MembershipStatus parse(String value) => MembershipStatus.values.byName(value);
}

class GroupSummary {
  const GroupSummary({
    required this.id,
    required this.name,
    required this.role,
    required this.memberCount,
    required this.cycleName,
    required this.currency,
  });

  factory GroupSummary.fromJson(Json json) => GroupSummary(
    id: json.str('group_id'),
    name: json.str('name'),
    role: MemberRole.parse(json.str('role')),
    memberCount: json.intOr('member_count'),
    cycleName: json.strOrNull('cycle_name'),
    currency: json.strOrNull('currency') ?? 'EUR',
  );

  final String id;
  final String name;
  final MemberRole role;
  final int memberCount;
  final String? cycleName;
  final String currency;
}

class GroupSettings {
  const GroupSettings({
    required this.id,
    required this.name,
    required this.currency,
    required this.timezone,
    required this.requireDepositConfirmation,
    required this.requirePurchaseApproval,
    required this.undoWindowMinutes,
  });

  factory GroupSettings.fromJson(Json json) => GroupSettings(
    id: json.str('id'),
    name: json.str('name'),
    currency: json.str('currency'),
    timezone: json.str('timezone'),
    requireDepositConfirmation: json.boolOr('require_deposit_confirmation', true),
    requirePurchaseApproval: json.boolOr('require_purchase_approval'),
    undoWindowMinutes: json.intOr('member_undo_window_minutes', 15),
  );

  final String id;
  final String name;
  final String currency;
  final String timezone;
  final bool requireDepositConfirmation;
  final bool requirePurchaseApproval;
  final int undoWindowMinutes;
}

class Member {
  const Member({
    required this.userId,
    required this.displayName,
    required this.role,
    required this.status,
    required this.joinedAt,
    required this.isMe,
    this.avatarPath,
    this.leftAt,
  });

  factory Member.fromJson(Json json) => Member(
    userId: json.str('user_id'),
    displayName: json.str('display_name'),
    avatarPath: json.strOrNull('avatar_path'),
    role: MemberRole.parse(json.str('role')),
    status: MembershipStatus.parse(json.str('status')),
    joinedAt: json.date('joined_at'),
    leftAt: json.dateOrNull('left_at'),
    isMe: json.boolOr('is_me'),
  );

  final String userId;
  final String displayName;
  final String? avatarPath;
  final MemberRole role;
  final MembershipStatus status;
  final DateTime joinedAt;
  final DateTime? leftAt;
  final bool isMe;

  bool get isActive => status == MembershipStatus.active;
}

class Invitation {
  const Invitation({
    required this.id,
    required this.code,
    required this.role,
    required this.useCount,
    required this.createdAt,
    this.maxUses,
    this.expiresAt,
    this.revokedAt,
  });

  factory Invitation.fromJson(Json json) => Invitation(
    id: json.str('id'),
    code: json.str('code'),
    role: MemberRole.parse(json.str('role')),
    maxUses: json.intOrNull('max_uses'),
    useCount: json.intOr('use_count'),
    expiresAt: json.dateOrNull('expires_at'),
    revokedAt: json.dateOrNull('revoked_at'),
    createdAt: json.dateOrNull('created_at') ?? DateTime.now(),
  );

  final String id;
  final String code;
  final MemberRole role;
  final int? maxUses;
  final int useCount;
  final DateTime? expiresAt;
  final DateTime? revokedAt;
  final DateTime createdAt;

  bool isActiveAt(DateTime now) =>
      revokedAt == null && (expiresAt == null || expiresAt!.isAfter(now)) && (maxUses == null || useCount < maxUses!);

  /// Code formatted for reading aloud, e.g. `ABCD-EFGH`.
  String get displayCode => code.length == 8 ? '${code.substring(0, 4)}-${code.substring(4)}' : code;
}

class InvitationPreview {
  const InvitationPreview({
    required this.valid,
    this.reason,
    this.groupId,
    this.groupName,
    this.memberCount,
    this.alreadyMember = false,
  });

  factory InvitationPreview.fromJson(Json json) => InvitationPreview(
    valid: json.boolOr('valid'),
    reason: json.strOrNull('reason'),
    groupId: json.strOrNull('group_id'),
    groupName: json.strOrNull('group_name'),
    memberCount: json.intOrNull('member_count'),
    alreadyMember: json.boolOr('already_member'),
  );

  final bool valid;
  final String? reason;
  final String? groupId;
  final String? groupName;
  final int? memberCount;
  final bool alreadyMember;
}

class CoffeePrice {
  const CoffeePrice({required this.id, required this.priceCents, required this.effectiveFrom});

  factory CoffeePrice.fromJson(Json json) => CoffeePrice(
    id: json.str('id'),
    priceCents: json.integer('price_cents'),
    effectiveFrom: json.date('effective_from'),
  );

  final String id;
  final int priceCents;
  final DateTime effectiveFrom;
}
