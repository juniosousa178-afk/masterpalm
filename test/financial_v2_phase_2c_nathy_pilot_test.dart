import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/financeiro/v2/financial_authority.dart';
import 'package:master_palm/financeiro/v2/financial_chart_axis.dart';
import 'package:master_palm/financeiro/v2/financial_dashboard_gate.dart';
import 'package:master_palm/financeiro/v2/financial_dashboard_pilot.dart';
import 'package:master_palm/financeiro/v2/financial_dashboard_presentation.dart';
import 'package:master_palm/financeiro/v2/financial_home_route.dart';
import 'package:master_palm/financeiro/v2/financial_overview_loader.dart';
import 'package:master_palm/financeiro/v2/financial_read_model.dart';
import 'package:master_palm/financeiro/v2/financial_v2_dashboard_view.dart';
import 'package:master_palm/financeiro/v2/financial_v2_flags.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/models/venda_item.dart';

void main() {
  test('y axis width follows the largest compact label', () {
    const samples = <double>[950, 1250, 9999, 10000, 125000, 1000000];
    expect(compactChartAxisLabel(950), '950');
    expect(compactChartAxisLabel(1250), '1,3 mil');
    expect(compactChartAxisLabel(9999), '10 mil');
    expect(compactChartAxisLabel(10000), '10 mil');
    expect(compactChartAxisLabel(125000), '125 mil');
    expect(compactChartAxisLabel(1000000), '1 mi');

    for (final value in samples) {
      final label = compactChartAxisLabel(value);
      final painter = TextPainter(
        text: TextSpan(text: label, style: chartAxisLabelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final reserved = chartYAxisReservedWidth([value]);
      expect(reserved, greaterThanOrEqualTo(painter.width));
      expect(label, isNot(contains('R\$')));
    }
    expect(
      chartYAxisReservedWidth([125000]),
      greaterThan(chartYAxisReservedWidth([950])),
    );
  });

  test('dashboard pilot is store scoped and fails closed', () {
    expect(FinancialV2Flags.financialV2Enabled, isFalse);
    expect(FinancialV2DashboardGate.replacesCurrentFinanceiro, isFalse);
    expect(FinancialV2DashboardGate.showInHomeMenu, isFalse);
    expect(FinancialDashboardPilot.documentId, 'dashboard');

    const nathy = 'nathy-pratas-e-folheados';
    expect(
      financialDashboardPilotFromMap(
        storeId: nathy,
        data: {
          'storeId': nathy,
          'financialV2Enabled': true,
          'readOnly': true,
        },
      ).showReadOnlyDashboard,
      isTrue,
    );
    expect(
      financialDashboardPilotFromMap(
        storeId: 'mirjoias',
        data: null,
      ).showReadOnlyDashboard,
      isFalse,
    );
    expect(
      financialDashboardPilotFromMap(
        storeId: nathy,
        data: {
          'storeId': nathy,
          'financialV2Enabled': false,
          'readOnly': true,
        },
      ).showReadOnlyDashboard,
      isFalse,
    );
    expect(
      financialDashboardPilotFromMap(
        storeId: nathy,
        data: {
          'storeId': nathy,
          'financialV2Enabled': true,
          'readOnly': false,
          'payablesRemoteMirrorEnabled': true,
        },
      ).showReadOnlyDashboard,
      isFalse,
    );
    expect(
      financialDashboardPilotFromMap(
        storeId: nathy,
        data: {
          'storeId': 'mirjoias',
          'financialV2Enabled': true,
          'readOnly': true,
        },
      ).showReadOnlyDashboard,
      isFalse,
    );
  });

  test('pilot read failure and timeout keep the old screen', () async {
    final missing = await readFinancialDashboardPilot(
      storeId: 'mirjoias',
      load: () async => null,
    );
    expect(missing.showReadOnlyDashboard, isFalse);

    final failed = await readFinancialDashboardPilot(
      storeId: 'nathy-pratas-e-folheados',
      load: () async => throw StateError('permission'),
    );
    expect(failed.showReadOnlyDashboard, isFalse);

    final timedOut = await readFinancialDashboardPilot(
      storeId: 'nathy-pratas-e-folheados',
      timeout: const Duration(milliseconds: 20),
      load: () => Future<Map<String, dynamic>?>.delayed(
        const Duration(seconds: 2),
        () => {
          'storeId': 'nathy-pratas-e-folheados',
          'financialV2Enabled': true,
          'readOnly': true,
        },
      ),
    );
    expect(timedOut.showReadOnlyDashboard, isFalse);
  });

  test('firestore pilot read does not write', () async {
    final firestore = FakeFirebaseFirestore();
    const nathy = 'nathy-pratas-e-folheados';
    await firestore
        .collection('lojas')
        .doc(nathy)
        .collection('financial_v2_pilot')
        .doc('dashboard')
        .set({
      'storeId': nathy,
      'financialV2Enabled': true,
      'readOnly': true,
    });
    await firestore
        .collection('lojas')
        .doc(nathy)
        .collection('financial_v2_pilot')
        .doc('payables')
        .set({
      'storeId': nathy,
      'payablesRemoteMirrorEnabled': true,
    });

    final source = FirestoreFinancialDashboardPilotSource(firestore: firestore);
    final nathyPilot = await source.read(nathy);
    final mirPilot = await source.read('mirjoias');
    expect(nathyPilot.showReadOnlyDashboard, isTrue);
    expect(mirPilot.showReadOnlyDashboard, isFalse);

    final payable = await firestore
        .collection('lojas')
        .doc(nathy)
        .collection('financial_v2_pilot')
        .doc('payables')
        .get();
    expect(payable.data()?['payablesRemoteMirrorEnabled'], isTrue);
    final dashboardDocs = await firestore
        .collection('lojas')
        .doc(nathy)
        .collection('financial_v2_pilot')
        .get();
    expect(dashboardDocs.docs.map((doc) => doc.id).toSet(), {
      'dashboard',
      'payables',
    });
  });

  test('receipts above sales are explained without changing totals', () {
    final period = FinancialPeriod(
      start: DateTime(2026, 9, 1),
      end: DateTime(2026, 9, 30),
    );
    final read = FinancialMetricsCalculator.dashboardRead(
      FinancialDataSources.scoped(
        storeId: 'nathy-pratas-e-folheados',
        period: period,
        today: DateTime.utc(2026, 9, 27, 12),
        sales: [
          _sale(total: 100, pix: 100),
        ],
        entries: [
          LancamentoFinanceiro(
            id: 'mp_cr2_baixa',
            lojaId: 'nathy-pratas-e-folheados',
            descricao: '',
            valor: 50,
            tipo: FinanceiroTipoLancamento.entradaExtra,
            status: FinanceiroStatusLancamento.pago,
            dataLancamento: DateTime.utc(2026, 9, 13, 15),
            dataPagamento: DateTime.utc(2026, 9, 13, 15),
            origem: FinanceiroOrigemLancamento.contaReceberFiado,
            referenciaExterna: 'mp_cr2_baixa',
          ),
        ],
      ),
    );
    final cards = presentFinancialDashboard(
      read: read,
      salesAvailable: true,
      entriesAvailable: true,
      receivablesAvailable: true,
      payablesAvailable: true,
    );
    expect(cards.faturamento.valueText, 'R\$ 100,00');
    expect(cards.recebimentos.valueText, 'R\$ 150,00');
    expect(cards.recebimentos.footnote, receiptsGreaterThanSalesExplanation);
    expect(
      cards.recebimentos.tooltip,
      contains(receiptsGreaterThanSalesExplanation),
    );
    expect(cards.recebimentos.footnote, isNot(contains('522')));
    expect(cards.showsAvailableBalance, isFalse);
    expect(cards.showsDre, isFalse);
    expect(cards.showsNetProfit, isFalse);
    expect(read.overview.payablesAuthority, FinancialAuthority.localOnly);
    expect(cards.aPagar.footnote, 'Neste dispositivo');
  });

  testWidgets('charts keep axis labels inside desktop and mobile cards',
      (tester) async {
    final period = FinancialPeriod(
      start: DateTime(2026, 9, 1),
      end: DateTime(2026, 9, 30),
    );
    final read = FinancialMetricsCalculator.dashboardRead(
      FinancialDataSources.scoped(
        storeId: 'nathy-pratas-e-folheados',
        period: period,
        today: DateTime(2026, 9, 27),
        sales: [_sale(total: 1000000, pix: 125000)],
      ),
    );
    final data = FinancialDashboardViewData(
      storeId: 'nathy-pratas-e-folheados',
      period: period,
      today: DateTime(2026, 9, 27),
      read: read,
      salesAvailable: true,
      entriesAvailable: true,
      receivablesAvailable: true,
      payablesAvailable: true,
      remoteQueryCount: 4,
      localReadCount: 1,
      remoteWrites: 0,
    );

    Future<void> pump(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FinancialV2DashboardView(
              data: data,
              periodKind: FinancialDashboardPeriodKind.currentMonth,
              onPeriod: (_) {},
              onRefresh: () {},
              onOpenReceivables: () {},
              onOpenPayables: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Entradas x saídas'),
        400,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('1 mi'), findsWidgets);
      expect(find.text('125 mil'), findsWidgets);
      expect(find.text('Entradas x saídas'), findsOneWidget);
      expect(find.text('Faturamento x recebimentos'), findsOneWidget);
    }

    await pump(const Size(1280, 900));
    await pump(const Size(390, 844));
    addTearDown(tester.view.resetPhysicalSize);
  });

  testWidgets('financeiro route follows the pilot flag', (tester) async {
    Future<void> pump(FinancialDashboardPilot pilot) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FinancialHomeRoute(
            key: ValueKey('${pilot.enabled}-${pilot.readOnly}'),
            debugPilot: pilot,
            oldScreen: () => const Text('financeiro-antigo'),
            dashboard: () => const Text('financeiro-v2'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pump(const FinancialDashboardPilot(enabled: true, readOnly: true));
    expect(find.text('financeiro-v2'), findsOneWidget);

    await pump(const FinancialDashboardPilot(enabled: false, readOnly: true));
    expect(find.text('financeiro-antigo'), findsOneWidget);

    await pump(FinancialDashboardPilot.disabled);
    expect(find.text('financeiro-antigo'), findsOneWidget);
  });
}

Venda _sale({required double total, required double pix}) {
  return Venda(
    clienteNome: '',
    produtosDescricao: '',
    quantidade: 1,
    preco: total,
    total: total,
    formasPagamento: 'Pix',
    data: DateTime.utc(2026, 9, 10, 15),
    vendedor: '',
    observacao: '',
    pagamentoPix: pix,
    custoProdutos: 10,
    lojaId: 'nathy-pratas-e-folheados',
    itens: [
      VendaItem(
        produtoNome: 'item',
        quantidade: 1,
        precoUnitario: total,
        custoUnitario: 10,
      ),
    ],
  );
}
