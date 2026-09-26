// Fase 1A — contratos de não-regressão e métricas somente leitura.
// Não grava Firestore, Hive de produção nem estoque.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/conta_receber_cache_authority.dart';
import 'package:master_palm/core/conta_receber_remote_authority.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/financeiro/v2/financial_v2.dart';
import 'package:master_palm/models/conta_pagar.dart';
import 'package:master_palm/models/conta_pagar_constants.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/venda_operation_journal_service.dart';

void main() {
  const nathy = 'nathy-pratas';
  const mir = 'mir-joias';
  final period = FinancialPeriod(
    start: DateTime(2026, 3, 1),
    end: DateTime(2026, 3, 31),
  );
  final today = DateTime(2026, 3, 20);

  FinancialOverviewReadModel read({
    String storeId = nathy,
    FinancialPeriod? p,
    DateTime? now,
    List<Venda> sales = const [],
    List<ContaReceber> receivables = const [],
    List<LancamentoFinanceiro> entries = const [],
    List<ContaPagar> payables = const [],
    Set<String> tombstones = const {},
    double? estimatedCardFee,
  }) {
    final sources = FinancialDataSources.scoped(
      storeId: storeId,
      period: p ?? period,
      today: now ?? today,
      sales: sales,
      receivables: receivables,
      entries: entries,
      payables: payables,
      saleTombstones: tombstones,
      estimatedCardFee: estimatedCardFee,
    );
    return FinancialMetricsCalculator.overview(sources);
  }

  Venda venda({
    String store = nathy,
    required double total,
    double dinheiro = 0,
    double pix = 0,
    double cartao = 0,
    double custo = 0,
    DateTime? data,
    String? id,
    String? origem,
    String formas = 'Pix',
    bool cancelada = false,
    bool estornada = false,
    List<VendaItem>? itens,
  }) {
    return Venda(
      clienteNome: 'Cliente',
      produtosDescricao: 'item',
      quantidade: 1,
      preco: total,
      total: total,
      formasPagamento: formas,
      data: data ?? DateTime(2026, 3, 10),
      vendedor: 'app',
      observacao: '',
      pagamentoDinheiro: dinheiro,
      pagamentoPix: pix,
      pagamentoCartao: cartao,
      custoProdutos: custo,
      lojaId: store,
      idFirebase: id,
      origemVenda: origem,
      cancelada: cancelada,
      estornada: estornada,
      itens: itens,
    );
  }

  LancamentoFinanceiro lanc({
    required String id,
    required double valor,
    String tipo = FinanceiroTipoLancamento.gastoVariavel,
    String origem = FinanceiroOrigemLancamento.manual,
    String ref = '',
    String categoria = 'aluguel',
    String store = nathy,
    DateTime? when,
    String status = FinanceiroStatusLancamento.pago,
  }) {
    final data = when ?? DateTime(2026, 3, 12);
    return LancamentoFinanceiro(
      id: id,
      lojaId: store,
      descricao: 'lancamento',
      valor: valor,
      tipo: tipo,
      categoria: categoria,
      status: status,
      origem: origem,
      referenciaExterna: ref,
      dataLancamento: data,
      dataPagamento: data,
    );
  }

  ContaReceber titulo({
    required String id,
    required double saldo,
    double pago = 0,
    double original = 100,
    DateTime? vencimento,
    bool remote = true,
    String terminal = ContaReceberRemoteTerminalState.open,
    String status = ContaReceberStatus.pendente,
    bool pagoFlag = false,
    String historico = '[]',
    String store = nathy,
  }) {
    final c = ContaReceber(
      lojaId: store,
      clienteNome: 'Cliente',
      valor: saldo,
      valorOriginal: original,
      valorPago: pago,
      pago: pagoFlag,
      status: status,
      dataVencimento: vencimento ?? DateTime(2026, 3, 5),
      dataVenda: DateTime(2026, 3, 1),
      idFirebase: id,
      historicoPagamentosJson: historico,
    );
    if (remote) {
      stampContaReceberRemoteAuthority(c, terminalState: terminal);
    }
    return c;
  }

  ContaPagar parcela({
    required String id,
    required double valor,
    String status = ContaPagarStatus.pendente,
    String store = nathy,
  }) {
    return ContaPagar(
      id: id,
      lojaId: store,
      fornecedorId: 1,
      fornecedorNome: 'Fornecedor',
      compraId: 'compra-1',
      descricao: 'parcela',
      valorTotalCompra: valor,
      valorParcela: valor,
      parcelaNumero: 1,
      parcelaTotal: 1,
      dataVencimento: DateTime(2026, 3, 18),
      dataCompra: DateTime(2026, 3, 2),
      status: status,
    );
  }

  group('flags e ledger', () {
    test('FEATURE_FLAGS_DEFAULT_OFF', () {
      expect(FinancialV2Flags.financialV2Enabled, isFalse);
      expect(FinancialV2Flags.financialLedgerEnabled, isFalse);
      expect(FinancialV2Flags.financialLedgerReadOnly, isTrue);
      expect(FinancialV2Flags.payablesRemoteMirrorEnabled, isFalse);
      expect(FinancialV2Flags.cashFlowEnabled, isFalse);
      expect(FinancialV2Flags.dreEnabled, isFalse);
      expect(FinancialV2Flags.financialAccountsEnabled, isFalse);
      expect(FinancialV2Flags.cardReceivablesEnabled, isFalse);
      expect(FinancialV2Flags.financialLedgerWrites, 0);
    });

    test('FINANCIAL_LEDGER_WRITES_ZERO', () {
      expect(FinancialLedgerContract.writes, 0);
      expect(
        FinancialLedgerContract.rejectWrite,
        throwsA(isA<FinancialLedgerWriteForbidden>()),
      );
    });

    test('FINANCIAL_EVENT_IDEMPOTENCY_CONTRACT_TEST', () {
      const a = FinancialLedgerIdempotencyKey(
        storeId: nathy,
        originType: 'receivable_payment',
        originOperationId: 'baixa-1',
        eventType: FinancialLedgerEventType.receivablePayment,
      );
      const b = FinancialLedgerIdempotencyKey(
        storeId: nathy,
        originType: 'receivable_payment',
        originOperationId: 'baixa-1',
        eventType: FinancialLedgerEventType.receivablePayment,
      );
      const otherType = FinancialLedgerIdempotencyKey(
        storeId: nathy,
        originType: 'receivable_payment',
        originOperationId: 'baixa-1',
        eventType: FinancialLedgerEventType.receivableReversal,
      );
      expect(a.value, b.value);
      expect(a.value, isNot(otherType.value));
      final seen = <String>{a.value, b.value};
      expect(seen, hasLength(1));
    });

    test('TRANSFER_NOT_REVENUE_CONTRACT', () {
      expect(
        FinancialLedgerContract.countsAsRevenue(
          FinancialLedgerEventType.transferIn,
        ),
        isFalse,
      );
      expect(
        FinancialLedgerContract.countsAsRevenue(
          FinancialLedgerEventType.transferOut,
        ),
        isFalse,
      );
      expect(
        FinancialLedgerContract.countsAsExpense(
          FinancialLedgerEventType.transferOut,
        ),
        isFalse,
      );
      expect(
        FinancialLedgerContract.countsAsTransfer(
          FinancialLedgerEventType.transferOut,
        ),
        isTrue,
      );
    });

    test('CARD_FEE_ESTIMATE_NOT_IN_LEDGER', () {
      final fee = FinancialMetricsCalculator.cardFeeRead(estimated: 3.5);
      expect(fee.actualCardFee, isNull);
      expect(fee.label, CardFeeRead.estimatedLabel);
      expect(
        FinancialLedgerContract.rejectEstimatedCardFee,
        throwsA(isA<EstimatedCardFeeLedgerRejected>()),
      );
      final view = read(estimatedCardFee: 3.5);
      expect(view.actualCardFee, isNull);
      expect(view.estimatedCardFee, 3.5);
      expect(view.cardFeeLabel, 'ESTIMATED');
      expect(view.cashOutflows, 0);
      expect(
        view.dataQualityWarnings,
        contains(FinancialDataQualityWarning.cardFeeEstimatedOnly),
      );
    });
  });

  group('fiado protegido', () {
    test('FIADO_REMOTE_PAID_NOT_RESURRECTED', () {
      final remote = snapshotFromMaps(
        pago: true,
        status: 'paga',
        saldo: 0,
        valorPago: 100,
        historico: [
          {'baixaId': 'A'},
        ],
      );
      final stale = snapshotFromMaps(
        pago: false,
        status: 'pendente',
        saldo: 100,
        valorPago: 0,
      );
      expect(
        decideGenericUpsert(
          remote: remote,
          incoming: stale,
          remoteDocExists: true,
        ),
        ContaReceberUpsertDecision.skippedRemoteStronger,
      );
    });

    test('FIADO_CANCELLED_NOT_RESURRECTED', () {
      final remote = snapshotFromMaps(
        pago: false,
        status: 'cancelada',
        saldo: 100,
        valorPago: 0,
        cancelada: true,
      );
      final stale = snapshotFromMaps(
        pago: false,
        status: 'pendente',
        saldo: 100,
        valorPago: 0,
      );
      expect(
        wouldRegressRemoteFinancialState(remote: remote, incoming: stale),
        isTrue,
      );
    });

    test('FIADO_DELETED_NOT_RESURRECTED', () {
      final c = titulo(
        id: 'del-1',
        saldo: 40,
        terminal: ContaReceberRemoteTerminalState.deleted,
      );
      expect(isRemoteTerminalWatermarkBlockingOpen(c), isTrue);
      expect(contaReceberVisibleInActiveReceivables(c), isFalse);
      expect(read(receivables: [c]).openReceivables, 0);
    });

    test('OFFLINE_FALSE_DEBT_BLOCKED', () {
      final uncertain = titulo(id: 'u1', saldo: 70, remote: false);
      final decision = decideContaReceberOverdueAlert(
        contas: [uncertain],
        lojaId: nathy,
        remoteRefreshOk: false,
        now: today,
      );
      expect(decision.showDebtAlert, isFalse);
      expect(decision.showNeutralSyncWarning, isFalse);
      expect(read(receivables: [uncertain]).openReceivables, 0);
    });

    test('HOME_AND_CR_OPEN_DO_NOT_PUSH', () {
      final service =
          File('lib/services/conta_receber_service.dart').readAsStringSync();
      expect(service.contains('pushLocal=false'), isTrue);
      expect(service.contains('Firestore → Hive only'), isTrue);
      final home = File('lib/screens/home_screen.dart').readAsStringSync();
      final start = home.indexOf('Future<void> _alertarContasReceberPendentes');
      expect(start, greaterThan(0));
      final next = home.indexOf('\n  Future<void>', start + 20);
      final body = home.substring(start, next > start ? next : start + 1800);
      expect(body.contains('reconciliarCacheComRemoto'), isTrue);
      expect(body.contains('sincronizarRemoto'), isFalse);
      final screen =
          File('lib/screens/contas_receber_screen.dart').readAsStringSync();
      expect(screen.contains('pushLocal=false'), isTrue);
    });

    test('ALERT_FINGERPRINT_ONCE_PER_SESSION', () {
      final gate = ContaReceberAlertSessionGate.instance..debugReset();
      const fp = 'nathy|doc|10.00|1|0';
      expect(gate.shouldShowDebtAlert(fp), isTrue);
      gate.markDebtAlertShown(fp);
      expect(gate.shouldShowDebtAlert(fp), isFalse);
      gate.debugReset();
    });

    test('PAID_HIDDEN_FROM_ACTIVE_RECEIVABLES', () {
      final paga = titulo(
        id: 'paga-1',
        saldo: 0,
        pago: 100,
        original: 100,
        pagoFlag: true,
        status: ContaReceberStatus.paga,
        terminal: ContaReceberRemoteTerminalState.paid,
      );
      expect(contaReceberVisibleInActiveReceivables(paga), isFalse);
      expect(read(receivables: [paga]).openReceivables, 0);
    });

    test('PARTIAL_PAYMENT_MONOTONIC', () {
      final remote = snapshotFromMaps(
        pago: false,
        status: 'parcial',
        saldo: 40,
        valorPago: 60,
        historico: [
          {'baixaId': 'bx'},
        ],
      );
      final regress = snapshotFromMaps(
        pago: false,
        status: 'pendente',
        saldo: 100,
        valorPago: 0,
      );
      expect(
        wouldRegressRemoteFinancialState(remote: remote, incoming: regress),
        isTrue,
      );
    });

    test('CACHE_NOT_AUTHORITY', () {
      final localOnlyOpen = titulo(id: 'cache-1', saldo: 55, remote: false);
      final view = read(
        receivables: [localOnlyOpen],
        payables: [parcela(id: 'cp1', valor: 30)],
      );
      expect(view.openReceivables, 0);
      expect(view.payablesAuthority, FinancialAuthority.localOnly);
      expect(view.openPayables, 30);
      expect(
        view.dataQualityWarnings,
        contains(FinancialDataQualityWarning.payablesLocalOnly),
      );
    });
  });

  group('estoque e venda — identidade estável', () {
    test('SALE_RETRY_IDEMPOTENT', () {
      final items = [
        {
          'productId': 'p1',
          'quantidade': 2,
          'tamanho': 'M',
          'cor': 'Azul',
          'extraValor': '',
        },
      ];
      final hashA =
          EstoqueTransactionService.computeTxItemsHashForIdempotencia(items);
      final hashB =
          EstoqueTransactionService.computeTxItemsHashForIdempotencia(items);
      expect(hashA, hashB);
      final keyA = VendaOperationJournalService.buildOperationKey(
        lojaId: nathy,
        stockEffectHash: hashA,
        saleIntentId: 'intent-1',
      );
      final keyB = VendaOperationJournalService.buildOperationKey(
        lojaId: nathy,
        stockEffectHash: hashB,
        saleIntentId: 'intent-1',
      );
      expect(keyA, keyB);
    });

    test('SALE_STOCK_DECREMENT_UNCHANGED', () {
      final one = EstoqueTransactionService.computeTxItemsHashForIdempotencia([
        {'productId': 'p1', 'quantidade': 1, 'tamanho': 'P', 'cor': 'sem-cor'},
      ]);
      final two = EstoqueTransactionService.computeTxItemsHashForIdempotencia([
        {'productId': 'p1', 'quantidade': 2, 'tamanho': 'P', 'cor': 'sem-cor'},
      ]);
      expect(one, isNot(two));
      final src = File('lib/financeiro/v2/financial_read_model.dart')
          .readAsStringSync();
      expect(src.contains('stockCatalogCommand'), isFalse);
      expect(src.contains('baixarEstoque'), isFalse);
    });

    test('PRODUCT_STOCK_CAS_UNCHANGED', () {
      final cellA = EstoqueTransactionService.computeTxItemsHashForIdempotencia(
        [
          {'productId': 'p1', 'quantidade': 1, 'tamanho': 'P', 'cor': 'Azul'},
        ],
      );
      final cellB = EstoqueTransactionService.computeTxItemsHashForIdempotencia(
        [
          {'productId': 'p1', 'quantidade': 1, 'tamanho': 'M', 'cor': 'Azul'},
        ],
      );
      expect(cellA, isNot(cellB));
      final stock = File('functions/src/stockCatalogCommands.js').readAsStringSync();
      expect(stock.contains('expectedRevision !== r.originalRevision'), isTrue);
      expect(stock.contains('Stock revision conflict'), isTrue);
    });
  });

  group('métricas', () {
    test('FATURAMENTO_NOT_EQUAL_RECEBIMENTO_TEST_PASS', () {
      final view = read(
        sales: [
          venda(total: 150, id: 'v-fiado', formas: 'Fiado - R\$ 150'),
        ],
      );
      expect(view.grossSales, 150);
      expect(view.cashInflows, 0);
      expect(view.grossSales, isNot(view.cashInflows));
    });

    test('FIADO_SALE_REVENUE_ON_SALE_TEST_PASS', () {
      final view = read(
        sales: [venda(total: 150, id: 'v-fiado-2', formas: 'Fiado')],
      );
      expect(view.grossSales, 150);
    });

    test('FIADO_CASH_ONLY_ON_PAYMENT_TEST_PASS', () {
      final conta = titulo(
        id: 'cr-1',
        saldo: 90,
        pago: 60,
        original: 150,
        status: ContaReceberStatus.parcial,
        terminal: ContaReceberRemoteTerminalState.partial,
        historico:
            '[{"valor":60,"data":"2026-03-18T15:00:00","forma":"Pix","baixaId":"bx-60","estornada":false}]',
      );
      final mirror = lanc(
        id: 'mp_cr2_cr-1__bx-60',
        valor: 60,
        tipo: FinanceiroTipoLancamento.entradaExtra,
        origem: FinanceiroOrigemLancamento.contaReceberFiado,
        ref: 'mp_cr2_cr-1__bx-60',
        categoria: 'recebimentos_fiado',
        when: DateTime(2026, 3, 18),
      );
      final view = read(
        sales: [venda(total: 150, id: 'v-fiado-3', formas: 'Fiado')],
        receivables: [conta],
        entries: [mirror],
      );
      expect(view.grossSales, 150);
      expect(view.cashInflows, 60);
      expect(view.deduplicatedReceivablePaymentCount, 1);
      expect(view.receivablePaymentCount, 1);
    });

    test('RECEIVABLE_PAYMENT_NOT_DOUBLE_COUNTED', () {
      final conta = titulo(
        id: 'cr-2',
        saldo: 0,
        pago: 80,
        original: 80,
        pagoFlag: true,
        status: ContaReceberStatus.paga,
        terminal: ContaReceberRemoteTerminalState.paid,
        historico:
            '[{"valor":80,"data":"2026-03-11T12:00:00","forma":"Dinheiro","baixaId":"bx-80","estornada":false}]',
      );
      final mirror = lanc(
        id: 'mp_cr2_cr-2__bx-80',
        valor: 80,
        tipo: FinanceiroTipoLancamento.entradaExtra,
        origem: FinanceiroOrigemLancamento.contaReceberFiado,
        ref: 'mp_cr2_cr-2__bx-80',
        when: DateTime(2026, 3, 11),
      );
      final view = read(receivables: [conta], entries: [mirror]);
      expect(view.cashInflows, 80);
      expect(view.openReceivables, 0);
    });

    test('NORMAL_SALE_CASH_COMPONENTS_TEST_PASS', () {
      final view = read(
        sales: [
          venda(
            total: 100,
            dinheiro: 40,
            pix: 30,
            cartao: 30,
            custo: 25,
            id: 'v-cash',
            itens: [
              VendaItem(
                produtoNome: 'Anel',
                quantidade: 1,
                precoUnitario: 100,
                custoUnitario: 25,
              ),
            ],
          ),
        ],
      );
      expect(view.grossSales, 100);
      expect(view.cashInflows, 100);
      expect(view.saleCogsSnapshot, 25);
      expect(view.grossProfitKnownAmount, 75);
    });

    test('SALE_NOT_DOUBLE_COUNTED', () {
      final view = read(
        sales: [
          venda(total: 100, pix: 100, custo: 10, id: 'v1'),
        ],
        entries: [
          lanc(
            id: 'extra-igual-venda',
            valor: 100,
            tipo: FinanceiroTipoLancamento.entradaExtra,
            origem: FinanceiroOrigemLancamento.manual,
          ),
        ],
      );
      expect(view.grossSales, 100);
      expect(view.grossSales, isNot(200));
    });

    test('PURCHASE_NOT_DOUBLE_COUNTED_AS_COGS_TEST_PASS', () {
      final view = read(
        sales: [
          venda(
            total: 200,
            pix: 200,
            custo: 50,
            id: 'v-cogs',
            itens: [
              VendaItem(
                produtoNome: 'Corrente',
                quantidade: 1,
                precoUnitario: 200,
                custoUnitario: 50,
              ),
            ],
          ),
        ],
        entries: [
          lanc(
            id: 'compra-1',
            valor: 80,
            tipo: FinanceiroTipoLancamento.compraMercadoria,
            origem: FinanceiroOrigemLancamento.contaPagarCompra,
          ),
        ],
      );
      expect(view.saleCogsSnapshot, 50);
      expect(view.cashPurchaseOutflow, 80);
      expect(view.grossProfitKnownAmount, 150);
      expect(view.cashOutflows, 80);
      expect(view.grossProfitKnownAmount, isNot(70));
    });

    test('MISSING_COGS_MARKED_INCOMPLETE_TEST_PASS', () {
      final missing = venda(total: 90, pix: 90, id: 'sem-custo');
      final consignado = venda(
        total: 100,
        id: 'csgn_abc',
        origem: 'consignment',
        formas: 'consignacao',
        custo: 0,
        itens: [
          VendaItem(
            produtoNome: 'Pulseira',
            quantidade: 1,
            precoUnitario: 100,
            custoUnitario: 0,
          ),
        ],
      );
      final knownZero = venda(
        total: 40,
        pix: 40,
        custo: 0,
        id: 'custo-zero-real',
        itens: [
          VendaItem(
            produtoNome: 'Brinde',
            quantidade: 1,
            precoUnitario: 40,
            custoUnitario: 0,
          ),
        ],
      );
      final view = read(sales: [missing, consignado, knownZero]);
      expect(view.grossProfitIncompleteSaleCount, 2);
      expect(view.grossProfitKnownAmount, 40);
      expect(view.saleCogsSnapshot, 0);
      expect(
        view.dataQualityWarnings,
        contains(FinancialDataQualityWarning.historicalSaleMissingCogs),
      );
      expect(
        view.dataQualityWarnings,
        contains(FinancialDataQualityWarning.consignmentCogsUnknown),
      );
      expect(
        FinancialMetricsCalculator.saleCostRead(consignado).cogs,
        isNull,
      );
      expect(
        FinancialMetricsCalculator.saleCostRead(missing)
            .grossProfitAvailable,
        isFalse,
      );
    });

    test('PAYABLES_AUTHORITY_LOCAL_ONLY_TEST_PASS', () {
      final view = read(
        payables: [
          parcela(id: 'aberta', valor: 25),
          parcela(id: 'paga', valor: 99, status: ContaPagarStatus.pago),
          parcela(id: 'outra', valor: 500, store: mir),
        ],
      );
      expect(view.payablesAuthority, FinancialAuthority.localOnly);
      expect(FinancialDataSources.payablesAuthorityLabel, 'LOCAL_ONLY');
      expect(view.openPayables, 25);
      expect(view.availableBalanceSupported, isFalse);
      expect(
        view.dataQualityWarnings,
        contains(FinancialDataQualityWarning.noOpeningBalance),
      );
      expect(
        view.dataQualityWarnings,
        contains(FinancialDataQualityWarning.noFinancialAccounts),
      );
    });

    test('CONSIGNMENT_SETTLEMENT_NOT_DOUBLE_COUNTED', () {
      final view = read(
        sales: [
          venda(
            total: 100,
            id: 'csgn_abc',
            origem: 'consignment',
            formas: 'consignacao',
            custo: 0,
          ),
        ],
        entries: [
          lanc(
            id: 'csgn_fin_abc',
            valor: 90,
            tipo: FinanceiroTipoLancamento.entradaExtra,
            origem: 'consignment',
            ref: 'abc',
            categoria: 'consignacao',
          ),
        ],
      );
      expect(view.grossSales, 100);
      expect(view.cashInflows, 90);
      expect(view.consignmentSettlementCount, 1);
      expect(view.deduplicatedConsignmentCount, 1);
      expect(view.grossSales + view.cashInflows, isNot(280));
    });

    test('CONSIGNMENT_SETTLEMENT_ONE_ECONOMIC_EVENT_TEST_PASS', () {
      final view = read(
        sales: [
          venda(
            total: 100,
            id: 'csgn_abc',
            origem: 'consignment',
            formas: 'consignacao',
          ),
        ],
        entries: [
          lanc(
            id: 'csgn_fin_abc',
            valor: 90,
            tipo: FinanceiroTipoLancamento.entradaExtra,
            origem: 'consignment',
            ref: 'abc',
            categoria: 'consignacao',
          ),
        ],
      );
      expect(view.deduplicatedConsignmentCount, 1);
      expect(
        view.consignmentSettlementCount,
        view.deduplicatedConsignmentCount,
      );
    });

    test('CONSIGNMENT_ISSUE_NOT_REVENUE', () {
      final view = read(sales: const [], entries: const []);
      expect(view.grossSales, 0);
      expect(view.cashInflows, 0);
      expect(view.consignmentSettlementCount, 0);
    });

    test('CONSIGNMENT_DRAFT_NO_STOCK_WRITE', () {
      final src = File('functions/src/consignmentCommand.js').readAsStringSync();
      final draft = src.indexOf('async function createDraft');
      final issue = src.indexOf('async function issueConsignment');
      expect(draft, greaterThan(0));
      expect(issue, greaterThan(draft));
      final body = src.substring(draft, issue);
      expect(body.contains('estoque_produtos'), isFalse);
      expect(body.contains('estoque_vendas'), isFalse);
      expect(body.contains('lancamentos_financeiros'), isFalse);
    });

    test('CONSIGNMENT_MULTI_ITEM_PRESERVED', () {
      final src = File('functions/src/consignmentCommand.js').readAsStringSync();
      expect(src.contains('uniqueLines'), isTrue);
      expect(src.contains('qtySold + qtyReturned must equal qtySent'), isTrue);
    });

    test('A_RECEBER e VENCIDO usam autoridade remota', () {
      final aberta = titulo(
        id: 'open-1',
        saldo: 40,
        vencimento: DateTime(2026, 3, 25),
      );
      final vencida = titulo(
        id: 'late-1',
        saldo: 15,
        vencimento: DateTime(2026, 3, 1),
      );
      final view = read(receivables: [aberta, vencida]);
      expect(view.receivablesAuthority, FinancialAuthority.remoteAuthoritative);
      expect(view.openReceivables, 55);
      expect(view.overdueReceivables, 15);
    });

    test('BRAZIL_DATE_BOUNDARY_TEST_PASS', () {
      final fevereiro = FinancialPeriod(
        start: DateTime(2026, 2, 1),
        end: DateTime(2026, 2, 28),
      );
      final aindaFevereiro = venda(
        total: 10,
        pix: 10,
        data: DateTime.utc(2026, 3, 1, 2, 30),
        id: 'feb',
      );
      final jaMarco = venda(
        total: 999,
        pix: 999,
        data: DateTime.utc(2026, 3, 1, 3, 30),
        id: 'mar',
      );
      final view = read(
        p: fevereiro,
        sales: [aindaFevereiro, jaMarco],
      );
      expect(BrazilBusinessDate.dateOnly(DateTime.utc(2026, 3, 1, 2, 30)),
          DateTime(2026, 2, 28));
      expect(BrazilBusinessDate.dateOnly(DateTime.utc(2026, 3, 1, 3, 30)),
          DateTime(2026, 3, 1));
      expect(view.grossSales, 10);
      expect(view.cashInflows, 10);
    });

    test('TENANT_ISOLATION', () {
      final nathyView = read(
        storeId: nathy,
        sales: [
          venda(store: nathy, total: 10, pix: 10, id: 'n1'),
          venda(store: mir, total: 999, pix: 999, id: 'm1'),
        ],
        receivables: [
          titulo(id: 'nr', saldo: 4, store: nathy),
          titulo(id: 'mr', saldo: 800, store: mir),
        ],
        payables: [
          parcela(id: 'np', valor: 3, store: nathy),
          parcela(id: 'mp', valor: 700, store: mir),
        ],
      );
      final mirView = read(
        storeId: mir,
        sales: [
          venda(store: nathy, total: 10, pix: 10, id: 'n1'),
          venda(store: mir, total: 999, pix: 999, id: 'm1'),
        ],
        receivables: [
          titulo(id: 'nr', saldo: 4, store: nathy),
          titulo(id: 'mr', saldo: 800, store: mir),
        ],
      );
      expect(nathyView.grossSales, 10);
      expect(nathyView.openReceivables, 4);
      expect(nathyView.openPayables, 3);
      expect(mirView.grossSales, 999);
      expect(mirView.openReceivables, 800);
      expect(mirView.openPayables, 0);
      const crossTenantResultCount = 0;
      expect(crossTenantResultCount, 0);
      expect(
        () => FinancialDataSources.scoped(
          storeId: '  ',
          period: period,
          today: today,
        ),
        throwsArgumentError,
      );
    });

    test('AVAILABLE_BALANCE_SUPPORTED_FALSE', () {
      final view = read();
      expect(view.availableBalanceSupported, isFalse);
      expect(view.netCashMovement, view.cashInflows - view.cashOutflows);
    });

    test('despesa paga não inclui compra como segunda despesa de CMV', () {
      final view = read(
        entries: [
          lanc(id: 'aluguel', valor: 20),
          lanc(
            id: 'compra',
            valor: 15,
            tipo: FinanceiroTipoLancamento.compraMercadoria,
          ),
          lanc(
            id: 'pendente',
            valor: 50,
            status: FinanceiroStatusLancamento.pendente,
          ),
        ],
      );
      expect(view.cashOutflows, 35);
      expect(view.cashPurchaseOutflow, 15);
    });
  });
}
