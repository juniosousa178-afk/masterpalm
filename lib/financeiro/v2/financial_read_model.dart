// Modelo de leitura Financial V2 — fase 1A.
// Só calcula. Não grava venda, estoque, fiado, contas a pagar, lançamento,
// consignação, catálogo nem ledger.

import '../../core/conta_receber_cache_authority.dart';
import '../../core/conta_receber_remote_authority.dart';
import '../../core/venda_metrics_filter.dart';
import '../../financeiro/financeiro_constants.dart';
import '../../models/conta_pagar.dart';
import '../../models/conta_pagar_constants.dart';
import '../../models/conta_receber.dart';
import '../../models/lancamento_financeiro.dart';
import '../../models/venda.dart';
import '../../models/venda_item.dart';
import 'brazil_business_date.dart';
import 'financial_authority.dart';
import 'financial_warnings.dart';

const double kFinancialReadEpsilon = 0.01;

/// Plano de leitura por período. O caller não deve baixar o histórico inteiro.
abstract final class FinancialSourceQueryPlan {
  static const sales =
      'lojas/{storeId}/estoque_vendas filtrado por lojaId e data da venda no período';
  static const receivablesOpen =
      'lojas/{storeId}/contas_receber abertas/parciais (estado atual, não histórico pago)';
  static const entries =
      'lojas/{storeId}/lancamentos_financeiros com data de pagamento no período e lojaId';
  static const payables =
      'Hive contas_pagar_{storeId} abertas — authority=LOCAL_ONLY, sem coleção remota';
  static const fixedCosts =
      'lojas/{storeId}/gastos_fixos_mensais só como cadastro; o caixa usa o lançamento gerado';
  static const purchases =
      'lojas/{storeId}/compras_fornecedor no período da compra; saída de caixa só no lançamento pago';
  static const consignments =
      'lojas/{storeId}/consignments com settledAt no período; efeito financeiro lido da venda csgn_ e do lançamento csgn_fin_ já existentes';
}

class FinancialPeriod {
  FinancialPeriod({
    required DateTime start,
    required DateTime end,
  })  : periodStart = BrazilBusinessDate.dateOnly(start),
        periodEnd = BrazilBusinessDate.dateOnly(end) {
    if (periodEnd.isBefore(periodStart)) {
      throw ArgumentError('periodEnd anterior a periodStart.');
    }
  }

  final DateTime periodStart;
  final DateTime periodEnd;

  bool contains(DateTime instant) {
    return BrazilBusinessDate.inInclusiveRange(
      instant: instant,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
  }
}

class SaleCostRead {
  const SaleCostRead({
    required this.grossProfitAvailable,
    required this.revenue,
    required this.cogs,
    required this.incomplete,
    required this.consignmentArtificialZero,
  });

  final bool grossProfitAvailable;
  final double revenue;
  final double? cogs;
  final bool incomplete;
  final bool consignmentArtificialZero;
}

class CardFeeRead {
  const CardFeeRead({
    required this.actualCardFee,
    required this.estimatedCardFee,
    required this.label,
  });

  /// Sempre null nesta fase: a venda não grava taxa real de cartão.
  final double? actualCardFee;

  /// Estimativa de config, se o caller passar. Nunca entra no ledger.
  final double? estimatedCardFee;
  final String label;

  static const estimatedLabel = 'ESTIMATED';
}

class FinancialDataSources {
  FinancialDataSources._({
    required this.storeId,
    required this.period,
    required this.today,
    required this.sales,
    required this.receivables,
    required this.entries,
    required this.payables,
    required this.saleTombstones,
    required this.estimatedCardFee,
  });

  final String storeId;
  final FinancialPeriod period;
  final DateTime today;
  final List<Venda> sales;
  final List<ContaReceber> receivables;
  final List<LancamentoFinanceiro> entries;
  final List<ContaPagar> payables;
  final Set<String> saleTombstones;

