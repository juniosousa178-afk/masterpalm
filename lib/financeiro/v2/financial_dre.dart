// DRE somente leitura — fase 3A.
// Calcula um demonstrativo a partir de vendas e lançamentos já existentes.
// Não grava venda, lançamento, fiado, conta a pagar, compra, estoque,
// consignação, ledger nem histórico.

import '../../core/venda_metrics_filter.dart';
import '../../financeiro/financeiro_constants.dart';
import '../../models/lancamento_financeiro.dart';
import '../../models/venda.dart';
import 'brazil_business_date.dart';
import 'financial_month.dart';
import 'financial_read_model.dart';

/// A DRE global continua desligada. O preview é só da loja piloto.
abstract final class FinancialDrePolicy {
  static const bool readOnly = true;
  static const int financialWrites = 0;
  static const int ledgerWrites = 0;
  static const bool netProfitSupported = false;
  static const bool notBasedOnCashResult = true;
  static const bool purchasePaymentNotCogs = true;
  static const bool payablePaymentNotDoubleExpense = true;
  static const bool ownerWithdrawalNotOperatingExpense = true;
  static const bool investmentNotOperatingExpense = true;
  static const bool merchandisePurchaseNotOperatingExpense = true;
  static const bool fiadoPaymentNotNewRevenue = true;
  static const bool fiadoRevenueRecognizedOnSale = true;
  static const bool estimatedCardFeeNotInActualResult = true;
  static const bool unsupportedTaxesNotInvented = true;
  static const bool missingCogsNotZero = true;
  static const bool historicalDoesNotInventMissingComponents = true;
  static const bool drilldownReadOnly = true;
  static const bool screenPrintPdfSameTotals = true;
  static const bool periodSelectorReusesFinancialHistory = true;

  /// A loja entra pela flag remota `dreEnabled`, não pelo id fixo.
  static bool showEntry({required bool tenantDreEnabled}) => tenantDreEnabled;
}

enum DreValueState { known, unavailable }

class DreValue {
  const DreValue.known(this.amount) : state = DreValueState.known;
  const DreValue.unavailable()
      : state = DreValueState.unavailable,
        amount = null;

  final DreValueState state;
  final double? amount;

  bool get isKnown => state == DreValueState.known && amount != null;
}

class DreDrillItem {
  const DreDrillItem({
    required this.id,
    required this.date,
    required this.description,
    required this.amount,
  });

  final String id;
  final DateTime date;
  final String description;
  final double amount;
}

class DreGroupedLine {
  const DreGroupedLine({
    required this.key,
    required this.label,
    required this.amount,
    required this.items,
  });

  final String key;
  final String label;
  final double amount;
  final List<DreDrillItem> items;
}

class DreHistoricalComponent {
  const DreHistoricalComponent({
    required this.year,
    required this.month,
    this.grossRevenue,
    this.cogs,
  });

  final int year;
  final int month;

  /// Null quando o fechamento não traz o componente. Não vira zero.
  final double? grossRevenue;
  final double? cogs;
}

enum DrePeriodMode { month, year, custom }

/// Período da DRE. O mês vem de [FinancialMonth], sem outro calendário.
class DrePeriod {
  DrePeriod._({
    required this.mode,
    required this.start,
    required this.end,
    required this.label,
    required this.fileStamp,
    required this.months,
  });

  final DrePeriodMode mode;
  final DateTime start;
  final DateTime end;
  final String label;
  final String fileStamp;
  final List<FinancialMonth> months;

  factory DrePeriod.month(FinancialMonth month) {
    return DrePeriod._(
      mode: DrePeriodMode.month,
      start: month.start,
      end: DateTime(month.year, month.month + 1, 0),
      label: '${FinancialMonth.monthNamesPt[month.month - 1]} de ${month.year}',
      fileStamp:
          '${month.year}-${month.month.toString().padLeft(2, '0')}',
      months: [month],
    );
  }

