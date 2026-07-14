// M3.8 S2-R4 — HOMEPOLISH: favoritos, busca, persistência, registry, layout.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/app_module_definition.dart';
import 'package:master_palm/core/home_module_registry.dart';
import 'package:master_palm/core/home_module_search.dart';
import 'package:master_palm/core/plan_matrix.dart';
import 'package:master_palm/services/home_category_insight_service.dart';
import 'package:master_palm/services/home_ux_prefs_service.dart';
import 'package:master_palm/services/permissao_service.dart';
import 'package:master_palm/widgets/home_global_search_bar.dart';
import 'package:master_palm/widgets/home_module_accordion.dart';

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

  test('HOMEPOLISH-1 favoritos vazios no início', () async {
    expect(await HomeUxPrefsService.getFavorites('loja1'), isEmpty);
  });

  test('HOMEPOLISH-2 adiciona favorito', () async {
    final ids = await HomeUxPrefsService.toggleFavorite('loja1', 'estoque');
    expect(ids, ['estoque']);
  });

  test('HOMEPOLISH-3 remove favorito', () async {
    await HomeUxPrefsService.toggleFavorite('loja1', 'vendas');
    final ids = await HomeUxPrefsService.toggleFavorite('loja1', 'vendas');
    expect(ids, isEmpty);
  });

  test('HOMEPOLISH-4 limite de 6 favoritos', () async {
    for (var i = 0; i < 6; i++) {
      await HomeUxPrefsService.toggleFavorite('loja1', 'm$i');
    }
    expect(
      () => HomeUxPrefsService.toggleFavorite('loja1', 'm6'),
      throwsStateError,
    );
  });

  test('HOMEPOLISH-5 persistência última categoria', () async {
    await HomeUxPrefsService.setOpenCategoryId('loja1', 'marketing');
    expect(await HomeUxPrefsService.getOpenCategoryId('loja1'), 'marketing');
    await HomeUxPrefsService.setOpenCategoryId('loja1', null);
    expect(await HomeUxPrefsService.getOpenCategoryId('loja1'), isNull);
  });

  test('HOMEPOLISH-6 pesquisa estoque', () {
    final r = HomeModuleSearch.search('estoque', access: _adminCtx());
    expect(r.map((e) => e.id), contains('estoque'));
  });

  test('HOMEPOLISH-7 pesquisa campanha', () {
    final r = HomeModuleSearch.search('campanha', access: _adminCtx());
    expect(r.any((e) => e.id.contains('campanha') || e.id.contains('marketing')),
        isTrue);
  });

  test('HOMEPOLISH-8 pesquisa cliente', () {
    final r = HomeModuleSearch.search('cliente', access: _adminCtx());
    expect(r.map((e) => e.id), contains('clientes'));
  });

  test('HOMEPOLISH-9 pesquisa vazia não retorna', () {
    expect(HomeModuleSearch.search('  ', access: _adminCtx()), isEmpty);
  });

  test('HOMEPOLISH-10 badges contagem por categoria', () {
    final counts = HomeModuleRegistry.countVisibleByCategory(_adminCtx());
    expect(counts[HomeModuleCategory.operacoes], greaterThan(0));
    expect(counts[HomeModuleCategory.vendas], greaterThan(0));
    expect(counts[HomeModuleCategory.marketing], greaterThan(0));
  });

  test('HOMEPOLISH-11 registry sem rotas duplicadas', () {
    expect(HomeModuleRegistry.duplicateRoutes(), isEmpty);
  });

  test('HOMEPOLISH-12 registry ids únicos', () {
    final ids = HomeModuleRegistry.all.map((e) => e.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('HOMEPOLISH-13 favoritos não duplicam id na lista', () async {
    await HomeUxPrefsService.setFavorites(
        'loja1', ['vendas', 'vendas', 'estoque']);
    expect(await HomeUxPrefsService.getFavorites('loja1'),
        ['vendas', 'estoque']);
  });

  test('HOMEPOLISH-14 drawer e home compartilham registry', () {
    final home = HomeModuleRegistry.visibleForHome(_adminCtx());
    final drawer = HomeModuleRegistry.visibleForDrawer(_adminCtx());
    for (final m in home.where((e) => e.showInDrawer)) {
      expect(drawer.any((d) => d.id == m.id && d.route == m.route), isTrue);
    }
  });

  test('HOMEPOLISH-15 gate de plano em busca', () {
    final free = _adminCtx(tier: PlanAccessTier.freeLimited);
    final r = HomeModuleSearch.search('carrinho', access: free);
    final cart = r.firstWhere((e) => e.id == 'carrinhos_abandonados');
    expect(HomeModuleRegistry.isPlanLocked(cart, free), isTrue);
  });

  testWidgets('HOMEPOLISH-16 categorias iniciam fechadas', (tester) async {
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

  testWidgets('HOMEPOLISH-17 abre categoria com badge contagem', (tester) async {
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
    expect(find.textContaining('Operações ('), findsOneWidget);
    await tester.tap(find.textContaining('Operações ('));
    await tester.pumpAndSettle();
    expect(find.text('Fornecedores'), findsWidgets);
  });

  testWidgets('HOMEPOLISH-18 favorito via estrela no card', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeModuleAccordion(
            access: _adminCtx(),
            lojaId: 'loja1',
            excludeFavoriteIdsFromAccordion: false,
            onModuleTap: (_, {required planLocked}) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Operações ('));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.star_border).first);
    await tester.pumpAndSettle();
    expect(await HomeUxPrefsService.getFavorites('loja1'), isNotEmpty);
  });

  testWidgets('HOMEPOLISH-19 pesquisa global abre resultado', (tester) async {
    AppModuleDefinition? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeGlobalSearchBar(
            access: _adminCtx(),
            onOpenModule: (m, {required planLocked}) {
              opened = m;
            },
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'estoque');
    await tester.pumpAndSettle();
    expect(find.text('Estoque'), findsWidgets);
    await tester.tap(find.text('Estoque').last);
    await tester.pumpAndSettle();
    expect(opened?.id, 'estoque');
  });

  testWidgets('HOMEPOLISH-20 layout mobile sem overflow', (tester) async {
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
            child: Column(
              children: [
                HomeGlobalSearchBar(
                  access: _adminCtx(),
                  onOpenModule: (_, {required planLocked}) {},
                ),
                Expanded(
                  child: HomeModuleAccordion(
                    access: _adminCtx(),
                    lojaId: 'loja1',
                    onModuleTap: (_, {required planLocked}) {},
                  ),
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
