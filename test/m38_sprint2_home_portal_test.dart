// M3.8 S2-R5 — HOMEPORTAL: home executiva + cards + telas por módulo.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/app_module_definition.dart';
import 'package:master_palm/core/home_module_registry.dart';
import 'package:master_palm/core/plan_matrix.dart';
import 'package:master_palm/screens/home_portal_category_screen.dart';
import 'package:master_palm/services/permissao_service.dart';
import 'package:master_palm/widgets/dashboard_home_cards.dart';
import 'package:master_palm/widgets/home_portal_grid.dart';
import 'package:master_palm/widgets/home_quick_actions_row.dart';

HomeModuleAccessContext _adminCtx({
  PlanAccessTier tier = PlanAccessTier.lifetime,
}) {
  return HomeModuleAccessContext(
    tipoUsuario: 'admin',
    permissoes: {
      for (final k in PermissaoService.todasAsChaves) k: true,
    },
    planTier: tier,
    applyPlanGate: true,
  );
}

void main() {
  test('HOMEPORTAL-1 registry ids únicos', () {
    final ids = HomeModuleRegistry.all.map((e) => e.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('HOMEPORTAL-2 registry sem rotas duplicadas', () {
    expect(HomeModuleRegistry.duplicateRoutes(), isEmpty);
  });

  test('HOMEPORTAL-3 seis categorias ordenadas', () {
    expect(HomeModuleRegistry.categoriesOrdered.map((c) => c.id).toList(), [
      'operacoes',
      'vendas',
      'clientes',
      'marketing',
      'financeiro',
      'configuracoes',
    ]);
  });

  test('HOMEPORTAL-4 cada categoria tem descrição de portal', () {
    for (final c in HomeModuleRegistry.categoriesOrdered) {
      expect(c.portalDescription.trim(), isNotEmpty);
    }
  });

  test('HOMEPORTAL-5 catálogo interno é comercial (vendas)', () {
    final m = HomeModuleRegistry.byId('catalogo_interno')!;
    expect(m.route, '/catalogo_interno');
    expect(m.category, HomeModuleCategory.vendas);
    expect(m.permissionKey, 'vendas');
  });

  test('HOMEPORTAL-6 catálogo da loja fica em Vendas (atalho Home)', () {
    final m = HomeModuleRegistry.byId('catalogo_loja')!;
    expect(m.category, HomeModuleCategory.vendas);
    expect(m.route, '/catalogo_loja');
  });

  test('HOMEPORTAL-7 vendas / estoque / carrinhos no registry', () {
    expect(HomeModuleRegistry.byId('vendas')!.route, '/vendas');
    expect(HomeModuleRegistry.byId('estoque')!.route, '/estoque');
    expect(
      HomeModuleRegistry.byId('carrinhos_abandonados')!.route,
      '/carrinhos_abandonados',
    );
  });

  test('HOMEPORTAL-8 contagens por categoria > 0 para admin', () {
    final counts = HomeModuleRegistry.countVisibleByCategory(_adminCtx());
    for (final c in HomeModuleRegistry.categoriesOrdered) {
      expect(counts[c] ?? 0, greaterThan(0), reason: c.title);
    }
  });

  test('HOMEPORTAL-9 drawer e home compartilham registry', () {
    final home = HomeModuleRegistry.visibleForHome(_adminCtx());
    final drawer = HomeModuleRegistry.visibleForDrawer(_adminCtx());
    for (final m in home.where((e) => e.showInDrawer)) {
      expect(drawer.any((d) => d.id == m.id), isTrue);
    }
  });

  test('HOMEPORTAL-10 marketing inclui campanhas (sem catálogo da loja)', () {
    final mkt = HomeModuleRegistry.byCategory(HomeModuleCategory.marketing)
        .map((e) => e.id);
    expect(mkt, contains('campanhas_dashboard'));
    expect(mkt, isNot(contains('catalogo_loja')));
  });

  test('HOMEPORTAL-11 operações inclui estoque (sem catálogo interno)', () {
    final ops = HomeModuleRegistry.byCategory(HomeModuleCategory.operacoes)
        .map((e) => e.id);
    expect(ops, containsAll(['estoque', 'fornecedores']));
    expect(ops, isNot(contains('catalogo_interno')));
  });

  test('HOMEPORTAL-11b vendas inclui catálogo interno e da loja', () {
    final vendas = HomeModuleRegistry.byCategory(HomeModuleCategory.vendas)
        .map((e) => e.id);
    expect(
      vendas,
      containsAll(['vendas', 'catalogo_interno', 'catalogo_loja']),
    );
  });

  test('HOMEPORTAL-12 gate de plano em carrinhos', () {
    final free = _adminCtx(tier: PlanAccessTier.freeLimited);
    final cart = HomeModuleRegistry.byId('carrinhos_abandonados')!;
    expect(HomeModuleRegistry.isPlanLocked(cart, free), isTrue);
  });

  testWidgets('HOMEPORTAL-13 grid mostra cards de categoria', (tester) async {
    HomeModuleCategory? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomePortalGrid(
            access: _adminCtx(),
            onOpenCategory: (c) => opened = c,
          ),
        ),
      ),
    );
    expect(find.text('Operações'), findsOneWidget);
    expect(find.text('Vendas'), findsOneWidget);
    expect(find.text('Marketing'), findsOneWidget);
    await tester.tap(find.text('Operações'));
    await tester.pump();
    expect(opened, HomeModuleCategory.operacoes);
  });

  testWidgets('HOMEPORTAL-14 card mostra quantidade de funcionalidades',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomePortalGrid(
            access: _adminCtx(),
            onOpenCategory: (_) {},
          ),
        ),
      ),
    );
    expect(find.textContaining('funcionalidade'), findsWidgets);
  });

  testWidgets('HOMEPORTAL-15 quick actions Vendas Estoque Clientes Catálogo',
      (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeQuickActionsRow(
            access: _adminCtx(),
            onModuleTap: (m, {required planLocked}) {
              opened.add(m.id);
            },
          ),
        ),
      ),
    );
    expect(find.text('Vendas'), findsOneWidget);
    expect(find.text('Estoque'), findsOneWidget);
    expect(find.text('Clientes'), findsOneWidget);
    expect(find.text('Catálogo'), findsOneWidget);
    expect(find.text('Carrinhos'), findsNothing);
    await tester.tap(find.text('Vendas'));
    await tester.pump();
    expect(opened, ['vendas']);
  });

  testWidgets('HOMEPORTAL-16 tela portal Operações lista estoque',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomePortalCategoryScreen(
          category: HomeModuleCategory.operacoes,
          access: _adminCtx(),
          onOpenModule: (_, {required planLocked}) {},
        ),
      ),
    );
    expect(find.text('Estoque'), findsWidgets);
    expect(find.text('Fornecedores'), findsOneWidget);
    expect(find.text('Catálogo interno'), findsNothing);
  });

  testWidgets('HOMEPORTAL-17 tela portal Vendas lista catálogos',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomePortalCategoryScreen(
          category: HomeModuleCategory.vendas,
          access: _adminCtx(),
          onOpenModule: (_, {required planLocked}) {},
        ),
      ),
    );
    expect(find.text('Catálogo interno'), findsOneWidget);
    expect(find.text('Catálogo da loja'), findsOneWidget);
    expect(find.text('Campanhas'), findsNothing);
  });

  testWidgets('HOMEPORTAL-18 tap no atalho da tela portal dispara callback',
      (tester) async {
    String? openedId;
    await tester.pumpWidget(
      MaterialApp(
        home: HomePortalCategoryScreen(
          category: HomeModuleCategory.vendas,
          access: _adminCtx(),
          onOpenModule: (m, {required planLocked}) {
            openedId = m.id;
          },
        ),
      ),
    );
    await tester.tap(find.text('Pré-pedidos'));
    await tester.pump();
    expect(openedId, 'pre_pedidos');
  });

  testWidgets('HOMEPORTAL-19 KPIs DashboardHomeCards widget existe',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DashboardHomeCards(lojaId: ''),
        ),
      ),
    );
    await tester.pump();
    // lojaId vazio → shrink (sem crash).
    expect(tester.takeException(), isNull);
  });

  testWidgets('HOMEPORTAL-20 layout mobile do grid sem overflow',
      (tester) async {
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
            child: ListView(
              children: [
                HomeQuickActionsRow(
                  access: _adminCtx(),
                  onModuleTap: (_, {required planLocked}) {},
                ),
                HomePortalGrid(
                  access: _adminCtx(),
                  onOpenCategory: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