  factory DrePeriod.year(int year, {required DateTime now}) {
    final current = FinancialMonth.fromClock(now);
    final lastMonth = year < current.year ? 12 : current.month;
    final earliest = FinancialMonth(year, 1);
    final latest = FinancialMonth(year, lastMonth);
    final range = FinancialMonthRange(earliest, latest);
    final stamp = lastMonth == 12 ? '$year' : '$year';
    final label = lastMonth == 1
        ? DrePeriod.month(earliest).label
        : lastMonth == 12
            ? 'Janeiro–Dezembro de $year'
            : '${FinancialMonth.monthNamesPt.first}–${FinancialMonth.monthNamesPt[lastMonth - 1]} de $year';
    return DrePeriod._(
      mode: DrePeriodMode.year,
      start: earliest.start,
      end: DateTime(year, lastMonth + 1, 0),
      label: label,
      fileStamp: lastMonth == 12 ? stamp : '$year',
      months: range.months,
    );
  }

  factory DrePeriod.custom({
    required DateTime start,
    required DateTime end,
  }) {
    final from = BrazilBusinessDate.dateOnly(start);
    final to = BrazilBusinessDate.dateOnly(end);
    if (to.isBefore(from)) {
      throw ArgumentError('Período da DRE termina antes de começar.');
    }
    final earliest = FinancialMonth(from.year, from.month);
    final latest = FinancialMonth(to.year, to.month);
    return DrePeriod._(
      mode: DrePeriodMode.custom,
      start: from,
      end: to,
      label: '${formatDreDate(from)}–${formatDreDate(to)}',
      fileStamp:
          '${_stampDay(from)}_${_stampDay(to)}',
      months: FinancialMonthRange(earliest, latest).months,
    );
  }

  FinancialPeriod get financialPeriod => FinancialPeriod(start: start, end: end);
}

class DreStatement {
  const DreStatement({
    required this.storeId,
    required this.storeName,
    required this.period,
    required this.generatedAt,
    required this.grossRevenue,
    required this.discounts,
    required this.discountsIdentified,
    required this.netRevenue,
    required this.cogs,
    required this.cogsComplete,
    required this.salesWithMissingCogs,
    required this.grossProfit,
    required this.grossProfitLabel,
    required this.operatingExpenseLines,
    required this.operatingExpenses,
    required this.operatingExpenseDocumentCount,
    required this.operatingResult,
    required this.operatingResultLabel,
    required this.proLabore,
    required this.ownerWithdrawals,
    required this.investments,
    required this.qualityNotes,
    required this.estimatedCardFee,
    required this.sales,
    required this.usedHistoricalRevenue,
    required this.ignoredCurrentMonthClosure,
  });

  final String storeId;
  final String storeName;
  final DrePeriod period;
  final DateTime generatedAt;
  final DreValue grossRevenue;
  final DreValue discounts;
  final bool discountsIdentified;
  final DreValue netRevenue;
  final DreValue cogs;
  final bool cogsComplete;
  final int salesWithMissingCogs;
  final DreValue grossProfit;
  final String grossProfitLabel;
  final List<DreGroupedLine> operatingExpenseLines;
  final DreValue operatingExpenses;
  final int operatingExpenseDocumentCount;
  final DreValue operatingResult;
  final String operatingResultLabel;
  final DreGroupedLine? proLabore;
  final DreGroupedLine? ownerWithdrawals;
  final DreGroupedLine? investments;
  final List<String> qualityNotes;
  final double? estimatedCardFee;
  final List<DreDrillItem> sales;
  final bool usedHistoricalRevenue;
  final bool ignoredCurrentMonthClosure;

  static const bool netProfitSupported = false;

  String get totalsFingerprint => [
        grossRevenue.amount,
        discounts.amount,
        netRevenue.amount,
        cogs.amount,
        grossProfit.amount,
        operatingExpenses.amount,
        operatingResult.amount,
      ].join('|');
}

class DreReadInput {
  const DreReadInput({
    required this.storeId,
    required this.storeName,
    required this.period,
    required this.now,
    required this.generatedAt,
    this.sales = const [],
    this.entries = const [],
    this.saleTombstones = const {},
    this.historicalComponents = const [],
    this.salesLoaded = true,
    this.expensesLoaded = true,
    this.discountSnapshotsPresent = true,
    this.estimatedCardFee,
  });