  /// Opcional e rotulado ESTIMATED. Não é taxa real.
  final double? estimatedCardFee;

  static const String payablesAuthorityLabel = 'LOCAL_ONLY';

  factory FinancialDataSources.scoped({
    required String storeId,
    required FinancialPeriod period,
    required DateTime today,
    Iterable<Venda> sales = const [],
    Iterable<ContaReceber> receivables = const [],
    Iterable<LancamentoFinanceiro> entries = const [],
    Iterable<ContaPagar> payables = const [],
    Set<String> saleTombstones = const {},
    double? estimatedCardFee,
  }) {
    final store = storeId.trim();
    if (store.isEmpty) {
      throw ArgumentError('storeId explícito é obrigatório.');
    }
    bool sameStore(String? id) => (id ?? '').trim() == store;
    return FinancialDataSources._(
      storeId: store,
      period: period,
      today: today,
      sales: [
        for (final v in sales)
          if (sameStore(v.lojaId)) v,
      ],
      receivables: [
        for (final c in receivables)
          if (sameStore(c.lojaId)) c,
      ],
      entries: [
        for (final l in entries)
          if (sameStore(l.lojaId)) l,
      ],
      payables: [
        for (final p in payables)
          if (sameStore(p.lojaId)) p,
      ],
      saleTombstones: saleTombstones,
      estimatedCardFee: estimatedCardFee,
    );
  }
}

class FinancialOverviewReadModel {
  const FinancialOverviewReadModel({
    required this.storeId,
    required this.periodStart,
    required this.periodEnd,
    required this.grossSales,
    required this.cashInflows,
    required this.cashOutflows,
    required this.netCashMovement,
    required this.openReceivables,
    required this.overdueReceivables,
    required this.openPayables,
    required this.payablesAuthority,
    required this.grossProfitKnownAmount,
    required this.grossProfitIncompleteSaleCount,
    required this.saleCogsSnapshot,
    required this.cashPurchaseOutflow,
    required this.consignmentSettlementCount,
    required this.deduplicatedConsignmentCount,
    required this.receivablePaymentCount,
    required this.deduplicatedReceivablePaymentCount,
    required this.dataQualityWarnings,
    required this.actualCardFee,
    required this.estimatedCardFee,
    required this.cardFeeLabel,
    required this.grossSalesAuthority,
    required this.cashAuthority,
    required this.receivablesAuthority,
    required this.grossProfitAuthority,
    required this.availableBalanceSupported,
  });

