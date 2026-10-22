import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/app_card.dart';
import 'package:coffee_tracker/core/widgets/feedback.dart';
import 'package:coffee_tracker/core/widgets/money_text.dart';
import 'package:coffee_tracker/core/widgets/page_layout.dart';
import 'package:coffee_tracker/core/widgets/stat_tile.dart';
import 'package:coffee_tracker/core/widgets/states.dart';
import 'package:coffee_tracker/features/accounting/application/report_providers.dart';
import 'package:coffee_tracker/features/accounting/domain/balance_models.dart';
import 'package:coffee_tracker/features/admin/domain/csv_exports.dart';
import 'package:coffee_tracker/features/admin/presentation/file_export.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class CycleReportPage extends ConsumerWidget {
  const CycleReportPage({required this.cycleId, super.key});

  final String cycleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final report = ref.watch(cycleReportProvider(cycleId));
    return AppPage(
      title: report.value?.cycle.name ?? l10n.cycleReportTitle,
      showBackButton: true,
      actions: [
        if (report.value case final data?)
          IconButton(
            tooltip: l10n.exportCsv,
            icon: const Icon(Icons.download_rounded),
            onPressed: () async {
              try {
                final saved = await exportTextFile(
                  context,
                  fileName: 'cycle-${data.cycle.sequenceNo}-${data.cycle.name}.csv',
                  content: cycleReportCsv(data),
                );
                if (context.mounted && saved) showToast(context, l10n.exportDone, icon: Icons.check_rounded);
              } on Object catch (error) {
                if (context.mounted) showErrorToast(context, error);
              }
            },
          ),
      ],
      body: AsyncValueView(
        value: report,
        onRetry: () => ref.invalidate(cycleReportProvider(cycleId)),
        data: (data) => _ReportBody(report: data),
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.report});

  final CycleReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final currency = report.currency;
    String money(int cents) => context.money(cents, currency: currency);
    final cash = report.cash;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Row(
            children: [
              Icon(
                report.isFinal ? Icons.verified_rounded : Icons.timelapse_rounded,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  report.isFinal
                      ? l10n.reportFinal(
                          context.shortDate(report.cycle.openedAt),
                          context.shortDate(report.cycle.closedAt!),
                        )
                      : l10n.reportLive(context.shortDate(report.cycle.openedAt), context.dateTime(report.generatedAt)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.md),
        TileGrid(
          children: [
            StatTile(icon: Icons.coffee_rounded, label: l10n.statCoffees, value: context.number(report.totalCoffees)),
            StatTile(
              icon: Icons.receipt_rounded,
              label: l10n.statConsumption,
              value: money(report.totalConsumptionCents),
            ),
            StatTile(
              icon: Icons.inventory_2_rounded,
              label: l10n.statClosingCash,
              value: money(cash.closingCashCents),
              emphasis: true,
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        SectionCard(
          title: l10n.cashSummaryTitle,
          child: Column(
            children: [
              for (final (label, cents) in [
                (l10n.cashOpening, cash.openingCashCents),
                (l10n.cashDeposits, cash.depositsCents),
                (l10n.cashBoxPurchases, -cash.boxPurchasesCents),
                (l10n.cashReimbursements, -cash.reimbursementsCents),
                (l10n.cashAdjustments, cash.cashAdjustmentsCents),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(label)),
                      MoneyText(cents, currency: currency, signed: label != l10n.cashOpening),
                    ],
                  ),
                ),
              const Divider(),
              Row(
                children: [
                  Expanded(child: Text(l10n.cashClosing, style: theme.textTheme.titleSmall)),
                  MoneyText(cash.closingCashCents, currency: currency, style: theme.textTheme.titleSmall),
                ],
              ),
              if (!cash.isConsistent) Text(l10n.balanceInconsistent, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ),
        ),
        const SizedBox(height: Spacing.md),
        SectionCard(
          title: l10n.reportMembersTitle,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                DataColumn(label: Text(l10n.columnMember)),
                DataColumn(label: Text(l10n.breakdownOpening), numeric: true),
                DataColumn(label: Text(l10n.columnCoffees), numeric: true),
                DataColumn(label: Text(l10n.columnConsumption), numeric: true),
                DataColumn(label: Text(l10n.columnContributions), numeric: true),
                DataColumn(label: Text(l10n.columnPayments), numeric: true),
                DataColumn(label: Text(l10n.breakdownReimbursed), numeric: true),
                DataColumn(label: Text(l10n.breakdownAdjustments), numeric: true),
                DataColumn(label: Text(report.isFinal ? l10n.columnClosing : l10n.columnNet), numeric: true),
              ],
              rows: [
                for (final row in report.members)
                  DataRow(
                    cells: [
                      DataCell(Text(row.active ? row.displayName : '${row.displayName} (${l10n.formerMember})')),
                      DataCell(MoneyText(row.breakdown.openingCents, currency: currency)),
                      DataCell(Text(context.number(row.breakdown.coffees))),
                      DataCell(MoneyText(row.breakdown.consumptionCents, currency: currency)),
                      DataCell(MoneyText(row.breakdown.contributionsCents, currency: currency)),
                      DataCell(
                        MoneyText(
                          row.breakdown.transfersReceivedCents - row.breakdown.transfersSentCents,
                          currency: currency,
                          signed: true,
                        ),
                      ),
                      DataCell(MoneyText(row.breakdown.reimbursementsCents, currency: currency)),
                      DataCell(MoneyText(row.breakdown.adjustmentsCents, currency: currency, signed: true)),
                      DataCell(MoneyText(row.breakdown.netCents, currency: currency, colorBySign: true)),
                    ],
                  ),
              ],
            ),
          ),
        ),
        if (report.cycle.closeNote != null) ...[
          const SizedBox(height: Spacing.md),
          AppCard(child: Text(l10n.reportCloseNote(report.cycle.closeNote!))),
        ],
        if (report.members.isEmpty) EmptyState(icon: Icons.inbox_rounded, title: l10n.reportEmpty),
      ],
    );
  }
}