  final String storeId;
  final String storeName;
  final DrePeriod period;
  final DateTime now;
  final DateTime generatedAt;
  final List<Venda> sales;
  final List<LancamentoFinanceiro> entries;
  final Set<String> saleTombstones;
  final List<DreHistoricalComponent> historicalComponents;
  final bool salesLoaded;
  final bool expensesLoaded;
  final bool discountSnapshotsPresent;
  final double? estimatedCardFee;
}

abstract final class FinancialDreRead {
  static DreStatement calculate(DreReadInput input) {
    final store = input.storeId.trim();
    final period = input.period.financialPeriod;
    final notes = <String>[];
    final included = <Venda>[];
    for (final sale in input.sales) {
      if ((sale.lojaId ?? '').trim() != store) continue;
      if (!period.contains(sale.data)) continue;
      if (!incluirVendaEmMetricas(sale, tombstonesExclusao: input.saleTombstones)) {
        continue;
      }
      included.add(sale);
    }

    final seenConsignment = <String>{};
    final saleRows = <DreDrillItem>[];
    var gross = 0.0;
    var discounts = 0.0;
    var knownCogs = 0.0;
    var knownCogsCount = 0;
    var missingCogs = 0;
    var ignoredClosure = false;

    if (input.salesLoaded) {
      for (final sale in included) {
        final economic = FinancialMetricsCalculator.consignmentEconomicIdFromSale(sale);
        if (economic != null && !seenConsignment.add(economic)) continue;
        final discount = input.discountSnapshotsPresent ? sale.descontoValor : 0.0;
        final revenue = input.discountSnapshotsPresent
            ? sale.total + sale.descontoValor
            : sale.total;
        gross += revenue;
        discounts += discount;
        saleRows.add(
          DreDrillItem(
            id: (sale.idFirebase ?? '').trim().isEmpty
                ? sale.data.toIso8601String()
                : sale.idFirebase!.trim(),
            date: sale.data,
            description: sale.clienteNome.trim().isEmpty
                ? 'Venda'
                : sale.clienteNome.trim(),
            amount: revenue,
          ),
        );
        final cost = FinancialMetricsCalculator.saleCostRead(sale);
        if (cost.grossProfitAvailable && cost.cogs != null) {
          knownCogs += cost.cogs!;
          knownCogsCount++;
        } else {
          missingCogs++;
        }
      }
    }

    final monthsWithSales = <int>{
      for (final sale in included)
        FinancialMonth.fromInstant(sale.data).orderKey,
    };
    var historicalRevenue = 0.0;
    var historicalCogs = 0.0;
    var historicalRevenueUsed = false;
    var historicalCogsKnown = true;
    var historicalCogsAny = false;
    for (final component in input.historicalComponents) {
      final month = FinancialMonth(component.year, component.month);
      if (!input.period.months.any((m) => m.orderKey == month.orderKey)) {
        continue;
      }
      final monthEnd = DateTime(month.year, month.month + 1, 0);
      if (!periodIsCompletePastMonth(
        start: month.start,
        end: monthEnd,
        now: input.now,
      )) {
        ignoredClosure = true;
        continue;
      }
      if (monthsWithSales.contains(month.orderKey)) continue;
      if (component.grossRevenue == null) continue;
      historicalRevenueUsed = true;
      historicalRevenue += component.grossRevenue!;
      if (component.cogs == null) {
        historicalCogsKnown = false;
      } else {
        historicalCogs += component.cogs!;
        historicalCogsAny = true;
      }
    }

    final DreValue grossValue;
    final DreValue discountValue;
    final DreValue netValue;
    if (!input.salesLoaded && !historicalRevenueUsed) {
      grossValue = const DreValue.unavailable();
      discountValue = const DreValue.unavailable();
      netValue = const DreValue.unavailable();
    } else {
      final saleGross = input.salesLoaded ? gross : 0.0;
      final grossAmount = _money(saleGross + historicalRevenue);
      grossValue = DreValue.known(grossAmount);
      final onlyHistorical = historicalRevenueUsed && saleGross == 0;
      if (onlyHistorical || !input.discountSnapshotsPresent) {
        discountValue = const DreValue.unavailable();
        netValue = DreValue.known(grossAmount);
        notes.add(
          onlyHistorical
              ? 'Descontos não identificados separadamente no fechamento histórico.'
              : 'Descontos não identificados separadamente.',
        );
      } else {
        final discountAmount = _money(discounts);
        discountValue = DreValue.known(discountAmount);
        netValue = DreValue.known(_money(grossAmount - discountAmount));
        if (historicalRevenueUsed) {
          notes.add(
            'Descontos do fechamento histórico não identificados separadamente.',
          );
        }
      }
    }

    final totalSalesForCogs = (input.salesLoaded ? included.length : 0);
    final DreValue cogsValue;
    var cogsComplete = false;
    if (missingCogs > 0 && knownCogsCount > 0) {
      cogsValue = DreValue.known(_money(knownCogs + (historicalCogsAny ? historicalCogs : 0)));
      cogsComplete = false;
      notes.add(
        '$missingCogs venda(s) sem custo histórico. O CMV mostrado é só o conhecido; custo ausente não entra como zero.',
      );
    } else if (missingCogs > 0 && knownCogsCount == 0 && !historicalCogsAny) {
      cogsValue = const DreValue.unavailable();
      notes.add(
        '$missingCogs venda(s) sem custo histórico. CMV indisponível; custo ausente não foi lançado como zero.',
      );
    } else if (historicalRevenueUsed && !historicalCogsKnown) {
      cogsValue = const DreValue.unavailable();
      notes.add(
        'CMV indisponível: o fechamento histórico não traz custo das mercadorias.',
      );
    } else if (!input.salesLoaded && !historicalRevenueUsed) {
      cogsValue = const DreValue.unavailable();
    } else if (totalSalesForCogs == 0 && !historicalCogsAny && !historicalRevenueUsed) {
      cogsValue = const DreValue.known(0);
      cogsComplete = true;
    } else {
      cogsValue = DreValue.known(_money(knownCogs + historicalCogs));
      cogsComplete = missingCogs == 0 && historicalCogsKnown && !historicalRevenueUsed;
    }

    final DreValue grossProfit;
    final String grossProfitLabel;
    if (netValue.isKnown && cogsValue.isKnown && cogsComplete && missingCogs == 0) {
      grossProfit = DreValue.known(_money(netValue.amount! - cogsValue.amount!));
      grossProfitLabel = 'LUCRO BRUTO';
    } else if (historicalRevenueUsed && netValue.isKnown && cogsValue.isKnown) {
      grossProfit = DreValue.known(_money(netValue.amount! - cogsValue.amount!));
      grossProfitLabel = 'LUCRO BRUTO CONHECIDO';
      notes.add(
        'Lucro bruto conhecido a partir do fechamento; não é um CMV auditado item a item.',
      );
    } else if (netValue.isKnown && cogsValue.isKnown) {
      grossProfit = DreValue.known(_money(netValue.amount! - cogsValue.amount!));
      grossProfitLabel = 'LUCRO BRUTO CONHECIDO';
      notes.add(
        'Lucro bruto conhecido: ainda há venda sem custo histórico ou componente incompleto.',
      );
    } else {
      grossProfit = const DreValue.unavailable();
      grossProfitLabel = 'LUCRO BRUTO';
      notes.add('Lucro bruto indisponível enquanto o CMV não estiver completo.');
    }

    final operating = <String, List<DreDrillItem>>{};
    final operatingLabels = <String, String>{};
    final proLaboreItems = <DreDrillItem>[];
    final withdrawalItems = <DreDrillItem>[];
    final investmentItems = <DreDrillItem>[];

    if (input.expensesLoaded) {
      for (final entry in input.entries) {
        if (entry.lojaId.trim() != store) continue;
        if (!_statusAceito(entry.status)) continue;
        if (!_competenciaNoPeriodo(entry, period)) continue;
        if (_foraDaDre(entry)) continue;
        final item = DreDrillItem(
          id: entry.id,
          date: entry.dataLancamento,
          description: entry.descricao.trim().isEmpty ? entry.categoria : entry.descricao.trim(),
          amount: _money(entry.valor.abs()),
        );
        final tipo = entry.tipo;
        if (tipo == FinanceiroTipoLancamento.proLabore) {
          proLaboreItems.add(item);
        } else if (tipo == FinanceiroTipoLancamento.retirada) {
          withdrawalItems.add(item);
        } else if (tipo == FinanceiroTipoLancamento.investimento) {
          investmentItems.add(item);
        } else if (_ehDespesaOperacional(entry)) {
          final key = _linhaOperacionalKey(entry);
          operating.putIfAbsent(key, () => []).add(item);
          operatingLabels[key] = _linhaOperacionalLabel(entry);
        }
      }
    }

    final operatingLines = [
      for (final key in operating.keys)
        DreGroupedLine(
          key: key,
          label: operatingLabels[key] ?? key,
          amount: _money(operating[key]!.fold(0.0, (s, e) => s + e.amount)),
          items: operating[key]!,
        ),
    ];
    final expenseCount = operating.values.fold<int>(0, (s, e) => s + e.length);
    final onlyHistoricalRevenue = historicalRevenueUsed &&
        !(input.salesLoaded && included.isNotEmpty);
    final DreValue expenseValue;
    if (!input.expensesLoaded || (onlyHistoricalRevenue && expenseCount == 0)) {
      expenseValue = const DreValue.unavailable();
      notes.add(
        'Despesas operacionais indisponíveis: não há valor confirmado no período.',
      );
    } else {
      expenseValue = DreValue.known(
        _money(operatingLines.fold(0.0, (s, e) => s + e.amount)),
      );
      notes.add(
        'Este resultado considera as despesas registradas no MasterPalm. Despesas não lançadas não podem ser incluídas.',
      );
    }
    if (cogsComplete && missingCogs == 0 && cogsValue.isKnown) {
      notes.add('CMV histórico completo.');
    }

    final DreValue operatingResult;
    final String operatingResultLabel;
    if (grossProfit.isKnown && expenseValue.isKnown && cogsComplete && missingCogs == 0) {
      operatingResult = DreValue.known(
        _money(grossProfit.amount! - expenseValue.amount!),
      );
      operatingResultLabel = 'RESULTADO OPERACIONAL';
    } else if (grossProfit.isKnown && expenseValue.isKnown) {
      operatingResult = DreValue.known(
        _money(grossProfit.amount! - expenseValue.amount!),
      );
      operatingResultLabel = 'RESULTADO OPERACIONAL CONHECIDO';
    } else {
      operatingResult = const DreValue.unavailable();
      operatingResultLabel = 'RESULTADO OPERACIONAL';
      notes.add('Resultado operacional indisponível: falta componente confiável.');
    }

    if (input.estimatedCardFee != null) {
      notes.add(
        'Taxas de cartão estimadas (${formatDreMoney(input.estimatedCardFee!)}): ESTIMATIVA, fora do resultado.',
      );
    } else {
      notes.add('Taxas de cartão reais não confirmadas no período.');
    }
    notes.add(
      'Tributos não incluídos: não há valor contábil confirmado no período.',
    );
    if (investmentItems.isNotEmpty) {
      notes.add('Investimentos exibidos separadamente, fora do resultado operacional.');
    }
    if (withdrawalItems.isNotEmpty) {
      notes.add('Retiradas não fazem parte do resultado operacional.');
    }
    if (historicalRevenueUsed) {
      notes.add(
        'Histórico parcial: receita de mês sem vendas brutas veio do fechamento, sem completar CMV ou despesa ausente.',
      );
    }
    if (!input.expensesLoaded || (historicalRevenueUsed && !historicalCogsKnown)) {
      notes.add('Histórico parcial.');
    }

    DreGroupedLine? groupOrNull(String key, String label, List<DreDrillItem> items) {
      if (items.isEmpty) return null;
      return DreGroupedLine(
        key: key,
        label: label,
        amount: _money(items.fold(0.0, (s, e) => s + e.amount)),
        items: items,
      );
    }

    return DreStatement(
      storeId: store,
      storeName: input.storeName,
      period: input.period,
      generatedAt: input.generatedAt,
      grossRevenue: grossValue,
      discounts: discountValue,
      discountsIdentified: discountValue.isKnown,
      netRevenue: netValue,
      cogs: cogsValue,
      cogsComplete: cogsComplete,
      salesWithMissingCogs: missingCogs,
      grossProfit: grossProfit,
      grossProfitLabel: grossProfitLabel,
      operatingExpenseLines: operatingLines,
      operatingExpenses: expenseValue,
      operatingExpenseDocumentCount: expenseCount,
      operatingResult: operatingResult,
      operatingResultLabel: operatingResultLabel,
      proLabore: groupOrNull('pro_labore', 'Pró-labore', proLaboreItems),
      ownerWithdrawals: groupOrNull(
        'retirada_financeira',
        'Retiradas',
        withdrawalItems,
      ),
      investments: groupOrNull('investimento', 'Investimentos', investmentItems),
      qualityNotes: notes,
      estimatedCardFee: input.estimatedCardFee,
      sales: saleRows,
      usedHistoricalRevenue: historicalRevenueUsed,
      ignoredCurrentMonthClosure: ignoredClosure,
    );
  }
}

