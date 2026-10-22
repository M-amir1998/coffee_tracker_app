import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:coffee_tracker/core/data/rpc.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/money/money.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/feedback.dart';
import 'package:coffee_tracker/features/accounting/application/report_providers.dart';
import 'package:coffee_tracker/features/accounting/data/ledger_repository.dart';
import 'package:coffee_tracker/features/accounting/domain/ledger_models.dart';
import 'package:coffee_tracker/features/dashboard/domain/dashboard.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/settlements/domain/settlement_planner.dart';
import 'package:coffee_tracker/features/transactions/presentation/forms/amount_field.dart';
import 'package:coffee_tracker/features/transactions/presentation/forms/form_scaffold.dart';
import 'package:coffee_tracker/features/transactions/presentation/forms/member_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

Future<void> showDepositForm(
  BuildContext context, {
  required String groupId,
  int? suggestedCents,
  String? forMemberId,
}) => showAdaptiveSheet<void>(
  context,
  builder: (_) => DepositForm(groupId: groupId, suggestedCents: suggestedCents, forMemberId: forMemberId),
);

Future<void> showPurchaseForm(BuildContext context, {required String groupId}) =>
    showAdaptiveSheet<void>(context, builder: (_) => PurchaseForm(groupId: groupId));

Future<void> showTransferForm(
  BuildContext context, {
  required String groupId,
  String? fromMemberId,
  String? toMemberId,
  int? suggestedCents,
}) => showAdaptiveSheet<void>(
  context,
  builder: (_) => TransferForm(
    groupId: groupId,
    fromMemberId: fromMemberId,
    toMemberId: toMemberId,
    suggestedCents: suggestedCents,
  ),
);

Future<void> showReimbursementForm(
  BuildContext context, {
  required String groupId,
  String? memberId,
  int? suggestedCents,
}) => showAdaptiveSheet<void>(
  context,
  builder: (_) => ReimbursementForm(groupId: groupId, memberId: memberId, suggestedCents: suggestedCents),
);

/// Shared success handling: refresh data, close, and confirm what happened.
void _done(
  BuildContext context,
  WidgetRef ref,
  TransactionResult result, {
  required String posted,
  required String pending,
}) {
  ref.read(dataRevisionProvider.notifier).bump();
  final messenger = ScaffoldMessenger.of(context);
  Navigator.of(context).pop();
  messenger.showSnackBar(
    SnackBar(content: Text(result.isPending ? pending : posted), duration: const Duration(seconds: 5)),
  );
}

Dashboard? _dashboard(WidgetRef ref, String groupId) => ref.watch(dashboardProvider(groupId)).value;

// ---------------------------------------------------------------------------
// Deposit into the cash box
// ---------------------------------------------------------------------------

class DepositForm extends ConsumerStatefulWidget {
  const DepositForm({required this.groupId, super.key, this.suggestedCents, this.forMemberId});

  final String groupId;
  final int? suggestedCents;
  final String? forMemberId;

  @override
  ConsumerState<DepositForm> createState() => _DepositFormState();
}

class _DepositFormState extends ConsumerState<DepositForm> with SubmitOnce {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _key = newIdempotencyKey();
  late String? _memberId = widget.forMemberId;
  bool _onBehalf = false;

