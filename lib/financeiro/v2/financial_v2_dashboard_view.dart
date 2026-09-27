import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../design_system/mp_tokens.dart';
import 'financial_chart_axis.dart';
import 'financial_dashboard_presentation.dart';
import 'financial_overview_loader.dart';
import 'financial_read_model.dart';

class FinancialV2DashboardView extends StatelessWidget {
  const FinancialV2DashboardView({
    super.key,
    required this.data,
    required this.periodKind,
    required this.onPeriod,
    required this.onRefresh,
    required this.onOpenReceivables,
    required this.onOpenPayables,
  });

  final FinancialDashboardViewData data;
  final FinancialDashboardPeriodKind periodKind;
  final ValueChanged<FinancialDashboardPeriodKind> onPeriod;
  final VoidCallback onRefresh;
  final VoidCallback onOpenReceivables;
  final VoidCallback onOpenPayables;

  @override
  Widget build(BuildContext context) {
    final cards = presentFinancialDashboard(
      read: data.read,
      salesAvailable: data.salesAvailable,
      entriesAvailable: data.entriesAvailable,
      receivablesAvailable: data.receivablesAvailable,
      payablesAvailable: data.payablesAvailable,
    );
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1100 ? 4 : width >= 700 ? 2 : 1;

    return ListView(
      padding: const EdgeInsets.all(MpSpacing.lg),
      children: [
        Wrap(
          spacing: MpSpacing.sm,
          runSpacing: MpSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _periodChip(context, 'Hoje', FinancialDashboardPeriodKind.today),
            _periodChip(context, '7 dias', FinancialDashboardPeriodKind.last7Days),
            _periodChip(
              context,
              'Mês atual',
              FinancialDashboardPeriodKind.currentMonth,
            ),
            _periodChip(
              context,
              'Período personalizado',
              FinancialDashboardPeriodKind.custom,
            ),
            IconButton(
              tooltip: 'Atualizar',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: MpSpacing.lg),
        _grid(columns, [
          _card(context, cards.faturamento),
          _card(context, cards.recebimentos),
          _card(context, cards.saidas),
          _card(context, cards.resultadoCaixa),
          _card(context, cards.aReceber),
          _card(context, cards.vencido),
          _card(context, cards.aPagar),
          _card(context, cards.lucroBruto),
        ]),
        const SizedBox(height: MpSpacing.xl),
        _chartCard(
          context,
          title: 'Entradas x saídas',
          primary: 'Entradas',
          secondary: 'Saídas',
          points: cards.cashChart,
          primaryColor: MpColors.success,
          secondaryColor: MpColors.danger,
        ),
        const SizedBox(height: MpSpacing.lg),
        _chartCard(
          context,
          title: 'Faturamento x recebimentos',
          primary: 'Faturamento',
          secondary: 'Recebimentos',
          points: cards.salesVsReceiptsChart,
          primaryColor: MpColors.financeiro,
          secondaryColor: MpColors.info,
        ),
        const SizedBox(height: MpSpacing.xl),
        _summary(
          context,
          title: 'Contas a receber',
          slice: cards.receivableSummary,
          action: 'Ver contas a receber',
          onAction: onOpenReceivables,
          localNote: null,
        ),
        const SizedBox(height: MpSpacing.lg),
        _summary(
          context,
          title: 'Contas a pagar',
          slice: cards.payableSummary,
          action: 'Ver contas a pagar',
          onAction: onOpenPayables,
          localNote: 'Neste dispositivo',
        ),
        if (cards.qualityNotes.isNotEmpty) ...[
          const SizedBox(height: MpSpacing.lg),
          ExpansionTile(
            title: const Text('Qualidade dos dados', style: MpType.section),
            children: [
              for (final note in cards.qualityNotes)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.info_outline, color: MpColors.warning),
                  title: Text(note, style: MpType.body),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _periodChip(
    BuildContext context,
    String label,
    FinancialDashboardPeriodKind kind,
  ) {
    final selected = periodKind == kind;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onPeriod(kind),
    );
  }

  Widget _grid(int columns, List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = MpSpacing.md;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }

  Widget _card(BuildContext context, FinancialCardModel model) {
    final scheme = Theme.of(context).colorScheme;
    final valueColor = switch (model.tone) {
      FinancialCardTone.outflow => MpColors.danger,
      FinancialCardTone.attention => MpColors.warning,
      FinancialCardTone.neutral => scheme.onSurface,
    };
    return Card(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MpRadius.lg),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(MpSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(model.title, style: MpType.kpiLabel)),
                Tooltip(
                  message: model.tooltip,
                  child: Icon(Icons.info_outline, size: 16, color: scheme.outline),
                ),
              ],
            ),
            const SizedBox(height: MpSpacing.sm),
            Text(
              model.valueText ?? unavailableValue,
              style: MpType.kpiValue.copyWith(color: valueColor),
            ),
            if (model.footnote != null) ...[
              const SizedBox(height: MpSpacing.xs),
              Text(model.footnote!, style: MpType.caption),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chartCard(
    BuildContext context, {
    required String title,
    required String primary,
    required String secondary,
    required List<FinancialChartPoint>? points,
    required Color primaryColor,
    required Color secondaryColor,
  }) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(MpSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: MpType.title),
            const SizedBox(height: MpSpacing.sm),
            Text('$primary  ·  $secondary', style: MpType.caption),
            const SizedBox(height: MpSpacing.md),
            SizedBox(
              height: 220,
              child: points == null
                  ? const Center(child: Text(unavailableValue, style: MpType.body))
                  : _bars(
                      context,
                      points: points,
                      primary: primary,
                      secondary: secondary,
                      primaryColor: primaryColor,
                      secondaryColor: secondaryColor,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bars(
    BuildContext context, {
    required List<FinancialChartPoint> points,
    required String primary,
    required String secondary,
    required Color primaryColor,
    required Color secondaryColor,
  }) {
    final magnitudes = <double>[
      for (final point in points) ...[point.primary, point.secondary],
    ];
    var peak = 0.0;
    for (final value in magnitudes) {
      if (value.abs() > peak) peak = value.abs();
    }
    final reserved = chartYAxisReservedWidth([
      ...magnitudes,
      peak <= 0 ? 0 : peak * 1.08,
    ]);
    final width = MediaQuery.sizeOf(context).width;
    final labelStep = points.length <= 8
        ? 1
        : width < 500
            ? (points.length / 5).ceil().clamp(1, points.length)
            : points.length > 12
                ? 2
                : 1;
    final names = [primary, secondary];
    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        groupsSpace: 12,
        maxY: peak <= 0 ? 1 : peak * 1.08,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            maxContentWidth: 168,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final name = rodIndex >= 0 && rodIndex < names.length
                  ? names[rodIndex]
                  : '';
              return BarTooltipItem(
                '$name\n${formatBrlKnown(rod.toY)}',
                const TextStyle(color: Colors.white, fontSize: 12),
              );
            },
          ),
        ),
        barGroups: [
          for (var i = 0; i < points.length; i++)
            BarChartGroupData(
              x: i,
              barsSpace: 4,
              barRods: [
                BarChartRodData(
                  toY: points[i].primary,
                  color: primaryColor,
                  width: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                BarChartRodData(
                  toY: points[i].secondary,
                  color: secondaryColor,
                  width: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
        ],
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: reserved,
              interval: peak <= 0 ? 1 : peak,
              getTitlesWidget: (value, meta) {
                return Text(
                  compactChartAxisLabel(value),
                  style: chartAxisLabelStyle,
                  maxLines: 1,
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= points.length) {
                  return const SizedBox.shrink();
                }
                if (i % labelStep != 0 && i != points.length - 1) {
                  return const SizedBox.shrink();
                }
                return Text(
                  points[i].label,
                  style: chartAxisLabelStyle,
                  maxLines: 1,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _summary(
    BuildContext context, {
    required String title,
    required FinancialAgingSlice? slice,
    required String action,
    required VoidCallback onAction,
    required String? localNote,
  }) {
    final known = slice != null;
    String line(String label, double? value) => known
        ? '$label: ${formatBrlKnown(value!)}'
        : '$label: $unavailableValue';
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(MpSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: MpType.title),
            if (localNote != null)
              Text(localNote, style: MpType.caption),
            const SizedBox(height: MpSpacing.sm),
            Text(line('Total aberto', known ? slice.open : null), style: MpType.body),
            Text(line('Vencido', known ? slice.overdue : null), style: MpType.body),
            Text(line('A vencer', known ? slice.upcoming : null), style: MpType.body),
            Text(
              line('Vence em 7 dias', known ? slice.dueWithin7Days : null),
              style: MpType.body,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: onAction, child: Text(action)),
            ),
          ],
        ),
      ),
    );
  }
}