class DreRenderRow {
  const DreRenderRow({
    required this.label,
    required this.amount,
    required this.emphasis,
  });

  final String label;
  final String amount;
  final bool emphasis;
}

/// Linhas já calculadas. Tela, impressão e PDF leem esta lista.
abstract final class DrePresentation {
  static List<DreRenderRow> rows(DreStatement statement) {
    String money(DreValue value) =>
        value.isKnown ? formatDreMoney(value.amount!) : 'Indisponível';
    return [
      DreRenderRow(
        label: 'RECEITA BRUTA DE VENDAS',
        amount: money(statement.grossRevenue),
        emphasis: true,
      ),
      DreRenderRow(
        label: '(-) DESCONTOS CONCEDIDOS',
        amount: statement.discountsIdentified
            ? money(statement.discounts)
            : 'Não identificado',
        emphasis: false,
      ),
      DreRenderRow(
        label: '= RECEITA LÍQUIDA',
        amount: money(statement.netRevenue),
        emphasis: true,
      ),
      DreRenderRow(
        label: statement.cogsComplete
            ? '(-) CUSTO DAS MERCADORIAS VENDIDAS — CMV'
            : '(-) CMV CONHECIDO',
        amount: money(statement.cogs),
        emphasis: false,
      ),
      DreRenderRow(
        label: '= ${statement.grossProfitLabel}',
        amount: money(statement.grossProfit),
        emphasis: true,
      ),
      for (final line in statement.operatingExpenseLines)
        DreRenderRow(
          label: line.label,
          amount: formatDreMoney(line.amount),
          emphasis: false,
        ),
      DreRenderRow(
        label: statement.operatingExpenses.isKnown
            ? '(-) DESPESAS OPERACIONAIS REGISTRADAS'
            : '(-) DESPESAS OPERACIONAIS',
        amount: money(statement.operatingExpenses),
        emphasis: false,
      ),
      DreRenderRow(
        label: '= ${statement.operatingResultLabel}',
        amount: money(statement.operatingResult),
        emphasis: true,
      ),
      if (statement.proLabore != null)
        DreRenderRow(
          label: 'Pró-labore',
          amount: formatDreMoney(statement.proLabore!.amount),
          emphasis: false,
        ),
      if (statement.ownerWithdrawals != null)
        DreRenderRow(
          label: 'Retiradas',
          amount: formatDreMoney(statement.ownerWithdrawals!.amount),
          emphasis: false,
        ),
      if (statement.investments != null)
        DreRenderRow(
          label: 'Investimentos',
          amount: formatDreMoney(statement.investments!.amount),
          emphasis: false,
        ),
      if (statement.estimatedCardFee != null)
        const DreRenderRow(
          label: 'Taxas de cartão estimadas',
          amount: 'ESTIMATIVA',
          emphasis: false,
        ),
    ];
  }

