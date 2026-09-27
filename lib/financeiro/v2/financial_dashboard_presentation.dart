import 'financial_read_model.dart';
import 'financial_warnings.dart';
import 'brazil_business_date.dart';

enum FinancialDashboardPeriodKind { today, last7Days, currentMonth, custom }

enum FinancialCardTone { neutral, outflow, attention }

enum GrossProfitDisplay { amount, knownPartial, insufficient, unavailable }

class FinancialCardModel {
  const FinancialCardModel({
    required this.id,
    required this.title,
    required this.tooltip,
    required this.tone,
    this.valueText,
    this.footnote,
  });

  final String id;
  final String title;
  final String tooltip;
  final FinancialCardTone tone;
  final String? valueText;
  final String? footnote;

  bool get unavailable => valueText == null;
}

class FinancialChartPoint {
  const FinancialChartPoint({
    required this.label,
    required this.primary,
    required this.secondary,
  });

  final String label;
  final double primary;
  final double secondary;
}

class FinancialDashboardCards {
  const FinancialDashboardCards({
    required this.faturamento,
    required this.recebimentos,
    required this.saidas,
    required this.resultadoCaixa,
    required this.aReceber,
    required this.vencido,
    required this.aPagar,
    required this.lucroBruto,
    required this.cashChart,
    required this.salesVsReceiptsChart,
    required this.receivableSummary,
    required this.payableSummary,
    required this.qualityNotes,
    required this.showsAvailableBalance,
    required this.showsDre,
    required this.showsNetProfit,
    required this.estimatedFeeIncludedInTotals,
  });

  final FinancialCardModel faturamento;
  final FinancialCardModel recebimentos;
  final FinancialCardModel saidas;
  final FinancialCardModel resultadoCaixa;
  final FinancialCardModel aReceber;
  final FinancialCardModel vencido;
  final FinancialCardModel aPagar;
  final FinancialCardModel lucroBruto;
  final List<FinancialChartPoint>? cashChart;
  final List<FinancialChartPoint>? salesVsReceiptsChart;
  final FinancialAgingSlice? receivableSummary;
  final FinancialAgingSlice? payableSummary;
  final List<String> qualityNotes;
  final bool showsAvailableBalance;
  final bool showsDre;
  final bool showsNetProfit;
  final bool estimatedFeeIncludedInTotals;
}

FinancialPeriod financialDashboardPeriod({
  required FinancialDashboardPeriodKind kind,
  required DateTime today,
  DateTime? customStart,
  DateTime? customEnd,
}) {
  final day = BrazilBusinessDate.dateOnly(today);
  switch (kind) {
    case FinancialDashboardPeriodKind.today:
      return FinancialPeriod(start: day, end: day);
    case FinancialDashboardPeriodKind.last7Days:
      return FinancialPeriod(
        start: day.subtract(const Duration(days: 6)),
        end: day,
      );
    case FinancialDashboardPeriodKind.currentMonth:
      final last = DateTime(day.year, day.month + 1, 0);
      return FinancialPeriod(start: DateTime(day.year, day.month, 1), end: last);
    case FinancialDashboardPeriodKind.custom:
      return FinancialPeriod(
        start: customStart ?? day,
        end: customEnd ?? day,
      );
  }
}