  final String storeId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final double grossSales;
  final double cashInflows;
  final double cashOutflows;
  final double netCashMovement;
  final double openReceivables;
  final double overdueReceivables;
  final double openPayables;
  final FinancialAuthority payablesAuthority;
  final double grossProfitKnownAmount;
  final int grossProfitIncompleteSaleCount;
  final double saleCogsSnapshot;
  final double cashPurchaseOutflow;
  final int consignmentSettlementCount;
  final int deduplicatedConsignmentCount;
  final int receivablePaymentCount;
  final int deduplicatedReceivablePaymentCount;
  final List<String> dataQualityWarnings;
  final double? actualCardFee;
  final double? estimatedCardFee;
  final String? cardFeeLabel;
  final FinancialAuthority grossSalesAuthority;
  final FinancialAuthority cashAuthority;
  final FinancialAuthority receivablesAuthority;
  final FinancialAuthority grossProfitAuthority;
  final bool availableBalanceSupported;
}

abstract final class FinancialMetricsCalculator {
  static FinancialOverviewReadModel overview(FinancialDataSources sources) {
    final warnings = <String>{
      FinancialDataQualityWarning.payablesLocalOnly,
      FinancialDataQualityWarning.cardFeeEstimatedOnly,
      FinancialDataQualityWarning.noFinancialAccounts,
      FinancialDataQualityWarning.noOpeningBalance,
    };

    final includedSales = <Venda>[
      for (final v in sources.sales)
        if (sources.period.contains(v.data) &&
            incluirVendaEmMetricas(
              v,
              tombstonesExclusao: sources.saleTombstones,
            ))
          v,
    ];

    var grossSales = 0.0;
    var cashFromSaleTenders = 0.0;
    var knownProfit = 0.0;
    var knownCogs = 0.0;
    var incomplete = 0;
    final consignmentIds = <String>{};

    for (final sale in includedSales) {
      grossSales += sale.total;
      cashFromSaleTenders += _tenderCash(sale);
      final cost = saleCostRead(sale);
      if (cost.grossProfitAvailable && cost.cogs != null) {
        knownProfit += cost.revenue - cost.cogs!;
        knownCogs += cost.cogs!;
      } else {
        incomplete++;
        if (cost.consignmentArtificialZero) {
          warnings.add(FinancialDataQualityWarning.consignmentCogsUnknown);
        } else if (cost.incomplete) {
          warnings.add(FinancialDataQualityWarning.historicalSaleMissingCogs);
          warnings.add(FinancialDataQualityWarning.incompleteCostData);
        }
      }
      final economic = consignmentEconomicIdFromSale(sale);
      if (economic != null) consignmentIds.add(economic);
    }

    final paymentKeys = <String>{};
    var cashFromReceivablePayments = 0.0;

    for (final conta in sources.receivables) {
      if (!contaReceberVisibleAsAuthoritativeOpen(conta) &&
          conta.historicoPagamentos().isEmpty) {
        continue;
      }
      for (final raw in conta.historicoPagamentos()) {
        if (raw['estornada'] == true) continue;
        final amount = (raw['valor'] as num?)?.toDouble() ?? 0;
        if (amount <= kFinancialReadEpsilon) continue;
        final when = _parseWhen(raw['data']);
        if (when == null || !sources.period.contains(when)) continue;
        final key = _receivablePaymentKey(conta, raw, amount, when);
        if (!paymentKeys.add(key)) continue;
        cashFromReceivablePayments += amount;
      }
    }

    var cashFromEntries = 0.0;
    var cashOut = 0.0;
    var purchaseOut = 0.0;
    for (final entry in sources.entries) {
      if (!FinanceiroStatusLancamento.statusLiquidado(entry.status)) continue;
      final when = entry.dataEfetivaPagamentoOuLancamento;
      if (!sources.period.contains(when)) continue;

      final consignmentId = consignmentEconomicIdFromEntry(entry);
      if (consignmentId != null) consignmentIds.add(consignmentId);

      if (_isReceivableMirror(entry, paymentKeys)) {
        continue;
      }
      if (entry.origem == FinanceiroOrigemLancamento.contaReceberFiado ||
          _looksLikeReceivableRef(entry)) {
        final key = 'entry:${entry.id.trim()}';
        if (!paymentKeys.add(key)) continue;
        if (entry.tipo == FinanceiroTipoLancamento.entradaExtra) {
          cashFromEntries += entry.valor.abs();
        }
        continue;
      }

      final tipo = entry.tipo;
      if (tipo == FinanceiroTipoLancamento.entradaExtra) {
        cashFromEntries += entry.valor.abs();
      } else if (tipo == FinanceiroTipoLancamento.ajusteFinanceiro) {
        if (entry.valor >= 0) {
          cashFromEntries += entry.valor;
        } else {
          cashOut += entry.valor.abs();
        }
      } else if (tipo == FinanceiroTipoLancamento.compraMercadoria) {
        final v = entry.valor.abs();
        purchaseOut += v;
        cashOut += v;
      } else if (tipo == FinanceiroTipoLancamento.gastoFixo ||
          tipo == FinanceiroTipoLancamento.gastoVariavel ||
          tipo == FinanceiroTipoLancamento.despesaOperacional ||
          tipo == FinanceiroTipoLancamento.investimento ||
          tipo == FinanceiroTipoLancamento.pagamentoFuncionario ||
          tipo == FinanceiroTipoLancamento.proLabore ||
          tipo == FinanceiroTipoLancamento.retirada) {
        cashOut += entry.valor.abs();
      } else {
        cashOut += entry.valor.abs();
      }
    }

    var openReceivables = 0.0;
    var overdue = 0.0;
    for (final conta in sources.receivables) {
      if (!contaReceberVisibleAsAuthoritativeOpen(conta)) continue;
      openReceivables += conta.saldoRestante;
      if (BrazilBusinessDate.isBeforeDay(conta.dataVencimento, sources.today)) {
        overdue += conta.saldoRestante;
      }
    }

    var openPayables = 0.0;
    for (final parcela in sources.payables) {
      if (!parcela.estaAberta) continue;
      openPayables += parcela.valorParcela;
    }

    final inflows = cashFromSaleTenders +
        cashFromReceivablePayments +
        cashFromEntries;
    final card = cardFeeRead(estimated: sources.estimatedCardFee);

    return FinancialOverviewReadModel(
      storeId: sources.storeId,
      periodStart: sources.period.periodStart,
      periodEnd: sources.period.periodEnd,
      grossSales: grossSales,
      cashInflows: inflows,
      cashOutflows: cashOut,
      netCashMovement: inflows - cashOut,
      openReceivables: openReceivables,
      overdueReceivables: overdue,
      openPayables: openPayables,
      payablesAuthority: FinancialAuthority.localOnly,
      grossProfitKnownAmount: knownProfit,
      grossProfitIncompleteSaleCount: incomplete,
      saleCogsSnapshot: knownCogs,
      cashPurchaseOutflow: purchaseOut,
      consignmentSettlementCount: consignmentIds.length,
      deduplicatedConsignmentCount: consignmentIds.length,
      receivablePaymentCount: paymentKeys.length,
      deduplicatedReceivablePaymentCount: paymentKeys.length,
      dataQualityWarnings: warnings.toList()..sort(),
      actualCardFee: card.actualCardFee,
      estimatedCardFee: card.estimatedCardFee,
      cardFeeLabel: card.estimatedCardFee == null ? null : card.label,
      grossSalesAuthority: FinancialAuthority.derived,
      cashAuthority: FinancialAuthority.derived,
      receivablesAuthority: FinancialAuthority.remoteAuthoritative,
      grossProfitAuthority: FinancialAuthority.derived,
      availableBalanceSupported: false,
    );
  }