  static String fingerprint(DreStatement statement) => statement.totalsFingerprint;
}

bool _statusAceito(String status) {
  final s = status.trim().toLowerCase();
  return s != 'cancelado' && s != 'excluido' && s != 'estornado';
}

bool _competenciaNoPeriodo(LancamentoFinanceiro entry, FinancialPeriod period) {
  final competence = DateTime(entry.competenciaAno, entry.competenciaMes, 15);
  return period.contains(competence);
}

bool _foraDaDre(LancamentoFinanceiro entry) {
  if (entry.origem == FinanceiroOrigemLancamento.contaPagarCompra) return true;
  if (entry.origem == FinanceiroOrigemLancamento.contaReceberFiado) return true;
  if (FinancialMetricsCalculator.consignmentEconomicIdFromEntry(entry) != null) {
    return true;
  }
  final tipo = entry.tipo;
  if (tipo == FinanceiroTipoLancamento.compraMercadoria) return true;
  if (tipo == FinanceiroTipoLancamento.entradaExtra) return true;
  if (tipo == FinanceiroTipoLancamento.ajusteFinanceiro) return true;
  return false;
}

bool _ehDespesaOperacional(LancamentoFinanceiro entry) {
  if (_categoriaMercadoria(entry.categoria)) return false;
  final tipo = entry.tipo;
  return tipo == FinanceiroTipoLancamento.despesaOperacional ||
      tipo == FinanceiroTipoLancamento.gastoFixo ||
      tipo == FinanceiroTipoLancamento.gastoVariavel ||
      tipo == FinanceiroTipoLancamento.pagamentoFuncionario;
}

