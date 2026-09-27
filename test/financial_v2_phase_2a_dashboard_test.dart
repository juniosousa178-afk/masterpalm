import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/conta_receber_cache_authority.dart';
import 'package:master_palm/core/home_module_registry.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/financeiro/v2/financial_v2.dart';
import 'package:master_palm/financeiro/v2/financial_v2_dashboard_view.dart';
import 'package:master_palm/financeiro/v2/financial_v2_preview_screen.dart';
import 'package:master_palm/models/conta_pagar.dart';
import 'package:master_palm/models/conta_pagar_constants.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/models/venda.dart';

void main() {
  const nathy = 'nathy-pratas-e-folheados';
  const mir = 'mirjoias';
  final period = FinancialPeriod(
    start: DateTime(2026, 3, 1),
    end: DateTime(2026, 3, 31),
  );
  final today = DateTime(2026, 3, 20);

  FinancialDashboardRead dash({
    String storeId = nathy,
    List<Venda> sales = const [],
    List<ContaReceber> receivables = const [],
    List<LancamentoFinanceiro> entries = const [],
    List<ContaPagar> payables = const [],
    double? estimatedCardFee,
  }) {
    return FinancialMetricsCalculator.dashboardRead(
      FinancialDataSources.scoped(
        storeId: storeId,
        period: period,
        today: today,
        sales: sales,
        receivables: receivables,
        entries: entries,
        payables: payables,
        estimatedCardFee: estimatedCardFee,
      ),
    );
  }

  Venda venda({
    String store = nathy,
    required double total,
    double dinheiro = 0,
    double pix = 0,
    double cartao = 0,
    double custo = 0,
    String? id,
    String formas = 'Pix',
    String? origem,
  }) {
    return Venda(
      clienteNome: 'Cliente',
      produtosDescricao: 'item',
      quantidade: 1,
      preco: total,
      total: total,
      formasPagamento: formas,
      data: DateTime(2026, 3, 10),
      vendedor: 'app',
      observacao: '',
      pagamentoDinheiro: dinheiro,
      pagamentoPix: pix,
      pagamentoCartao: cartao,
      custoProdutos: custo,
      lojaId: store,
      idFirebase: id,
      origemVenda: origem,
    );
  }

  LancamentoFinanceiro lanc({
    required String id,
    required double valor,
    String tipo = FinanceiroTipoLancamento.gastoVariavel,
    String origem = FinanceiroOrigemLancamento.manual,
    String ref = '',
    String store = nathy,
    DateTime? when,
  }) {
    final data = when ?? DateTime(2026, 3, 12);
    return LancamentoFinanceiro(
      id: id,
      lojaId: store,
      descricao: 'lancamento',
      valor: valor,
      tipo: tipo,
      categoria: 'aluguel',
      status: FinanceiroStatusLancamento.pago,
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
    String status = ContaReceberStatus.pendente,
    String terminal = ContaReceberRemoteTerminalState.open,
    String historico = '[]',
    DateTime? vencimento,
    String store = nathy,
    bool pagoFlag = false,
  }) {
    final c = ContaReceber(
      lojaId: store,
      clienteNome: 'Cliente',
      valor: saldo,
      valorOriginal: saldo + pago,
      valorPago: pago,
      pago: pagoFlag,
      status: status,
      dataVencimento: vencimento ?? DateTime(2026, 3, 25),
      dataVenda: DateTime(2026, 3, 1),
      idFirebase: id,
      historicoPagamentosJson: historico,
    );
    stampContaReceberRemoteAuthority(c, terminalState: terminal);
    return c;
  }

  ContaPagar parcela({
    required String id,
    required double valor,
    String store = nathy,
    DateTime? vencimento,
    String status = ContaPagarStatus.pendente,
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
      dataVencimento: vencimento ?? DateTime(2026, 3, 25),
      dataCompra: DateTime(2026, 3, 2),
      status: status,
    );
  }

  test('DASHBOARD_USES_FINANCIAL_V2_READ_MODEL', () {
    final read = dash(
      sales: [venda(total: 80, dinheiro: 80, custo: 20, id: 'v1')],
    );
    final direct = FinancialMetricsCalculator.overview(
      FinancialDataSources.scoped(
        storeId: nathy,
        period: period,
        today: today,
        sales: [venda(total: 80, dinheiro: 80, custo: 20, id: 'v1')],
      ),
    );
    expect(read.overview.grossSales, direct.grossSales);
    expect(read.overview.cashInflows, direct.cashInflows);
    expect(read.overview.availableBalanceSupported, isFalse);
  });

  test('faturamento difere de recebimento e fiado só entra no caixa quando pago', () {
    final saleOnly = dash(
      sales: [venda(total: 150, id: 'fiado', formas: 'Fiado')],
    );
    expect(saleOnly.overview.grossSales, 150);
    expect(saleOnly.overview.cashInflows, 0);
    expect(saleOnly.days.single.grossSales, 150);
    expect(saleOnly.days.single.receipts, 0);

    final paid = dash(
      sales: [venda(total: 150, id: 'fiado-2', formas: 'Fiado')],
      receivables: [
        titulo(
          id: 'cr-1',
          saldo: 90,
          pago: 60,
          status: ContaReceberStatus.parcial,
          terminal: ContaReceberRemoteTerminalState.partial,
          historico:
              '[{"valor":60,"data":"2026-03-18T15:00:00","forma":"Pix","baixaId":"bx-60"}]',
        ),
      ],
      entries: [
        lanc(
          id: 'mp_cr2_cr-1__bx-60',
          valor: 60,
          tipo: FinanceiroTipoLancamento.entradaExtra,
          origem: FinanceiroOrigemLancamento.contaReceberFiado,
          ref: 'mp_cr2_cr-1__bx-60',
          when: DateTime(2026, 3, 18),
        ),
      ],
    );
    expect(paid.overview.grossSales, 150);
    expect(paid.overview.cashInflows, 60);
    expect(paid.overview.deduplicatedReceivablePaymentCount, 1);
  });

  test('consignação e compra não contam duas vezes', () {
    final consignment = dash(
      sales: [
        venda(total: 40, id: 'csgn_acerto-1', origem: 'consignment', formas: 'consignacao'),
      ],
      entries: [
        lanc(
          id: 'csgn_fin_acerto-1',
          valor: 40,
          tipo: FinanceiroTipoLancamento.entradaExtra,
          origem: 'consignment',
        ),
      ],
    );
    expect(consignment.overview.consignmentSettlementCount, 1);
    expect(consignment.overview.cashInflows, 40);
    expect(consignment.overview.grossSales + consignment.overview.cashInflows, isNot(120));

    final purchase = dash(
      sales: [venda(total: 100, dinheiro: 100, custo: 30, id: 'venda')],
      entries: [
        lanc(
          id: 'compra',
          valor: 30,
          tipo: FinanceiroTipoLancamento.compraMercadoria,
        ),
      ],
    );
    expect(purchase.overview.saleCogsSnapshot, 30);
    expect(purchase.overview.cashPurchaseOutflow, 30);
    expect(purchase.overview.grossProfitKnownAmount, 70);
    expect(purchase.overview.cashOutflows, 30);
  });

  test('custo ausente não vira zero e taxa estimada fica de fora', () {
    final missing = presentFinancialDashboard(
      read: dash(sales: [venda(total: 50, dinheiro: 50, id: 'sem-custo')]),
      salesAvailable: true,
      entriesAvailable: true,
      receivablesAvailable: true,
      payablesAvailable: true,
    );
    expect(missing.lucroBruto.valueText, 'Dados insuficientes');
    expect(missing.lucroBruto.valueText, isNot('R\$ 0,00'));
    expect(missing.faturamento.valueText, 'R\$ 50,00');

    final estimated = dash(
      sales: [venda(total: 100, cartao: 100, custo: 10, id: 'cartao')],
      estimatedCardFee: 5,
    );
    expect(estimated.overview.cashInflows, 100);
    expect(estimated.overview.actualCardFee, isNull);
    final cards = presentFinancialDashboard(
      read: estimated,
      salesAvailable: true,
      entriesAvailable: true,
      receivablesAvailable: true,
      payablesAvailable: true,
    );
    expect(cards.estimatedFeeIncludedInTotals, isFalse);
    expect(cards.qualityNotes.any((n) => n.contains('estimativa')), isTrue);
    expect(cards.showsAvailableBalance, isFalse);
    expect(cards.showsDre, isFalse);
    expect(cards.showsNetProfit, isFalse);
  });

  test('zero conhecido difere de fonte indisponível', () {
    final empty = presentFinancialDashboard(
      read: dash(),
      salesAvailable: true,
      entriesAvailable: true,
      receivablesAvailable: true,
      payablesAvailable: true,
    );
    expect(empty.faturamento.valueText, 'R\$ 0,00');
    expect(empty.saidas.valueText, 'R\$ 0,00');

    final down = presentFinancialDashboard(
      read: dash(payables: [parcela(id: 'p1', valor: 15)]),
      salesAvailable: false,
      entriesAvailable: false,
      receivablesAvailable: false,
      payablesAvailable: true,
    );
    expect(down.faturamento.valueText, isNull);
    expect(down.recebimentos.valueText, isNull);
    expect(down.aPagar.valueText, 'R\$ 15,00');
    expect(down.aPagar.footnote, 'Neste dispositivo');
    expect(down.cashChart, isNull);
  });

  test('a pagar permanece local e o período padrão é o mês atual', () {
    final read = dash(
      payables: [
        parcela(id: 'p1', valor: 10, vencimento: DateTime(2026, 3, 10)),
        parcela(id: 'p2', valor: 7, vencimento: DateTime(2026, 3, 22)),
        parcela(
          id: 'p3',
          valor: 99,
          status: ContaPagarStatus.pago,
          vencimento: DateTime(2026, 3, 1),
        ),
      ],
    );
    expect(read.overview.payablesAuthority, FinancialAuthority.localOnly);
    expect(read.payables.open, 17);
    expect(read.payables.overdue, 10);
    expect(read.payables.upcoming, 7);
    expect(read.payables.dueWithin7Days, 7);

    final month = financialDashboardPeriod(
      kind: FinancialDashboardPeriodKind.currentMonth,
      today: DateTime(2026, 3, 20),
    );
    expect(month.periodStart, DateTime(2026, 3, 1));
    expect(month.periodEnd, DateTime(2026, 3, 31));
  });

  test('isolamento de loja e painel sem saldo disponível', () {
    final nathyRead = dash(
      sales: [
        venda(total: 10, dinheiro: 10, id: 'n'),
        venda(store: mir, total: 999, dinheiro: 999, id: 'm'),
      ],
      payables: [
        parcela(id: 'nathy', valor: 4),
        parcela(id: 'mir', valor: 80, store: mir),
      ],
    );
    final mirRead = dash(
      storeId: mir,
      sales: [
        venda(total: 10, dinheiro: 10, id: 'n'),
        venda(store: mir, total: 999, dinheiro: 999, id: 'm'),
      ],
    );
    expect(nathyRead.overview.grossSales, 10);
    expect(nathyRead.overview.openPayables, 4);
    expect(mirRead.overview.grossSales, 999);
    expect(mirRead.overview.openPayables, 0);
    final cards = presentFinancialDashboard(
      read: nathyRead,
      salesAvailable: true,
      entriesAvailable: true,
      receivablesAvailable: true,
      payablesAvailable: true,
    );
    expect(
      [
        cards.faturamento,
        cards.recebimentos,
        cards.saidas,
        cards.resultadoCaixa,
        cards.aReceber,
        cards.vencido,
        cards.aPagar,
        cards.lucroBruto,
      ].map((c) => c.title),
      isNot(contains('Saldo disponível')),
    );
    expect(cards.qualityNotes.any((n) => n.contains('PAYABLES_LOCAL_ONLY')), isFalse);
  });

  test('abrir e atualizar o painel não grava', () async {
    final reads = _FakeReads(
      saleRows: [venda(total: 20, pix: 20, custo: 5, id: 'ok')],
      payableRows: [parcela(id: 'p', valor: 3)],
    );
    const loader = FinancialOverviewLoader();
    final first = await loader.load(
      storeId: nathy,
      period: period,
      today: today,
      reads: reads,
    );
    final second = await loader.load(
      storeId: nathy,
      period: period,
      today: today,
      reads: reads,
    );
    expect(first.remoteWrites, 0);
    expect(second.remoteWrites, 0);
    expect(reads.salesCalls, 2);
    expect(reads.entryCalls, 2);
    expect(reads.writeCalls, 0);
    expect(first.remoteQueryCount, 3);
    expect(first.localReadCount, 1);
    expect(first.read.overview.grossSales, 20);
  });

  test('flag falsa não troca a tela atual nem o menu', () {
    expect(FinancialV2Flags.financialV2Enabled, isFalse);
    expect(FinancialV2Flags.payablesRemoteMirrorEnabled, isFalse);
    expect(FinancialV2Flags.payablesRemoteMirrorPilotStoreId, nathy);
    expect(FinancialV2DashboardGate.replacesCurrentFinanceiro, isFalse);
    expect(FinancialV2DashboardGate.showInHomeMenu, isFalse);
    expect(
      HomeModuleRegistry.all.any(
        (m) => m.route == FinancialV2DashboardGate.previewRoute,
      ),
      isFalse,
    );
    expect(
      HomeModuleRegistry.all.any((m) => m.route == '/financeiro'),
      isTrue,
    );
  });

  testWidgets('prévia mostra cartões e não oferece lançamento', (tester) async {
    final reads = _FakeReads(
      saleRows: [venda(total: 37.9, pix: 37.9, custo: 10, id: 'anel')],
      payableRows: [parcela(id: 'p', valor: 8)],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: FinancialV2PreviewScreen(
          debugIsAdmin: true,
          debugStoreId: nathy,
          debugReads: reads,
          debugToday: today,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Faturamento'), findsOneWidget);
    expect(find.text('Recebimentos'), findsOneWidget);
    expect(find.text('Resultado de caixa'), findsOneWidget);
    expect(find.text('Neste dispositivo'), findsWidgets);
    expect(find.text('Saldo disponível'), findsNothing);
    expect(find.text('Lucro líquido'), findsNothing);
    expect(find.text('DRE'), findsNothing);
    expect(find.text('Nova despesa'), findsNothing);
    expect(find.text('Pagar'), findsNothing);
    expect(find.text('Baixar'), findsNothing);
    expect(reads.writeCalls, 0);

    await tester.tap(find.byTooltip('Atualizar'));
    await tester.pumpAndSettle();
    expect(reads.writeCalls, 0);
    expect(reads.salesCalls, 2);
  });

  testWidgets('sem permissão a prévia não lê dados', (tester) async {
    final reads = _FakeReads();
    await tester.pumpWidget(
      const MaterialApp(
        home: FinancialV2PreviewScreen(debugIsAdmin: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Prévia interna indisponível.'), findsOneWidget);
    expect(reads.salesCalls, 0);
  });
}

class _FakeReads implements FinancialPeriodReads {
  _FakeReads({
    this.saleRows = const [],
    this.entryRows = const [],
    this.receivableRows = const [],
    this.payableRows = const [],
  });

  final List<Venda> saleRows;
  final List<LancamentoFinanceiro> entryRows;
  final List<ContaReceber> receivableRows;
  final List<ContaPagar> payableRows;
  int salesCalls = 0;
  int entryCalls = 0;
  int writeCalls = 0;

  @override
  int get remoteQueryCount => 3;

  @override
  int get localReadCount => 1;

  @override
  Future<List<Venda>> sales({
    required String storeId,
    required FinancialPeriod period,
  }) async {
    salesCalls++;
    return saleRows;
  }

  @override
  Future<List<LancamentoFinanceiro>> entries({
    required String storeId,
    required FinancialPeriod period,
  }) async {
    entryCalls++;
    return entryRows;
  }

  @override
  Future<List<ContaReceber>> openReceivables({required String storeId}) async {
    return receivableRows;
  }

  @override
  Future<List<ContaPagar>> payables({required String storeId}) async {
    return payableRows;
  }
}