  static bool contaReceberVisibleAsAuthoritativeOpen(ContaReceber conta) {
    if (!contaReceberVisibleInActiveReceivables(conta)) return false;
    return isTrustedRemoteOpenDebt(conta);
  }

  static SaleCostRead saleCostRead(Venda sale) {
    final revenue = sale.total;
    if (isConsignmentSettlementSale(sale)) {
      return SaleCostRead(
        grossProfitAvailable: false,
        revenue: revenue,
        cogs: null,
        incomplete: true,
        consignmentArtificialZero: true,
      );
    }
    final items = sale.itens ?? const <VendaItem>[];
    final hasExplicitLineCost = items.any((it) => it.custoUnitario != null);
    final hasAggregate = sale.custoProdutos > kFinancialReadEpsilon;
    if (!hasExplicitLineCost && !hasAggregate) {
      return SaleCostRead(
        grossProfitAvailable: false,
        revenue: revenue,
        cogs: null,
        incomplete: true,
        consignmentArtificialZero: false,
      );
    }
    return SaleCostRead(
      grossProfitAvailable: true,
      revenue: revenue,
      cogs: sale.custoProdutos,
      incomplete: false,
      consignmentArtificialZero: false,
    );
  }

  static CardFeeRead cardFeeRead({double? estimated}) {
    return CardFeeRead(
      actualCardFee: null,
      estimatedCardFee: estimated,
      label: CardFeeRead.estimatedLabel,
    );
  }