bool _categoriaMercadoria(String categoria) {
  final key = categoria.trim();
  for (final item in kFinanceiroCategoriasPadrao) {
    if (item.categoria == key && item.grupo == FinanceiroGrupoCategoria.estoque) {
      return true;
    }
  }
  return false;
}

String _linhaOperacionalKey(LancamentoFinanceiro entry) {
  if (entry.tipo == FinanceiroTipoLancamento.pagamentoFuncionario) {
    return 'pagamento_funcionario';
  }
  final categoria = entry.categoria.trim();
  if (categoria.isEmpty) return entry.tipo;
  return categoria;
}

String _linhaOperacionalLabel(LancamentoFinanceiro entry) {
  if (entry.tipo == FinanceiroTipoLancamento.pagamentoFuncionario) {
    return 'Salários / equipe';
  }
  return dreCategoriaLabel(entry.categoria.trim().isEmpty ? entry.tipo : entry.categoria);
}

String dreCategoriaLabel(String categoria) {
  const known = {
    'internet': 'Internet',
    'aluguel': 'Aluguel',
    'energia': 'Energia',
    'agua': 'Água',
    'contador': 'Contabilidade',
    'embalagens': 'Embalagens',
    'marketing': 'Marketing',
    'trafego_pago': 'Tráfego pago',
    'manutencao': 'Manutenção',
    'frete': 'Fretes',
  };
  final key = categoria.trim();
  if (known.containsKey(key)) return known[key]!;
  if (key.isEmpty) return 'Outras despesas operacionais';
  final words = key.split('_').where((w) => w.isNotEmpty).map((w) {
    return '${w[0].toUpperCase()}${w.substring(1)}';
  });
  return words.join(' ');
}

