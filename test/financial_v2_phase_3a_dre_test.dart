// Fase 3A — DRE somente leitura. Não grava Firestore, Hive nem ledger.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/financeiro/v2/financial_dre.dart';
import 'package:master_palm/financeiro/v2/financial_dre_pdf.dart';
import 'package:master_palm/financeiro/v2/financial_launch_catalog.dart';
import 'package:master_palm/financeiro/v2/financial_month.dart';
import 'package:master_palm/financeiro/v2/financial_v2_flags.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/screens/financeiro/dre_report_screen.dart';

void main() {
  const nathy = 'nathy-pratas-e-folheados';
  const mir = 'mirjoias';
  final now = DateTime(2026, 9, 28, 12);

  DreStatement read({
    String storeId = nathy,
    DrePeriod? period,
    List<Venda> sales = const [],
    List<LancamentoFinanceiro> entries = const [],
    List<DreHistoricalComponent> historical = const [],
    bool salesLoaded = true,
    bool expensesLoaded = true,
    bool discountSnapshotsPresent = true,
    double? estimatedCardFee,
    DateTime? clock,
  }) {
    final when = clock ?? now;
    return FinancialDreRead.calculate(
      DreReadInput(
        storeId: storeId,
        storeName: 'Nathy Pratas e Folheados',
        period: period ?? DrePeriod.month(const FinancialMonth(2026, 9)),
        now: when,
        generatedAt: DateTime(2026, 9, 28, 15, 4),
        sales: sales,
        entries: entries,
        historicalComponents: historical,
        salesLoaded: salesLoaded,
        expensesLoaded: expensesLoaded,
        discountSnapshotsPresent: discountSnapshotsPresent,
        estimatedCardFee: estimatedCardFee,
      ),
    );
  }

  Venda venda({
    String store = nathy,
    required double total,
    double custo = 0,
    double descontoValor = 0,
    DateTime? data,
    String? id,
    bool cancelada = false,
    String? origem,
  }) {
    return Venda(
      clienteNome: 'Cliente',
      produtosDescricao: 'item',
      quantidade: 1,
      preco: total,
      total: total,
      formasPagamento: 'Pix',
      data: data ?? DateTime(2026, 9, 10),
      vendedor: 'app',
      observacao: '',
      custoProdutos: custo,
      descontoValor: descontoValor,
      lojaId: store,
      idFirebase: id,
      origemVenda: origem,
      cancelada: cancelada,
    );
  }

  LancamentoFinanceiro lanc({
    required String id,
    required double valor,
    String tipo = FinanceiroTipoLancamento.despesaOperacional,
    String categoria = 'embalagens',
    String origem = FinanceiroOrigemLancamento.manual,
    String status = FinanceiroStatusLancamento.pago,
    String store = nathy,
    DateTime? competencia,
    DateTime? pagamento,
  }) {
    final data = competencia ?? DateTime(2026, 9, 12);
    return LancamentoFinanceiro(
      id: id,
      lojaId: store,
      descricao: 'Caixa de embalagem',
      valor: valor,
      tipo: tipo,
      categoria: categoria,
      status: status,
      origem: origem,
      dataLancamento: data,
      dataPagamento: pagamento,
      competenciaMes: data.month,
      competenciaAno: data.year,
    );
  }

  test('receita bruta usa venda válida e ignora cancelada e entrada extra', () {
    final statement = read(
      sales: [
        venda(total: 100, custo: 40, descontoValor: 0),
        venda(total: 50, custo: 10, cancelada: true),
      ],
      entries: [
        lanc(
          id: 'extra',
          valor: 80,
          tipo: FinanceiroTipoLancamento.entradaExtra,
          categoria: 'ajuste',
        ),
      ],
    );
    expect(statement.grossRevenue.amount, 100);
    expect(statement.netRevenue.amount, 100);
    expect(statement.sales, hasLength(1));
  });

  test('desconto confirmado reduz a receita líquida', () {
    final statement = read(
      sales: [venda(total: 90, custo: 30, descontoValor: 10)],
    );
    expect(statement.grossRevenue.amount, 100);
    expect(statement.discounts.amount, 10);
    expect(statement.netRevenue.amount, 90);
    expect(statement.netRevenue.amount, statement.grossRevenue.amount! - 10);
  });

  test('desconto desconhecido não vira zero', () {
    final statement = read(
      sales: [venda(total: 90, custo: 30)],
      discountSnapshotsPresent: false,
    );
    expect(statement.discounts.isKnown, isFalse);
    expect(statement.discounts.amount, isNull);
    expect(statement.netRevenue.amount, 90);
  });

  test('CMV vem do custo histórico da venda', () {
    final statement = read(
      sales: [venda(total: 100, custo: 40)],
    );
    expect(statement.cogs.amount, 40);
    expect(statement.grossProfit.amount, 60);
    expect(statement.grossProfitLabel, 'LUCRO BRUTO');
    expect(statement.cogsComplete, isTrue);
  });

  test('CMV ausente não entra como zero', () {
    final statement = read(
      sales: [
        venda(total: 100, custo: 40),
        venda(total: 50, custo: 0, id: 'sem-custo'),
      ],
    );
    expect(statement.salesWithMissingCogs, 1);
    expect(statement.cogs.amount, 40);
    expect(statement.cogs.amount, isNot(0));
    expect(statement.grossProfitLabel, 'LUCRO BRUTO CONHECIDO');
    expect(statement.cogsComplete, isFalse);
  });

  test('despesa operacional agrupa a categoria existente', () {
    final statement = read(
      sales: [venda(total: 100, custo: 40)],
      entries: [
        lanc(id: 'emb', valor: 30, categoria: 'embalagens'),
        lanc(
          id: 'net',
          valor: 20,
          categoria: 'internet',
          tipo: FinanceiroTipoLancamento.gastoFixo,
        ),
        lanc(
          id: 'equipe',
          valor: 15,
          tipo: FinanceiroTipoLancamento.pagamentoFuncionario,
          categoria: '',
        ),
      ],
    );
    expect(statement.operatingExpenses.amount, 65);
    expect(statement.operatingExpenseDocumentCount, 3);
    expect(
      statement.operatingExpenseLines.map((line) => line.label),
      containsAll(['Embalagens', 'Internet', 'Salários / equipe']),
    );
    expect(statement.operatingResult.amount, closeTo(-5, 0.001));
    expect(statement.operatingResultLabel, 'RESULTADO OPERACIONAL');
  });

  test('pagamento de compra não é CMV nem despesa operacional', () {
    final statement = read(
      sales: [venda(total: 100, custo: 40)],
      entries: [
        lanc(
          id: 'compra',
          valor: 500,
          tipo: FinanceiroTipoLancamento.compraMercadoria,
          categoria: 'compra_produtos',
        ),
      ],
    );
    expect(statement.cogs.amount, 40);
    expect(statement.operatingExpenses.amount, 0);
    expect(statement.netRevenue.amount, 100);
  });

  test('pagamento de conta a pagar não duplica despesa', () {
    final statement = read(
      sales: [venda(total: 100, custo: 40)],
      entries: [
        lanc(id: 'desp', valor: 40, categoria: 'embalagens'),
        lanc(
          id: 'baixa-pagar',
          valor: 40,
          categoria: 'embalagens',
          origem: FinanceiroOrigemLancamento.contaPagarCompra,
        ),
      ],
    );
    expect(statement.operatingExpenses.amount, 40);
    expect(statement.operatingExpenseDocumentCount, 1);
  });

  test('retirada não reduz o resultado operacional', () {
    final statement = read(
      sales: [venda(total: 100, custo: 40)],
      entries: [
        lanc(id: 'desp', valor: 10, categoria: 'marketing'),
        lanc(
          id: 'ret',
          valor: 200,
          tipo: FinanceiroTipoLancamento.retirada,
          categoria: 'retirada',
        ),
      ],
    );
    expect(statement.operatingExpenses.amount, 10);
    expect(statement.ownerWithdrawals?.amount, 200);
    expect(statement.operatingResult.amount, 50);
  });

  test('investimento fica fora do resultado operacional', () {
    final statement = read(
      sales: [venda(total: 100, custo: 40)],
      entries: [
        lanc(
          id: 'inv',
          valor: 800,
          tipo: FinanceiroTipoLancamento.investimento,
          categoria: 'moveis',
        ),
      ],
    );
    expect(statement.operatingExpenses.amount, 0);
    expect(statement.investments?.amount, 800);
    expect(statement.operatingResult.amount, 60);
    expect(
      statement.qualityNotes,
      contains(
        'Investimentos exibidos separadamente, fora do resultado operacional.',
      ),
    );
  });

  test('pró-labore não se mistura com retirada', () {
    final statement = read(
      entries: [
        lanc(
          id: 'pro',
          valor: 70,
          tipo: FinanceiroTipoLancamento.proLabore,
          categoria: 'pro_labore',
        ),
        lanc(
          id: 'ret',
          valor: 30,
          tipo: FinanceiroTipoLancamento.retirada,
          categoria: 'retirada',
        ),
      ],
    );
    expect(statement.proLabore?.amount, 70);
    expect(statement.ownerWithdrawals?.amount, 30);
    expect(statement.operatingExpenses.amount, 0);
  });

  test('recebimento de fiado não cria receita nova', () {
    final april = DrePeriod.month(const FinancialMonth(2026, 4));
    final statement = read(
      period: april,
      sales: [venda(total: 80, custo: 20, data: DateTime(2026, 3, 5))],
      entries: [
        lanc(
          id: 'fiado',
          valor: 80,
          tipo: FinanceiroTipoLancamento.entradaExtra,
          origem: FinanceiroOrigemLancamento.contaReceberFiado,
          competencia: DateTime(2026, 4, 8),
          pagamento: DateTime(2026, 4, 8),
        ),
      ],
    );
    expect(statement.grossRevenue.amount, 0);
    expect(statement.sales, isEmpty);
  });

  test('venda fiado entra na receita do mês da venda', () {
    final march = DrePeriod.month(const FinancialMonth(2026, 3));
    final statement = read(
      period: march,
      sales: [venda(total: 80, custo: 20, data: DateTime(2026, 3, 5))],
      entries: [
        lanc(
          id: 'fiado',
          valor: 80,
          tipo: FinanceiroTipoLancamento.entradaExtra,
          origem: FinanceiroOrigemLancamento.contaReceberFiado,
          competencia: DateTime(2026, 4, 8),
        ),
      ],
    );
    expect(statement.grossRevenue.amount, 80);
    expect(statement.netRevenue.amount, 80);
  });

  test('consignação não conta venda e lançamento duas vezes', () {
    final statement = read(
      sales: [
        venda(total: 80, custo: 0, id: 'csgn_abc', origem: 'consignment'),
      ],
      entries: [
        lanc(
          id: 'csgn_fin_abc',
          valor: 80,
          tipo: FinanceiroTipoLancamento.entradaExtra,
          origem: 'consignment',
        ),
      ],
    );
    expect(statement.grossRevenue.amount, 80);
    expect(statement.sales, hasLength(1));
  });

  test('taxa estimada de cartão não altera o resultado', () {
    final statement = read(
      sales: [venda(total: 100, custo: 40)],
      entries: [lanc(id: 'desp', valor: 10, categoria: 'internet')],
      estimatedCardFee: 12.5,
    );
    expect(statement.estimatedCardFee, 12.5);
    expect(statement.operatingResult.amount, 50);
    expect(
      DrePresentation.rows(statement).map((row) => row.amount),
      contains('ESTIMATIVA'),
    );
    expect(statement.qualityNotes.join(' '), contains('ESTIMATIVA'));
  });

  test('tributo não confirmado não é inventado', () {
    final statement = read(sales: [venda(total: 100, custo: 40)]);
    expect(
      statement.qualityNotes,
      contains(
        'Tributos não incluídos: não há valor contábil confirmado no período.',
      ),
    );
    expect(
      DrePresentation.rows(statement).map((row) => row.label).join(' '),
      isNot(contains('Simples')),
    );
    expect(statement.operatingResult.amount, 60);
  });

  test('tela, impressão e PDF usam os mesmos totais', () async {
    final statement = read(
      sales: [venda(total: 90, custo: 30, descontoValor: 10)],
      entries: [lanc(id: 'emb', valor: 5, categoria: 'embalagens')],
    );
    final screen = DrePresentation.rows(statement);
    final plan = DrePdfDocumentPlan.fromStatement(statement);
    expect(plan.fingerprint, statement.totalsFingerprint);
    expect(DrePresentation.fingerprint(statement), plan.fingerprint);
    expect(
      plan.rows.map((row) => row.amount).toList(),
      screen.map((row) => row.amount).toList(),
    );
    expect(plan.statement.operatingResult.amount, statement.operatingResult.amount);
    final bytes = await buildDrePdf(statement);
    expect(bytes, isNotEmpty);
    expect(dreFileName(statement), 'DRE_Nathy_Pratas_2026-09.pdf');
    expect(DreStatement.netProfitSupported, isFalse);
    expect(
      screen.map((row) => row.label).join(' '),
      isNot(contains('LUCRO LÍQUIDO')),
    );
  });

  test('loja cruzada não entra na DRE', () {
    final statement = read(
      sales: [
        venda(total: 10, custo: 4),
        venda(store: mir, total: 999, custo: 1),
      ],
      entries: [
        lanc(id: 'nathy', valor: 3, categoria: 'internet'),
        lanc(id: 'mir', valor: 700, store: mir, categoria: 'internet'),
      ],
    );
    expect(statement.grossRevenue.amount, 10);
    expect(statement.operatingExpenses.amount, 3);
    expect(statement.sales.where((row) => row.amount == 999), isEmpty);
  });

  test('fechamento sem CMV não transforma ausência em zero', () {
    final january = DrePeriod.month(const FinancialMonth(2026, 1));
    final statement = read(
      period: january,
      historical: [
        const DreHistoricalComponent(
          year: 2026,
          month: 1,
          grossRevenue: 221.98,
        ),
      ],
    );
    expect(statement.grossRevenue.amount, 221.98);
    expect(statement.cogs.amount, isNull);
    expect(statement.cogs.amount, isNot(0));
    expect(statement.operatingExpenses.amount, isNull);
    expect(statement.operatingResult.amount, isNull);
    expect(statement.usedHistoricalRevenue, isTrue);
  });

  test('mês corrente ignora fechamento', () {
    final statement = read(
      sales: [venda(total: 100, custo: 40)],
      historical: [
        const DreHistoricalComponent(
          year: 2026,
          month: 9,
          grossRevenue: 999,
          cogs: 1,
        ),
      ],
    );
    expect(statement.grossRevenue.amount, 100);
    expect(statement.ignoredCurrentMonthClosure, isTrue);
  });

  test('seletor de período reusa o mês financeiro', () {
    expect(FinancialDrePolicy.periodSelectorReusesFinancialHistory, isTrue);
    final september = DrePeriod.month(const FinancialMonth(2026, 9));
    expect(september.label, 'Setembro de 2026');
    expect(
      september.label,
      contains(FinancialMonth.monthNamesPt[8]),
    );
    final year = DrePeriod.year(2026, now: now);
    expect(year.label, 'Janeiro–Setembro de 2026');
    expect(
      dreFileName(
        read(period: year, sales: [venda(total: 10, custo: 1)]),
      ),
      'DRE_Nathy_Pratas_2026.pdf',
    );
    final custom = DrePeriod.custom(
      start: DateTime(2026, 4, 1),
      end: DateTime(2026, 6, 30),
    );
    expect(custom.label, '01/04/2026–30/06/2026');
    expect(formatDreMoney(1234.56), r'R$ 1.234,56');
  });

  test('despesa segue a competência, não o pagamento', () {
    final september = DrePeriod.month(const FinancialMonth(2026, 9));
    final may = DrePeriod.month(const FinancialMonth(2026, 5));
    final entry = lanc(
      id: 'comp',
      valor: 49.9,
      categoria: 'internet',
      competencia: DateTime(2026, 5, 10),
      pagamento: DateTime(2026, 9, 2),
      status: FinanceiroStatusLancamento.pendente,
    );
    expect(read(period: september, entries: [entry]).operatingExpenses.amount, 0);
    expect(read(period: may, entries: [entry]).operatingExpenses.amount, 49.9);
  });

  test('preview da DRE é só da Nathy e o flag global continua falso', () {
    expect(FinancialV2Flags.dreEnabled, isFalse);
    expect(FinancialDrePolicy.showEntry(storeId: nathy), isTrue);
    expect(FinancialDrePolicy.showEntry(storeId: mir), isFalse);
    expect(FinancialDrePolicy.readOnly, isTrue);
    expect(FinancialDrePolicy.financialWrites, 0);
    expect(FinancialDrePolicy.ledgerWrites, 0);
    expect(FinancialDrePolicy.netProfitSupported, isFalse);
    expect(
      FinancialLaunchCatalog.shortcuts.map((item) => item.id),
      isNot(contains('dre')),
    );
  });

  testWidgets('drilldown é somente leitura', (tester) async {
    final statement = read(
      sales: [venda(total: 100, custo: 40)],
      entries: [lanc(id: 'emb', valor: 30, categoria: 'embalagens')],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DreReportScreen(
          storeId: nathy,
          storeName: 'Nathy Pratas',
          previewStatement: statement,
          now: now,
        ),
      ),
    );
    expect(find.byKey(const Key('dre-quality-panel')), findsOneWidget);
    expect(find.byKey(const Key('dre-print')), findsOneWidget);
    expect(find.byKey(const Key('dre-pdf')), findsOneWidget);
    await tester.tap(find.text('Embalagens'));
    await tester.pumpAndSettle();
    expect(find.text('Caixa de embalagem'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.edit), findsNothing);
    expect(find.text('Fechar'), findsOneWidget);
  });
}
