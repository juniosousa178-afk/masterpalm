import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/financeiro/lancamento_lista_filtro.dart';
import 'package:master_palm/financeiro/v2/financial_authority.dart';
import 'package:master_palm/financeiro/v2/financial_dashboard_pilot.dart';
import 'package:master_palm/financeiro/v2/financial_home_route.dart';
import 'package:master_palm/financeiro/v2/financial_launch_catalog.dart';
import 'package:master_palm/financeiro/v2/financial_overview_loader.dart';
import 'package:master_palm/financeiro/v2/financial_read_model.dart';
import 'package:master_palm/financeiro/v2/financial_v2_flags.dart';
import 'package:master_palm/financeiro/v2/financial_v2_operational_hub.dart';
import 'package:master_palm/financeiro/v2/financial_v2_preview_screen.dart';
import 'package:master_palm/models/conta_pagar.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/screens/financeiro/financeiro_lancamentos_screen.dart';
import 'package:master_palm/screens/financeiro/gastos_fixos_screen.dart';

void main() {
  test('each new launch reuses an existing flow and writes nothing', () {
    expect(FinancialLaunchCatalog.createsFinancialRecord, isFalse);
    expect(FinancialLaunchCatalog.ledgerWrites, 0);
    expect(FinancialV2Flags.financialLedgerWrites, 0);
    expect(FinancialV2Flags.dreEnabled, isFalse);
    expect(FinancialV2Flags.financialV2Enabled, isFalse);
    expect(FinancialV2Flags.payablesRemoteMirrorEnabled, isFalse);
    expect(FinancialAuthority.localOnly, isNotNull);

    final ids = FinancialLaunchCatalog.options.map((item) => item.id).toSet();
    expect(ids, {
      'compra_mercadoria',
      'despesa',
      'conta_pagar',
      'gasto_recorrente',
      'entrada_extra',
      'salario',
      'pro_labore',
      'retirada',
      'investimento',
    });

    for (final destination in [
      ...FinancialLaunchCatalog.options,
      ...FinancialLaunchCatalog.shortcuts,
    ]) {
      expect(destination.persists, isFalse, reason: destination.id);
      expect(destination.screen, isNotEmpty);
      expect(destination.service, isNotEmpty);
    }

    expect(
      FinancialLaunchCatalog.options.map((item) => item.tipoLancamento),
      isNot(contains(FinanceiroTipoLancamento.compraMercadoria)),
    );
    expect(
      FinancialLaunchCatalog.options.map((item) => item.id),
      isNot(contains('venda')),
    );
    expect(
      FinancialLaunchCatalog.options.map((item) => item.id),
      isNot(contains('fiado')),
    );
  });

  test('purchase routes to the supplier purchase module', () {
    final purchase = FinancialLaunchCatalog.compraMercadoria;
    expect(purchase.route, '/fornecedores');
    expect(purchase.navigation, FinancialHubNavigation.namedRoute);
    expect(purchase.tipoLancamento, isNull);
    expect(purchase.screen, contains('CompraFornecedorFormScreen'));
    expect(purchase.service, contains('ContaPagarService.gerarParcelasCompra'));
    expect(purchase.service, contains('CompraFornecedor'));
    expect(purchase.screen, isNot(contains('FinanceiroLancamentosScreen')));
    expect(FinancialLaunchCatalog.compras.route, purchase.route);
  });

  test('expense, salary, pro-labore, withdrawal and investment reuse types', () {
    expect(
      FinancialLaunchCatalog.despesa.tipoLancamento,
      FinanceiroTipoLancamento.despesaOperacional,
    );
    expect(
      FinancialLaunchCatalog.despesa.navigation,
      FinancialHubNavigation.existingLancamento,
    );
    expect(FinancialLaunchCatalog.despesa.openNewForm, isTrue);
    expect(FinancialLaunchCatalog.despesa.categoria, isNull);
    expect(
      FinancialLaunchCatalog.salario.tipoLancamento,
      FinanceiroTipoLancamento.pagamentoFuncionario,
    );
    expect(
      FinancialLaunchCatalog.proLabore.tipoLancamento,
      FinanceiroTipoLancamento.proLabore,
    );
    expect(
      FinancialLaunchCatalog.retirada.tipoLancamento,
      FinanceiroTipoLancamento.retirada,
    );
    expect(
      FinancialLaunchCatalog.investimento.tipoLancamento,
      FinanceiroTipoLancamento.investimento,
    );
    expect(
      FinancialLaunchCatalog.entradaExtra.tipoLancamento,
      FinanceiroTipoLancamento.entradaExtra,
    );

    final tipos = {
      FinancialLaunchCatalog.despesa.tipoLancamento,
      FinancialLaunchCatalog.salario.tipoLancamento,
      FinancialLaunchCatalog.proLabore.tipoLancamento,
      FinancialLaunchCatalog.retirada.tipoLancamento,
      FinancialLaunchCatalog.investimento.tipoLancamento,
      FinancialLaunchCatalog.entradaExtra.tipoLancamento,
    };
    expect(tipos, hasLength(6));
    expect(
      kFinanceiroCategoriasPadrao.any(
        (item) => item.categoria == financialExistingPackagingCategory,
      ),
      isTrue,
    );
    expect(financialExistingPackagingCategory, 'embalagens');
  });

  test('payable and fixed expense stay on the existing screens', () {
    expect(FinancialLaunchCatalog.contaPagar.route, '/contas_pagar');
    expect(FinancialLaunchCatalog.contaPagar.screen, 'ContasPagarScreen');
    expect(FinancialLaunchCatalog.pagar.route, '/contas_pagar');
    expect(
      FinancialLaunchCatalog.gastoRecorrente.navigation,
      FinancialHubNavigation.existingFixedExpenses,
    );
    expect(FinancialLaunchCatalog.gastoRecorrente.screen, 'GastosFixosScreen');
    expect(FinancialLaunchCatalog.gastosFixos.screen, 'GastosFixosScreen');
    expect(FinancialLaunchCatalog.receber.route, '/contas_receber');
    expect(FinancialLaunchCatalog.relatorios.route, '/relatorios_financeiros');
    expect(FinancialLaunchCatalog.lancamentos.showFilters, isTrue);
    expect(FinancialLaunchCatalog.lancamentos.openNewForm, isFalse);
  });

  test('helper text warns against the common classification mistakes', () {
    expect(
      FinancialLaunchCatalog.compraMercadoria.helper,
      'Para produtos comprados para revenda.',
    );
    expect(
      FinancialLaunchCatalog.despesa.helper,
      contains('Embalagens'),
    );
    expect(
      FinancialLaunchCatalog.contaPagar.helper,
      'Para registrar um compromisso com vencimento futuro.',
    );
    expect(
      FinancialLaunchCatalog.entradaExtra.helper,
      contains('não vieram de uma venda'),
    );
    expect(
      FinancialLaunchCatalog.entradaExtra.helper,
      contains('fiado'),
    );
  });

  test('pending expense is still not a cash outflow and filters stay local', () {
    expect(
      FinanceiroStatusLancamento.statusLiquidado(
        FinanceiroStatusLancamento.pendente,
      ),
      isFalse,
    );
    expect(
      FinanceiroStatusLancamento.statusLiquidado(
        FinanceiroStatusLancamento.pago,
      ),
      isTrue,
    );

    const pendingExpense = LancamentoListaConsulta(
      recorte: LancamentoListaRecorte.pagos,
    );
    expect(
      pendingExpense.aceita(
        tipo: FinanceiroTipoLancamento.despesaOperacional,
        valor: 40,
        status: FinanceiroStatusLancamento.pendente,
        categoria: 'embalagens',
        data: DateTime(2026, 9, 10),
      ),
      isFalse,
    );

    final packaging = LancamentoListaConsulta(
      recorte: LancamentoListaRecorte.saidas,
      categoria: 'embalagens',
      periodoInicio: DateTime(2026, 9, 1),
      periodoFimExclusivo: DateTime(2026, 10, 1),
    );
    expect(
      packaging.aceita(
        tipo: FinanceiroTipoLancamento.despesaOperacional,
        valor: 40,
        status: FinanceiroStatusLancamento.pendente,
        categoria: 'embalagens',
        data: DateTime(2026, 9, 10),
      ),
      isTrue,
    );
    expect(
      packaging.aceita(
        tipo: FinanceiroTipoLancamento.despesaOperacional,
        valor: 40,
        status: FinanceiroStatusLancamento.pago,
        categoria: 'marketing',
        data: DateTime(2026, 9, 10),
      ),
      isFalse,
    );
    expect(
      packaging.aceita(
        tipo: FinanceiroTipoLancamento.despesaOperacional,
        valor: 40,
        status: FinanceiroStatusLancamento.pago,
        categoria: 'embalagens',
        data: DateTime(2026, 8, 10),
      ),
      isFalse,
    );
    expect(
      lancamentoEhEntrada(
        tipo: FinanceiroTipoLancamento.entradaExtra,
        valor: 10,
      ),
      isTrue,
    );
    expect(
      lancamentoEhEntrada(
        tipo: FinanceiroTipoLancamento.retirada,
        valor: 10,
      ),
      isFalse,
    );
    expect(
      lancamentoEhEntrada(
        tipo: FinanceiroTipoLancamento.proLabore,
        valor: 10,
      ),
      isFalse,
    );
  });

  test('hub stays off unless the read-only pilot is on', () {
    expect(FinancialV2OperationalPolicy.directFinancialWrites, 0);
    expect(
      FinancialV2OperationalPolicy.hubEnabled(
        showReadOnlyDashboard: false,
        operationalHubEnabled: true,
      ),
      isFalse,
    );
    expect(
      FinancialV2OperationalPolicy.hubEnabled(
        showReadOnlyDashboard: true,
        operationalHubEnabled: false,
      ),
      isFalse,
    );
    expect(
      FinancialV2OperationalPolicy.hubEnabled(
        showReadOnlyDashboard: true,
        operationalHubEnabled: true,
      ),
      isTrue,
    );
    expect(FinancialDashboardPilot.disabled.showReadOnlyDashboard, isFalse);
    expect(FinancialDashboardPilot.disabled.showOperationalHub, isFalse);

    const nathy = 'nathy-pratas-e-folheados';
    final legacy = financialDashboardPilotFromMap(
      storeId: nathy,
      data: {
        'storeId': nathy,
        'financialV2Enabled': true,
        'readOnly': true,
      },
    );
    expect(legacy.dashboardReadOnly, isTrue);
    expect(legacy.showOperationalHub, isFalse);

    final released = financialDashboardPilotFromMap(
      storeId: nathy,
      data: {
        'storeId': nathy,
        'financialV2Enabled': true,
        'readOnly': true,
        'dashboardReadOnly': true,
        'operationalHubEnabled': true,
      },
    );
    expect(released.dashboardReadOnly, isTrue);
    expect(released.showOperationalHub, isTrue);

    final mir = financialDashboardPilotFromMap(
      storeId: 'mirjoias',
      data: null,
    );
    expect(mir.showReadOnlyDashboard, isFalse);
    expect(mir.showOperationalHub, isFalse);

    final disagreed = financialDashboardPilotFromMap(
      storeId: nathy,
      data: {
        'storeId': nathy,
        'financialV2Enabled': true,
        'readOnly': true,
        'dashboardReadOnly': false,
        'operationalHubEnabled': true,
      },
    );
    expect(disagreed.showReadOnlyDashboard, isFalse);
    expect(disagreed.showOperationalHub, isFalse);
  });

  testWidgets('disabled pilot keeps the old financeiro screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FinancialHomeRoute(
          debugPilot: FinancialDashboardPilot.disabled,
          debugStoreId: 'mirjoias',
          oldScreen: () => const Text('financeiro-antigo'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('financeiro-antigo'), findsOneWidget);
    expect(find.text(financialNewLaunchLabel), findsNothing);
  });

  testWidgets('internal preview without the hub flag stays read-only', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FinancialV2PreviewScreen(
          debugIsAdmin: true,
          debugStoreId: 'nathy-pratas-e-folheados',
          debugReads: _EmptyReads(),
          debugToday: DateTime(2026, 9, 27),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Faturamento'), findsOneWidget);
    expect(find.text(financialNewLaunchLabel), findsNothing);
  });

  testWidgets('pilot hub shows the launch button and keeps the cards', (
    tester,
  ) async {
    await _pumpHubPreview(tester, const Size(1280, 900));
    expect(find.text('Visão financeira'), findsOneWidget);
    expect(find.text(financialNewLaunchLabel), findsOneWidget);
    final button = tester.getSize(find.byKey(const Key('financial-v2-new-launch')));
    expect(button.height, lessThan(64));
    expect(button.width, lessThan(420));
    expect(find.text('Faturamento'), findsOneWidget);
    expect(find.text('Lucro bruto'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _pumpHubPreview(tester, const Size(390, 844));
    expect(find.text(financialNewLaunchLabel), findsOneWidget);
    expect(find.text('Lançamentos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new launch and shortcuts open the existing screens', (
    tester,
  ) async {
    await _pumpHub(tester, const Size(400, 1200));
    final cases = <String, void Function()>{
      'compra_mercadoria': () =>
          expect(find.text('rota-fornecedores'), findsOneWidget),
      'despesa': () => _expectLancamento(
            tester,
            FinanceiroTipoLancamento.despesaOperacional,
          ),
      'conta_pagar': () =>
          expect(find.text('rota-contas-pagar'), findsOneWidget),
      'gasto_recorrente': () =>
          expect(find.byType(GastosFixosScreen), findsOneWidget),
      'entrada_extra': () => _expectLancamento(
            tester,
            FinanceiroTipoLancamento.entradaExtra,
          ),
      'salario': () => _expectLancamento(
            tester,
            FinanceiroTipoLancamento.pagamentoFuncionario,
          ),
      'pro_labore': () => _expectLancamento(
            tester,
            FinanceiroTipoLancamento.proLabore,
          ),
      'retirada': () => _expectLancamento(
            tester,
            FinanceiroTipoLancamento.retirada,
          ),
      'investimento': () => _expectLancamento(
            tester,
            FinanceiroTipoLancamento.investimento,
          ),
    };

    for (final entry in cases.entries) {
      await _openChooser(tester);
      expect(find.text(financialLaunchChooserTitle), findsOneWidget);
      await _tapLaunch(tester, entry.key);
      entry.value();
      if (entry.key != 'compra_mercadoria' && entry.key != 'conta_pagar') {
        final lancamento = find.byType(FinanceiroLancamentosScreen);
        if (lancamento.evaluate().isNotEmpty) {
          final screen = tester.widget<FinanceiroLancamentosScreen>(lancamento);
          expect(screen.abrirFormularioNovo, isTrue);
          expect(screen.mostrarFiltros, isFalse);
        }
      }
      await _popRoute(tester);
    }

    await _tapShortcut(tester, 'lancamentos');
    final list = tester.widget<FinanceiroLancamentosScreen>(
      find.byType(FinanceiroLancamentosScreen),
    );
    expect(list.mostrarFiltros, isTrue);
    expect(list.abrirFormularioNovo, isFalse);
    expect(list.tipoNovo, isNull);
    await _popRoute(tester);
    expect(find.text(financialNewLaunchLabel), findsOneWidget);

    await _tapShortcut(tester, 'receber');
    expect(find.text('rota-contas-receber'), findsOneWidget);
    await _popRoute(tester);

    await _tapShortcut(tester, 'pagar');
    expect(find.text('rota-contas-pagar'), findsOneWidget);
    await _popRoute(tester);

    await _tapShortcut(tester, 'compras');
    expect(find.text('rota-fornecedores'), findsOneWidget);
    await _popRoute(tester);

    await _tapShortcut(tester, 'gastos_fixos');
    expect(find.byType(GastosFixosScreen), findsOneWidget);
    await _popRoute(tester);

    await _tapShortcut(tester, 'relatorios');
    expect(find.text('rota-relatorios'), findsOneWidget);
  });

  testWidgets('mobile chooser can open the last option', (tester) async {
    await _pumpHub(tester, const Size(390, 844));
    await _openChooser(tester);
    await _tapLaunch(tester, 'investimento');
    _expectLancamento(tester, FinanceiroTipoLancamento.investimento);
    expect(tester.takeException(), isNull);
  });
}

void _expectLancamento(WidgetTester tester, String tipo) {
  final screen = tester.widget<FinanceiroLancamentosScreen>(
    find.byType(FinanceiroLancamentosScreen),
  );
  expect(screen.tipoNovo, tipo);
  expect(screen.lojaId, 'nathy-pratas-e-folheados');
}

Future<void> _pumpHubPreview(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: FinancialV2PreviewScreen(
        debugIsAdmin: true,
        debugStoreId: 'nathy-pratas-e-folheados',
        debugReads: _EmptyReads(),
        debugToday: DateTime(2026, 9, 27),
        operationalHub: true,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpHub(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: const Scaffold(
        body: FinancialV2OperationalHub(
          enabled: true,
          storeId: 'nathy-pratas-e-folheados',
          overview: Text('cartao-somente-leitura'),
        ),
      ),
      routes: {
        '/fornecedores': (_) => const Scaffold(
              body: Text('rota-fornecedores'),
            ),
        '/contas_pagar': (_) => const Scaffold(
              body: Text('rota-contas-pagar'),
            ),
        '/contas_receber': (_) => const Scaffold(
              body: Text('rota-contas-receber'),
            ),
        '/relatorios_financeiros': (_) => const Scaffold(
              body: Text('rota-relatorios'),
            ),
      },
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openChooser(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('financial-v2-new-launch')));
  await tester.pumpAndSettle();
}

Future<void> _tapLaunch(WidgetTester tester, String id) async {
  final tile = find.byKey(Key('financial-launch-$id'));
  final sheetScroll = find.descendant(
    of: find.byType(ListView),
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(tile, 280, scrollable: sheetScroll);
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

Future<void> _tapShortcut(WidgetTester tester, String id) async {
  final chip = find.byKey(Key('financial-hub-$id'));
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

Future<void> _popRoute(WidgetTester tester) async {
  final navigator = tester.state<NavigatorState>(find.byType(Navigator));
  navigator.pop();
  await tester.pumpAndSettle();
}

class _EmptyReads implements FinancialPeriodReads {
  @override
  int get remoteQueryCount => 0;

  @override
  int get localReadCount => 0;

  @override
  Future<List<Venda>> sales({
    required String storeId,
    required FinancialPeriod period,
  }) async =>
      const [];

  @override
  Future<List<LancamentoFinanceiro>> entries({
    required String storeId,
    required FinancialPeriod period,
  }) async =>
      const [];

  @override
  Future<List<ContaReceber>> openReceivables({required String storeId}) async =>
      const [];

  @override
  Future<List<ContaPagar>> payables({required String storeId}) async =>
      const [];
}