double _money(double value) => (value * 100).roundToDouble() / 100.0;

String formatDreMoney(double value) {
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts[0];
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write('.');
    buffer.write(whole[i]);
  }
  return '${negative ? '-' : ''}R\$ ${buffer.toString()},${parts[1]}';
}

String formatDreDate(DateTime date) {
  final d = date.day.toString().padLeft(2, '0');
  final m = date.month.toString().padLeft(2, '0');
  return '$d/$m/${date.year}';
}

String formatDreDateTime(DateTime date) {
  final h = date.hour.toString().padLeft(2, '0');
  final min = date.minute.toString().padLeft(2, '0');
  return '${formatDreDate(date)} $h:$min';
}

String _stampDay(DateTime date) {
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '${date.year}-$m-$d';
}

String dreStoreFileSlug(String storeName) {
  final words = storeName
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && w.toLowerCase() != 'e')
      .take(2)
      .map((w) => w.replaceAll(RegExp(r'[^A-Za-z0-9]'), ''))
      .where((w) => w.isNotEmpty);
  final slug = words.join('_');
  return slug.isEmpty ? 'Loja' : slug;
}

String dreFileName(DreStatement statement) {
  return 'DRE_${dreStoreFileSlug(statement.storeName)}_${statement.period.fileStamp}.pdf';
}