String formatBrlKnown(double value) {
  final negative = value < -0.004;
  final cents = (value.abs() * 100).round();
  final whole = cents ~/ 100;
  final frac = (cents % 100).toString().padLeft(2, '0');
  final digits = whole.toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final remaining = digits.length - i;
    if (i > 0 && remaining % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  return '${negative ? '-' : ''}R\$ $buf,$frac';
}

const unavailableValue = 'Indisponível';

FinancialDashboardCards presentFinancialDashboard({
  required FinancialDashboardRead read,
  required bool salesAvailable,
  required bool entriesAvailable,
  required bool receivablesAvailable,
  required bool payablesAvailable,
}) {
  final overview = read.overview;
  final receiptsKnown =
      salesAvailable && entriesAvailable && receivablesAvailable;
  final cashKnown = receiptsKnown && entriesAvailable;
  final profit = _grossProfit(
    salesAvailable: salesAvailable,
    included: read.includedSaleCount,
    incomplete: overview.grossProfitIncompleteSaleCount,
    knownAmount: overview.grossProfitKnownAmount,
  );

  return FinancialDashboardCards(
    faturamento: FinancialCardModel(
      id: 'faturamento',
      title: 'Faturamento',
      tooltip:
          'Total das vendas confirmadas no período. Não é o dinheiro que entrou no caixa.',
      tone: FinancialCardTone.neutral,
      valueText: salesAvailable ? formatBrlKnown(overview.grossSales) : null,
    ),
    recebimentos: FinancialCardModel(
      id: 'recebimentos',
      title: 'Recebimentos',
      tooltip:
          'Dinheiro, Pix e cartão recebidos, mais o que foi de fato pago do fiado. Fiado em aberto não entra.',
      tone: FinancialCardTone.neutral,
      valueText: receiptsKnown ? formatBrlKnown(overview.cashInflows) : null,
    ),
    saidas: FinancialCardModel(
      id: 'saidas',
      title: 'Saídas',
      tooltip:
          'Pagamentos feitos no período. Compra paga é saída de caixa e não entra de novo como custo da venda.',
      tone: FinancialCardTone.outflow,
      valueText: entriesAvailable ? formatBrlKnown(overview.cashOutflows) : null,
    ),
    resultadoCaixa: FinancialCardModel(
      id: 'resultado_caixa',
      title: 'Resultado de caixa',
      tooltip: 'Recebimentos menos saídas. Não é lucro.',
      tone: overview.netCashMovement < 0
          ? FinancialCardTone.outflow
          : FinancialCardTone.neutral,
      valueText: cashKnown ? formatBrlKnown(overview.netCashMovement) : null,
    ),
    aReceber: FinancialCardModel(
      id: 'a_receber',
      title: 'A receber',
      tooltip: 'Saldo em aberto das contas a receber confirmadas.',
      tone: FinancialCardTone.neutral,
      valueText:
          receivablesAvailable ? formatBrlKnown(read.receivables.open) : null,
    ),
    vencido: FinancialCardModel(
      id: 'vencido',
      title: 'Vencido',
      tooltip: 'Contas a receber em aberto com vencimento antes de hoje.',
      tone: FinancialCardTone.attention,
      valueText: receivablesAvailable
          ? formatBrlKnown(read.receivables.overdue)
          : null,
    ),
    aPagar: FinancialCardModel(
      id: 'a_pagar',
      title: 'A pagar',
      tooltip: 'Parcelas em aberto salvas neste dispositivo. Ainda não é uma conta sincronizada na nuvem.',
      tone: FinancialCardTone.neutral,
      footnote: 'Neste dispositivo',
      valueText: payablesAvailable ? formatBrlKnown(read.payables.open) : null,
    ),
    lucroBruto: profit,
    cashChart: cashKnown
        ? _chart(
            read: read,
            primary: (d) => d.receipts,
            secondary: (d) => d.outflows,
          )
        : null,
    salesVsReceiptsChart: salesAvailable && receiptsKnown
        ? _chart(
            read: read,
            primary: (d) => d.grossSales,
            secondary: (d) => d.receipts,
          )
        : null,
    receivableSummary: receivablesAvailable ? read.receivables : null,
    payableSummary: payablesAvailable ? read.payables : null,
    qualityNotes: _qualityNotes(overview),
    showsAvailableBalance: false,
    showsDre: false,
    showsNetProfit: false,
    estimatedFeeIncludedInTotals: false,
  );
}

FinancialCardModel _grossProfit({
  required bool salesAvailable,
  required int included,
  required int incomplete,
  required double knownAmount,
}) {
  const tooltip =
      'Faturamento menos o custo conhecido das vendas. Pagamento de compra não entra de novo. Venda sem custo histórico não vira zero.';
  if (!salesAvailable) {
    return const FinancialCardModel(
      id: 'lucro_bruto',
      title: 'Lucro bruto',
      tooltip: tooltip,
      tone: FinancialCardTone.neutral,
    );
  }
  if (included == 0 || incomplete == 0) {
    return FinancialCardModel(
      id: 'lucro_bruto',
      title: 'Lucro bruto',
      tooltip: tooltip,
      tone: FinancialCardTone.neutral,
      valueText: formatBrlKnown(knownAmount),
    );
  }
  if (incomplete < included) {
    return FinancialCardModel(
      id: 'lucro_bruto',
      title: 'Lucro bruto conhecido',
      tooltip: tooltip,
      tone: FinancialCardTone.attention,
      valueText: formatBrlKnown(knownAmount),
      footnote: '$incomplete venda(s) sem custo histórico completo',
    );
  }
  return const FinancialCardModel(
    id: 'lucro_bruto',
    title: 'Lucro bruto',
    tooltip: tooltip,
    tone: FinancialCardTone.attention,
    valueText: 'Dados insuficientes',
  );
}

List<FinancialChartPoint>? _chart({
  required FinancialDashboardRead read,
  required double Function(FinancialDayMovement day) primary,
  required double Function(FinancialDayMovement day) secondary,
}) {
  final period = FinancialPeriod(
    start: read.overview.periodStart,
    end: read.overview.periodEnd,
  );
  final byDay = {
    for (final day in read.days) BrazilBusinessDate.dateOnly(day.day): day,
  };
  final span = period.periodEnd.difference(period.periodStart).inDays + 1;
  final grain = span <= 31
      ? _Grain.day
      : span <= 120
          ? _Grain.week
          : _Grain.month;
  final grouped = <DateTime, List<double>>{};
  for (var i = 0; i < span; i++) {
    final day = period.periodStart.add(Duration(days: i));
    final key = switch (grain) {
      _Grain.day => day,
      _Grain.week => day.subtract(Duration(days: day.weekday - 1)),
      _Grain.month => DateTime(day.year, day.month, 1),
    };
    final movement = byDay[day];
    final slot = grouped.putIfAbsent(key, () => [0, 0]);
    if (movement == null) continue;
    slot[0] += primary(movement);
    slot[1] += secondary(movement);
  }
  final keys = grouped.keys.toList()..sort();
  return [
    for (final key in keys)
      FinancialChartPoint(
        label: _label(key, grain),
        primary: grouped[key]![0],
        secondary: grouped[key]![1],
      ),
  ];
}

enum _Grain { day, week, month }

String _label(DateTime day, _Grain grain) {
  final dd = day.day.toString().padLeft(2, '0');
  final mm = day.month.toString().padLeft(2, '0');
  if (grain == _Grain.month) return '$mm/${day.year}';
  return '$dd/$mm';
}

List<String> _qualityNotes(FinancialOverviewReadModel overview) {
  final notes = <String>[];
  final seen = <String>{};
  for (final code in overview.dataQualityWarnings) {
    final text = _warningText(code, overview.estimatedCardFee);
    if (text == null || !seen.add(text)) continue;
    notes.add(text);
  }
  return notes;
}

String? _warningText(String code, double? estimatedFee) {
  switch (code) {
    case FinancialDataQualityWarning.payablesLocalOnly:
      return 'Contas a pagar ainda estão salvas neste dispositivo.';
    case FinancialDataQualityWarning.historicalSaleMissingCogs:
    case FinancialDataQualityWarning.incompleteCostData:
      return 'Algumas vendas antigas não possuem custo histórico completo.';
    case FinancialDataQualityWarning.consignmentCogsUnknown:
      return 'Acertos de consignação ainda não têm custo histórico completo.';
    case FinancialDataQualityWarning.cardFeeEstimatedOnly:
      if (estimatedFee != null) {
        return 'Taxa de cartão é só estimativa (${formatBrlKnown(estimatedFee)}) e não entra nos totais.';
      }
      return 'Taxas de cartão configuradas são só estimativa e não entram nos totais.';
    case FinancialDataQualityWarning.noFinancialAccounts:
      return 'Saldo disponível será exibido quando contas financeiras forem configuradas.';
    case FinancialDataQualityWarning.noOpeningBalance:
      return 'Ainda não há saldo inicial de caixa configurado.';
    default:
      return null;
  }
}