  static bool isConsignmentSettlementSale(Venda sale) {
    return consignmentEconomicIdFromSale(sale) != null;
  }

  static String? consignmentEconomicIdFromSale(Venda sale) {
    final origem = (sale.origemVenda ?? '').trim().toLowerCase();
    final id = (sale.idFirebase ?? '').trim();
    final formas = sale.formasPagamento.toLowerCase();
    if (origem == 'consignment' ||
        id.startsWith('csgn_') ||
        formas.contains('consignacao') ||
        formas.contains('consignação')) {
      if (id.startsWith('csgn_fin_')) {
        return id.substring('csgn_fin_'.length);
      }
      if (id.startsWith('csgn_')) {
        return id.substring('csgn_'.length);
      }
      return id.isEmpty ? 'consignment-unkeyed' : id;
    }
    return null;
  }

  static String? consignmentEconomicIdFromEntry(LancamentoFinanceiro entry) {
    final origem = entry.origem.trim().toLowerCase();
    final id = entry.id.trim();
    final ref = entry.referenciaExterna.trim();
    final cat = entry.categoria.trim().toLowerCase();
    final isConsignment = origem == 'consignment' ||
        id.startsWith('csgn_fin_') ||
        cat == 'consignacao';
    if (!isConsignment) return null;
    if (id.startsWith('csgn_fin_')) return id.substring('csgn_fin_'.length);
    if (ref.isNotEmpty) return ref;
    return id;
  }

  static double _tenderCash(Venda sale) {
    final dinheiro = sale.pagamentoDinheiro;
    final pix = sale.pagamentoPix;
    final cartao = sale.pagamentoCartao;
    final sum = dinheiro + pix + cartao;
    if (sum <= kFinancialReadEpsilon) return 0;
    return sum;
  }

  static DateTime? _parseWhen(dynamic raw) {
    if (raw is DateTime) return raw;
    if (raw is String && raw.trim().isNotEmpty) {
      return DateTime.tryParse(raw.trim());
    }
    return null;
  }

  static String _receivablePaymentKey(
    ContaReceber conta,
    Map<String, dynamic> raw,
    double amount,
    DateTime when,
  ) {
    final baixa = (raw['baixaId'] ?? '').toString().trim();
    if (baixa.isNotEmpty) return 'baixa:$baixa';
    final ref = (raw['referenciaFinanceira'] ?? '').toString().trim();
    if (ref.isNotEmpty) return 'ref:$ref';
    final doc = (conta.idFirebase ?? '').trim();
    final cents = (amount * 100).round();
    final day = BrazilBusinessDate.dateOnly(when);
    return 'fallback:$doc:$cents:${day.toIso8601String()}';
  }

  static bool _looksLikeReceivableRef(LancamentoFinanceiro entry) {
    final ref = entry.referenciaExterna.trim();
    final id = entry.id.trim();
    return ref.startsWith('cr_receb') ||
        ref.startsWith('mp_cr2_') ||
        id.startsWith('cr_receb') ||
        id.startsWith('mp_cr2_');
  }

  static bool _isReceivableMirror(
    LancamentoFinanceiro entry,
    Set<String> paymentKeys,
  ) {
    if (entry.origem != FinanceiroOrigemLancamento.contaReceberFiado &&
        !_looksLikeReceivableRef(entry)) {
      return false;
    }
    final ref = entry.referenciaExterna.trim();
    final id = entry.id.trim();
    if (paymentKeys.contains('ref:$ref') || paymentKeys.contains('ref:$id')) {
      return true;
    }
    for (final key in paymentKeys) {
      if (!key.startsWith('baixa:')) continue;
      final baixa = key.substring('baixa:'.length);
      if (baixa.isEmpty) continue;
      if (ref.endsWith('__$baixa') ||
          id.endsWith('__$baixa') ||
          ref.contains(baixa) ||
          id.contains(baixa)) {
        return true;
      }
    }
    return false;
  }
}
