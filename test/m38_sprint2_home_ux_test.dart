// M3.8 S2-R3/R4 — HOMEUX regressão (compatível com favoritos R4).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/app_module_definition.dart';
import 'package:master_palm/core/home_module_registry.dart';
import 'package:master_palm/core/plan_matrix.dart';
import 'package:master_palm/services/home_category_insight_service.dart';
import 'package:master_palm/services/home_ux_prefs_service.dart';
import 'package:master_palm/widgets/home_module_accordion.dart';

HomeModuleAccessContext _adminCtx({PlanAccessTier tier = PlanAccessTier.lifetime}) {
  return HomeModuleAccessContext(
    tipoUsuario: 'admin',
    permissoes: const {
      'estoque': true,
      'vendas': true,
      'clientes': true,
      'fornecedores': true,
      'catalogo': true,
      'minha_loja': true,
    },
    planTier: tier,
    applyPlanGate: true,
  );
}

void main() {
  setUp(() {
    HomeUxPrefsService.useDebugMemory = true;
    HomeUxPrefsService.resetDebugMemory();
    HomeUxPrefsService.useDebugMemory = true;
    HomeCategoryInsightService.enableRemoteLoads = false;
  });

  tearDown(() {
    HomeUxPrefsService.resetDebugMemory();
    HomeCategoryInsightService.enableRemoteLoads = true;
  });

  testWidgets('HOMEUX-1 categorias fechadas inicialmente', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeModuleAccordion(
            access: _adminCtx(),
            lojaId: 'loja1',
            onModuleTap: (_, {required planLocked}) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('HOMEUX-2 abre Operações', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeModuleAccordion(
            access: _adminCtx(),
            lojaId: 'loja1',
            onModuleTap: (_, {required planLocked}) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Operações ('));
    await tester.pumpAndSettle();
    expect(find.text('Fornecedores'), findsWidgets);
  });

  testWidgets('HOMEUX-3 ao abrir outra categoria fecha a anterior', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeModuleAccordion(
            access: _adminCtx(),
            lojaId: 'loja1',
            onModuleTap: (_, {required planLocked}) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Operações ('));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('Marketing ('),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.textContaining('Marketing ('));
    await tester.pumpAndSettle();
    expect(await HomeUxPrefsService.getOpenCategoryId('loja1'), 'marketing');
  });

  test('HOMEUX-4 atalhos corretos por categoria', () {
    final vendas = HomeModuleRegistry.byCategory(HomeModuleCategory.vendas);
    expect(vendas.map((e) => e.id),
        containsAll(['vendas', 'carrinhos_abandonados', 'pre_pedidos']));
  });

  test('HOMEUX-5 rotas corretas', () {
    expect(HomeModuleRegistry.byId('estoque')!.route, '/estoque');
    expect(HomeModuleRegistry.byId('catalogo_interno')!.route, '/catalogo_interno');
    expect(HomeModuleRegistry.byId('catalogo_loja')!.route, '/catalogo_loja');
    expect(
      HomeModuleRegistry.byId('catalogo_loja')!.category,
      HomeModuleCategory.marketing,
    );
    expect(HomeModuleRegistry.duplicateRoutes(), isEmpty);
  });

  test('HOMEUX-6 gates de plano/permissão', () {
    final free = _adminCtx(tier: PlanAccessTier.freeLimited);
    final mod = HomeModuleRegistry.byId('carrinhos_abandonados')!;
    expect(HomeModuleRegistry.isPlanLocked(mod, free), isTrue);
  });

  test('HOMEUX-7 sem atalhos duplicados', () {
    final ids = HomeModuleRegistry.all.map((e) => e.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  testWidgets('HOMEUX-8 layout mobile sem overflow', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 844,
            child: HomeModuleAccordion(
              access: _adminCtx(),
              lojaId: 'loja1',
              onModuleTap: (_, {required planLocked}) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('HOMEUX-9 última categoria restaurada', (tester) async {
    await HomeUxPrefsService.setOpenCategoryId('loja1', 'financeiro');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeModuleAccordion(
            access: _adminCtx(),
            lojaId: 'loja1',
            initialOpenCategoryId: 'financeiro',
            onModuleTap: (_, {required planLocked}) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Contas a pagar'), findsOneWidget);
  });

  test('HOMEUX-10 menu lateral e Home usam registry comum', () {
    final home = HomeModuleRegistry.visibleForHome(_adminCtx());
    final drawer = HomeModuleRegistry.visibleForDrawer(_adminCtx());
    expect(home, isNotEmpty);
    expect(drawer, isNotEmpty);
  });
}