  @override
  void initState() {
    super.initState();
    _onBehalf = widget.forMemberId != null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_amount.text.isEmpty && widget.suggestedCents != null) {
      _amount.text = Money.toInput(widget.suggestedCents!, locale: context.localeTag);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = context.l10n;
    submitFrom(() async {
      final result = await ref
          .read(ledgerRepositoryProvider)
          .submitDeposit(
            groupId: widget.groupId,
            amountCents: Money.parse(_amount.text)!,
            idempotencyKey: _key,
            description: _note.text.trim().isEmpty ? null : _note.text.trim(),
            forMemberId: _onBehalf ? _memberId : null,
          );
      if (mounted) _done(context, ref, result, posted: l10n.depositRecorded, pending: l10n.depositPending);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final dashboard = _dashboard(ref, widget.groupId);
    final managesCash = dashboard?.role.managesCash ?? false;
    final needsConfirmation = !managesCash && (dashboard?.group.requireDepositConfirmation ?? true);
    return FormScaffold(
      formKey: _formKey,
      icon: Icons.savings_rounded,
      title: l10n.depositTitle,
      info: needsConfirmation ? l10n.depositInfoConfirmation : l10n.depositInfoDirect,
      busy: busy,
      error: error,
      submitLabel: l10n.depositSubmit,
      onSubmit: _submit,
      children: [
        if (managesCash) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.depositOnBehalf),
            subtitle: Text(l10n.depositOnBehalfHint),
            value: _onBehalf,
            onChanged: (value) => setState(() => _onBehalf = value),
          ),
          if (_onBehalf) ...[
            MemberPicker(
              groupId: widget.groupId,
              label: l10n.fieldMember,
              value: _memberId,
              onChanged: (value) => setState(() => _memberId = value),
            ),
            const SizedBox(height: Spacing.md),
          ],
        ],
        AmountField(controller: _amount, label: l10n.fieldAmount, autofocus: true),
        const SizedBox(height: Spacing.md),
        TextFormField(
          controller: _note,
          maxLength: 500,
          decoration: InputDecoration(labelText: l10n.fieldNoteOptional),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Coffee bean purchase
// ---------------------------------------------------------------------------

class PurchaseForm extends ConsumerStatefulWidget {
  const PurchaseForm({required this.groupId, super.key});

  final String groupId;

  @override
  ConsumerState<PurchaseForm> createState() => _PurchaseFormState();
}

class _PurchaseFormState extends ConsumerState<PurchaseForm> with SubmitOnce {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  late final _description = TextEditingController();
  final _key = newIdempotencyKey();
  PurchaseFunding _funding = PurchaseFunding.personal;
  DateTime _date = DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_description.text.isEmpty) _description.text = context.l10n.purchaseDefaultDescription;
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = context.l10n;
    final now = DateTime.now();
    final sameDay = _date.year == now.year && _date.month == now.month && _date.day == now.day;
    submitFrom(() async {
      final result = await ref
          .read(ledgerRepositoryProvider)
          .submitPurchase(
            groupId: widget.groupId,
            funding: _funding,
            amountCents: Money.parse(_amount.text)!,
            description: _description.text.trim(),
            idempotencyKey: _key,
            purchasedAt: sameDay ? null : DateTime(_date.year, _date.month, _date.day, 12),
          );
      if (mounted) _done(context, ref, result, posted: l10n.purchaseRecorded, pending: l10n.purchasePending);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final dashboard = _dashboard(ref, widget.groupId);
    final needsApproval =
        !(dashboard?.role.managesCash ?? false) && (dashboard?.group.requirePurchaseApproval ?? false);
    final info = _funding == PurchaseFunding.personal ? l10n.purchaseInfoPersonal : l10n.purchaseInfoBox;
    return FormScaffold(
      formKey: _formKey,
      icon: Icons.shopping_bag_rounded,
      title: l10n.purchaseTitle,
      info: needsApproval ? '$info ${l10n.purchaseInfoApproval}' : info,
      busy: busy,
      error: error,
      submitLabel: l10n.purchaseSubmit,
      onSubmit: _submit,
      children: [
        Text(l10n.purchaseFundingQuestion, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: Spacing.xs),
        SegmentedButton<PurchaseFunding>(
          segments: [
            ButtonSegment(
              value: PurchaseFunding.personal,
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: Text(l10n.purchaseFundingPersonal),
            ),
            ButtonSegment(
              value: PurchaseFunding.cashBox,
              icon: const Icon(Icons.inventory_2_outlined),
              label: Text(l10n.purchaseFundingBox),
            ),
          ],
          selected: {_funding},
          onSelectionChanged: (value) => setState(() => _funding = value.first),
        ),
        const SizedBox(height: Spacing.lg),
        AmountField(controller: _amount, label: l10n.fieldAmount),
        const SizedBox(height: Spacing.md),
        TextFormField(
          controller: _description,
          maxLength: 500,
          decoration: InputDecoration(labelText: l10n.fieldDescription),
          validator: (value) => (value?.trim().isEmpty ?? true) ? l10n.validationDescriptionRequired : null,
        ),
        const SizedBox(height: Spacing.xs),
        OutlinedButton.icon(
          onPressed: _pickDate,
          icon: const Icon(Icons.event_rounded),
          label: Text(l10n.purchaseDate(context.shortDate(_date))),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Direct payment between members
// ---------------------------------------------------------------------------

enum _TransferMode { iPaid, iReceived, betweenOthers }

class TransferForm extends ConsumerStatefulWidget {
  const TransferForm({required this.groupId, super.key, this.fromMemberId, this.toMemberId, this.suggestedCents});

  final String groupId;
  final String? fromMemberId;
  final String? toMemberId;
  final int? suggestedCents;

  @override
  ConsumerState<TransferForm> createState() => _TransferFormState();
}

class _TransferFormState extends ConsumerState<TransferForm> with SubmitOnce {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _key = newIdempotencyKey();
  _TransferMode? _mode;
  String? _from;
  String? _to;
  String? _other;
  bool _override = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_amount.text.isEmpty && widget.suggestedCents != null) {
      _amount.text = Money.toInput(widget.suggestedCents!, locale: context.localeTag);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  _TransferMode _initialMode(String myId) {
    if (widget.fromMemberId == myId) return _TransferMode.iPaid;
    if (widget.toMemberId == myId) return _TransferMode.iReceived;
    if (widget.fromMemberId != null || widget.toMemberId != null) return _TransferMode.betweenOthers;
    return _TransferMode.iPaid;
  }

  void _submit(String myId) {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = context.l10n;
    final mode = _mode ?? _initialMode(myId);
    final (from, to) = switch (mode) {
      _TransferMode.iPaid => (myId, _other ?? widget.toMemberId),
      _TransferMode.iReceived => (_other ?? widget.fromMemberId, myId),
      _TransferMode.betweenOthers => (_from ?? widget.fromMemberId, _to ?? widget.toMemberId),
    };
    if (from == null || to == null) return;
    submitFrom(() async {
      final result = await ref
          .read(ledgerRepositoryProvider)
          .recordTransfer(
            groupId: widget.groupId,
            fromMemberId: from,
            toMemberId: to,
            amountCents: Money.parse(_amount.text)!,
            idempotencyKey: _key,
            description: _note.text.trim().isEmpty ? null : _note.text.trim(),
            adminOverride: mode == _TransferMode.betweenOthers && _override,
          );
      if (mounted) _done(context, ref, result, posted: l10n.transferRecorded, pending: l10n.transferPending);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final dashboard = _dashboard(ref, widget.groupId);
    if (dashboard == null) return const Padding(padding: EdgeInsets.all(Spacing.xl), child: LinearProgressIndicator());
    final myId = dashboard.userId;
    final mode = _mode ?? _initialMode(myId);
    final isAdmin = dashboard.role.isAdmin;

    final info = switch (mode) {
      _TransferMode.iPaid => l10n.transferInfoPaid,
      _TransferMode.iReceived => l10n.transferInfoReceived,
      _TransferMode.betweenOthers => _override ? l10n.transferInfoOverride : l10n.transferInfoOthers,
    };

    return FormScaffold(
      formKey: _formKey,
      icon: Icons.swap_horiz_rounded,
      title: l10n.transferTitle,
      info: info,
      busy: busy,
      error: error,
      submitLabel: l10n.transferSubmit,
      onSubmit: () => _submit(myId),
      children: [
        SegmentedButton<_TransferMode>(
          segments: [
            ButtonSegment(value: _TransferMode.iPaid, label: Text(l10n.transferModePaid)),
            ButtonSegment(value: _TransferMode.iReceived, label: Text(l10n.transferModeReceived)),
            if (isAdmin) ButtonSegment(value: _TransferMode.betweenOthers, label: Text(l10n.transferModeOthers)),
          ],
          selected: {mode},
          onSelectionChanged: (value) => setState(() => _mode = value.first),
        ),
        const SizedBox(height: Spacing.lg),
        if (mode == _TransferMode.betweenOthers) ...[
          MemberPicker(
            groupId: widget.groupId,
            label: l10n.fieldFrom,
            value: _from ?? widget.fromMemberId,
            onChanged: (value) => setState(() => _from = value),
          ),
          const SizedBox(height: Spacing.md),
          MemberPicker(
            groupId: widget.groupId,
            label: l10n.fieldTo,
            value: _to ?? widget.toMemberId,
            exclude: {?(_from ?? widget.fromMemberId)},
            onChanged: (value) => setState(() => _to = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.transferOverride),
            subtitle: Text(l10n.transferOverrideHint),
            value: _override,
            onChanged: (value) => setState(() => _override = value),
          ),
        ] else
          MemberPicker(
            groupId: widget.groupId,
            label: mode == _TransferMode.iPaid ? l10n.fieldPaidTo : l10n.fieldReceivedFrom,
            value: _other ?? (mode == _TransferMode.iPaid ? widget.toMemberId : widget.fromMemberId),
            exclude: {myId},
            onChanged: (value) => setState(() => _other = value),
          ),
        const SizedBox(height: Spacing.md),
        AmountField(controller: _amount, label: l10n.fieldAmount),
        const SizedBox(height: Spacing.md),
        TextFormField(
          controller: _note,
          maxLength: 500,
          decoration: InputDecoration(labelText: _override ? l10n.fieldReasonRequired : l10n.fieldNoteOptional),
          validator: (value) => _override && mode == _TransferMode.betweenOthers && (value?.trim().length ?? 0) < 3
              ? l10n.validationNoteRequired
              : null,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Reimbursement from the cash box
// ---------------------------------------------------------------------------

class ReimbursementForm extends ConsumerStatefulWidget {
  const ReimbursementForm({required this.groupId, super.key, this.memberId, this.suggestedCents});

  final String groupId;
  final String? memberId;
  final int? suggestedCents;

  @override
  ConsumerState<ReimbursementForm> createState() => _ReimbursementFormState();
}

class _ReimbursementFormState extends ConsumerState<ReimbursementForm> with SubmitOnce {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _key = newIdempotencyKey();
  late String? _memberId = widget.memberId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_amount.text.isEmpty && widget.suggestedCents != null) {
      _amount.text = Money.toInput(widget.suggestedCents!, locale: context.localeTag);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit(String myId, bool managesCash) {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = context.l10n;
    final member = managesCash ? _memberId : myId;
    if (member == null) return;
    submitFrom(() async {
      final result = await ref
          .read(ledgerRepositoryProvider)
          .recordReimbursement(
            groupId: widget.groupId,
            memberId: member,
            amountCents: Money.parse(_amount.text)!,
            idempotencyKey: _key,
            description: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      if (mounted) {
        _done(context, ref, result, posted: l10n.reimbursementRecorded, pending: l10n.reimbursementRequested);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final dashboard = _dashboard(ref, widget.groupId);
    final inputs = ref.watch(settlementInputsProvider(widget.groupId)).value;
    if (dashboard == null) return const Padding(padding: EdgeInsets.all(Spacing.xl), child: LinearProgressIndicator());
    final managesCash = dashboard.role.managesCash;
    final credits = {for (final m in inputs?.members ?? const <SettlementMember>[]) m.userId: -m.netCents};

    return FormScaffold(
      formKey: _formKey,
      icon: Icons.payments_rounded,
      title: managesCash ? l10n.reimburseTitle : l10n.requestReimbursementTitle,
      info: managesCash ? l10n.reimburseInfo(context.money(inputs?.cashBoxCents ?? 0)) : l10n.requestReimbursementInfo,
      busy: busy,
      error: error,
      submitLabel: managesCash ? l10n.reimburseSubmit : l10n.requestReimbursementSubmit,
      onSubmit: () => _submit(dashboard.userId, managesCash),
      children: [
        if (managesCash) ...[
          MemberPicker(
            groupId: widget.groupId,
            label: l10n.fieldMember,
            value: _memberId,
            subtitleFor: (member) {
              final credit = credits[member.userId] ?? 0;
              return credit > 0 ? l10n.owedAmount(context.money(credit)) : null;
            },
            onChanged: (value) => setState(() => _memberId = value),
          ),
          const SizedBox(height: Spacing.md),
        ],
        AmountField(controller: _amount, label: l10n.fieldAmount),
        const SizedBox(height: Spacing.md),
        TextFormField(
          controller: _note,
          maxLength: 500,
          decoration: InputDecoration(labelText: l10n.fieldNoteOptional),
        ),
      ],
    );
  }
}
