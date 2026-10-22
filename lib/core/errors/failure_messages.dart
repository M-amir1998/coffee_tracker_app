import 'package:coffee_tracker/core/errors/app_failure.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';

/// A short, human explanation of any error, in the user's language.
String describeFailure(AppLocalizations l10n, Object error) {
  final failure = toFailure(error);
  return switch (failure) {
    NetworkFailure() => l10n.errorNetwork,
    SessionExpiredFailure() => l10n.errorSessionExpired,
    PermissionFailure() => l10n.errorPermission,
    AuthFailure(:final code) => _authMessage(l10n, code),
    RuleFailure(:final code, :final detail) => _ruleMessage(l10n, code) ?? detail ?? l10n.errorUnexpected,
    UnexpectedFailure() => l10n.errorUnexpected,
  };
}

String _authMessage(AppLocalizations l10n, String code) => switch (code) {
  'invalid_credentials' => l10n.authErrorInvalidCredentials,
  'email_not_confirmed' => l10n.authErrorEmailNotConfirmed,
  'user_already_exists' || 'email_exists' => l10n.authErrorUserExists,
  'weak_password' => l10n.authErrorWeakPassword,
  'otp_expired' || 'invalid_otp' => l10n.authErrorCodeInvalid,
  'over_email_send_rate_limit' || 'over_request_rate_limit' => l10n.authErrorRateLimited,
  'same_password' => l10n.authErrorSamePassword,
  'signup_disabled' => l10n.authErrorSignupDisabled,
  _ => l10n.errorUnexpected,
};

String? _ruleMessage(AppLocalizations l10n, String code) => switch (code) {
  'not_authenticated' => l10n.errorSessionExpired,
  'not_member' => l10n.ruleNotMember,
  'forbidden' => l10n.errorPermission,
  'not_found' => l10n.ruleNotFound,
  'invalid_amount' => l10n.ruleInvalidAmount,
  'amount_too_large' => l10n.ruleAmountTooLarge,
  'invalid_quantity' => l10n.ruleInvalidQuantity,
  'insufficient_cash' => l10n.ruleInsufficientCash,
  'reimbursement_exceeds_credit' => l10n.ruleReimbursementExceedsCredit,
  'self_transfer' => l10n.ruleSelfTransfer,
  'note_required' => l10n.ruleNoteRequired,
  'description_required' => l10n.ruleDescriptionRequired,
  'invalid_state' => l10n.ruleInvalidState,
  'already_reversed' => l10n.ruleAlreadyReversed,
  'cannot_reverse_reversal' => l10n.ruleCannotReverseReversal,
  'already_disputed' => l10n.ruleAlreadyDisputed,
  'undo_window_expired' => l10n.ruleUndoWindowExpired,
  'cycle_closed' => l10n.ruleCycleClosed,
  'no_open_cycle' => l10n.ruleNoOpenCycle,
  'stale_cycle' => l10n.ruleStaleCycle,
  'confirmation_mismatch' => l10n.ruleConfirmationMismatch,
  'occurred_at_out_of_range' => l10n.ruleOccurredAtOutOfRange,
  'idempotency_conflict' => l10n.ruleIdempotencyConflict,
  'outstanding_balance' => l10n.ruleOutstandingBalance,
  'open_items' => l10n.ruleOpenItems,
  'last_admin' => l10n.ruleLastAdmin,
  'invalid_invitation' => l10n.ruleInvalidInvitation,
  'invitation_revoked' => l10n.ruleInvitationRevoked,
  'invitation_expired' => l10n.ruleInvitationExpired,
  'invitation_used_up' => l10n.ruleInvitationUsedUp,
  'invalid_name' => l10n.ruleInvalidName,
  'invalid_price' => l10n.ruleInvalidPrice,
  'price_backdated' => l10n.rulePriceBackdated,
  'invalid_timezone' => l10n.ruleInvalidTimezone,
  'queue_full' => l10n.ruleQueueFull,
  _ => null,
};
