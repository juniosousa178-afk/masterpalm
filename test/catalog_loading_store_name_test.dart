// Loading inicial do catálogo público: mostra o "Nome da loja" de Identidade & Contato
// (config/config.nome) e nunca o slug da URL.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/public_catalog/catalog_helpers.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_early_shell_view.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_unified_loading.dart';

Future<void> _pumpShell(
  WidgetTester tester, {
  Key? key,
  String? storeName,
}) async {
  await tester.pumpWidget(
    MaterialApp(home: CatalogEarlyShellView(key: key, storeName: storeName)),
  );
  await tester.pump();
}

List<String> _shownTexts(WidgetTester tester) =>
    tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').toList();

void _expectNoSlugText(WidgetTester tester, String slug) {
  for (final s in _shownTexts(tester)) {
    final normalized = s.toLowerCase().replaceAll(' ', '-');
    expect(normalized.contains(slug.toLowerCase()), isFalse,
        reason: 'slug "$slug" exibido: $s');
  }
}

Map<String, String> _identity(String storeId, String name) =>
    <String, String>{'storeId': storeId, 'name': name};

String _catalogFirstPaintBlock(String html) {
  final start = html.indexOf('if (isCatalogFirstPaint()) {');
  final end = html.indexOf('} else {', start);
  expect(start, greaterThan(0));
  expect(end, greaterThan(start));
  return html.substring(start, end);
}

String _jsFunction(String html, String name) {
  final start = html.indexOf('function $name(');
  expect(start, greaterThan(0), reason: 'function $name ausente');
  final end = html.indexOf('\n      }\n', start);
  expect(end, greaterThan(start));
  return html.substring(start, end);
}

void main() {
  group('nome da loja pré-carregado para o loading', () {
    test('MASTERPALM: slug masterpalm26, nome cadastrado masterpalm -> masterpalm', () {
      final name = catalogPreloadedStoreNameFor(
        'masterpalm26',
        _identity('masterpalm26', 'masterpalm'),
      );
      expect(name, 'masterpalm');
      expect(name, isNot('Masterpalm26'));
    });

    test('NATHY: nome cadastrado exibido exatamente como salvo', () {
      expect(
        catalogPreloadedStoreNameFor(
          'nathy-pratas-e-folheados',
          _identity('nathy-pratas-e-folheados', 'Nathy Pratas e Folheados'),
        ),
        'Nathy Pratas e Folheados',
      );
      expect(
        catalogPreloadedStoreNameFor(
          'nathy-pratas-e-folheados',
          _identity('nathy-pratas-e-folheados', 'NATHY Pratas e Folheados'),
        ),
        'NATHY Pratas e Folheados',
      );
    });

    test('nome ainda não carregado -> sem nome (loading neutro)', () {
      expect(catalogPreloadedStoreNameFor('masterpalm26', null), isNull);
      expect(
        catalogPreloadedStoreNameFor('masterpalm26', _identity('masterpalm26', '  ')),
        isNull,
      );
    });

    test('loja A -> loja B: identidade de A nunca vale para B', () {
      final identityA = _identity('masterpalm26', 'masterpalm');
      expect(
        catalogPreloadedStoreNameFor('nathy-pratas-e-folheados', identityA),
        isNull,
      );
      expect(catalogPreloadedStoreNameFor('', identityA), isNull);
    });

    test('alterar o nome: mesmo slug, nome visual novo', () {
      const slug = 'masterpalm26';
      expect(catalogPreloadedStoreNameFor(slug, _identity(slug, 'masterpalm')), 'masterpalm');
      expect(
        catalogPreloadedStoreNameFor(slug, _identity(slug, 'MasterPalm Joias')),
        'MasterPalm Joias',
      );
    });
  });

  group('nome canônico depois da config (mesmo campo do cabeçalho)', () {
    test('ordem nome -> nomeLoja -> nome_loja -> name', () {
      expect(catalogHeaderStoreNameFromCfg({'nome': 'masterpalm', 'name': 'Minha Loja'}), 'masterpalm');
      expect(catalogHeaderStoreNameFromCfg({'nomeLoja': 'Loja X'}), 'Loja X');
      expect(catalogHeaderStoreNameFromCfg({'nome_loja': 'Loja Y'}), 'Loja Y');
      expect(catalogHeaderStoreNameFromCfg({'name': '  Loja Z  '}), 'Loja Z');
    });

    test('nome vazio -> fallback atual "Minha Loja"', () {
      expect(catalogHeaderStoreNameFromCfg({}) ?? 'Minha Loja', 'Minha Loja');
      expect(catalogHeaderStoreNameFromCfg({'nome': '   '}) ?? 'Minha Loja', 'Minha Loja');
      expect(catalogHeaderStoreNameFromCfg({'nome': 'Minha Loja'}) ?? 'Minha Loja', 'Minha Loja');
    });
  });

  group('título da aba', () {
    test('Catálogo | [Nome da loja]', () {
      expect(catalogBrowserTitle('masterpalm'), 'Catálogo | masterpalm');
      expect(catalogBrowserTitle('NATHY Pratas e Folheados'), 'Catálogo | NATHY Pratas e Folheados');
    });

    test('sem nome -> título padrão (nunca o slug)', () {
      expect(catalogBrowserTitle(null), kCatalogDefaultBrowserTitle);
      expect(catalogBrowserTitle('  '), kCatalogDefaultBrowserTitle);
    });
  });

  group('shell de loading (web) enquanto a config carrega', () {
    testWidgets('MASTERPALM: mostra masterpalm, nunca Masterpalm26', (tester) async {
      await _pumpShell(tester, storeName: 'masterpalm');
      expect(find.text('masterpalm'), findsOneWidget);
      expect(find.text(CatalogUnifiedLoadingCopy.title), findsOneWidget);
      expect(find.text(CatalogUnifiedLoadingCopy.subtitle), findsOneWidget);
      expect(find.text('Masterpalm26'), findsNothing);
      _expectNoSlugText(tester, 'masterpalm26');
    });

    testWidgets('NATHY: mostra o nome salvo, nunca o slug', (tester) async {
      await _pumpShell(tester, storeName: 'Nathy Pratas e Folheados');
      expect(find.text('Nathy Pratas e Folheados'), findsOneWidget);
      expect(find.text('Nathy Pratas E Folheados'), findsNothing);
      expect(find.text('nathy-pratas-e-folheados'), findsNothing);
      expect(find.text('Nathy-pratas-e-folheados'), findsNothing);
    });

    testWidgets('nome ainda não carregado: só a copy neutra', (tester) async {
      await _pumpShell(tester);
      expect(_shownTexts(tester), [
        CatalogUnifiedLoadingCopy.title,
        CatalogUnifiedLoadingCopy.subtitle,
      ]);
    });

    testWidgets('loja A -> loja B: nome de A nunca aparece na loja B', (tester) async {
      await _pumpShell(tester, key: const ValueKey('loja-a'), storeName: 'masterpalm');
      expect(find.text('masterpalm'), findsOneWidget);
      final nameForB = catalogPreloadedStoreNameFor(
        'nathy-pratas-e-folheados',
        _identity('masterpalm26', 'masterpalm'),
      );
      await _pumpShell(tester, key: const ValueKey('loja-b'), storeName: nameForB);
      expect(find.text('masterpalm'), findsNothing);
      expect(_shownTexts(tester), [
        CatalogUnifiedLoadingCopy.title,
        CatalogUnifiedLoadingCopy.subtitle,
      ]);
    });

    testWidgets('nome chega depois: o shell passa a mostrá-lo', (tester) async {
      await _pumpShell(tester);
      expect(find.text('masterpalm'), findsNothing);
      await _pumpShell(tester, storeName: 'masterpalm');
      expect(find.text('masterpalm'), findsOneWidget);
    });

    testWidgets('onFirstFrame continua a disparar o handoff do loader HTML', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(home: CatalogEarlyShellView(onFirstFrame: () => calls++)),
      );
      await tester.pump();
      expect(calls, 1);
    });
  });

  group('web/index.html — loader inicial', () {
    final html = File('web/index.html').readAsStringSync();

    test('primeira pintura do catálogo: neutra, depois o nome publicado', () {
      final block = _catalogFirstPaintBlock(html);
      expect(block.contains('slugToStoreName'), isFalse);
      expect(block.contains('getSlugFromLocation'), isFalse);
      expect(block.contains("logoEl.style.display = 'none'"), isTrue);
      expect(block.contains('preloadCatalogStoreName(logoEl);'), isTrue);
      expect(block.contains("'Preparando sua loja...'"), isTrue);
      expect(block.contains("'Estamos carregando o catálogo para você.'"), isTrue);
    });

    test('lê só os campos de nome de lojas/{id}/config/config', () {
      final fn = _jsFunction(html, 'preloadCatalogStoreName');
      expect(fn.contains("/documents/lojas/' +"), isTrue);
      expect(fn.contains("storeId + '/config/config'"), isTrue);
      expect(
        fn.contains(
          '?mask.fieldPaths=nome&mask.fieldPaths=nomeLoja&mask.fieldPaths=nome_loja&mask.fieldPaths=name',
        ),
        isTrue,
      );
      expect(fn.contains('produtos'), isFalse);
      expect(fn.contains('localStorage'), isFalse, reason: 'sem cache persistente slug -> nome');
      expect(fn.contains('slugToStoreName'), isFalse);
    });

    test('identidade presa ao id da loja da URL atual', () {
      final fn = _jsFunction(html, 'preloadCatalogStoreName');
      expect(fn.contains('catalogStoreIdFromLojaPath() !== storeId'), isTrue);
      expect(fn.contains('window.__mpCatalogStoreIdentity = { storeId: storeId, name: name };'), isTrue);
    });

    test('mesma ordem de campos e fallback do cabeçalho', () {
      final fn = _jsFunction(html, 'storeNameFromConfigFields');
      expect(fn.contains("['nome', 'nomeLoja', 'nome_loja', 'name']"), isTrue);
      expect(fn.contains("=== 'minha loja'"), isTrue);
      expect(fn.contains("return 'Minha Loja';"), isTrue);
    });

    test('id da loja só a partir de /loja/{id} e com formato de slug', () {
      final fn = _jsFunction(html, 'catalogStoreIdFromLojaPath');
      expect(fn.contains("p.indexOf('/loja/') !== 0"), isTrue);
      expect(fn.contains(r'/^[A-Za-z0-9_-]{3,128}$/'), isTrue);
      expect(fn.contains("'minha-loja'"), isTrue);
    });

    test('slug, identificação da loja e URL canônica continuam intactos', () {
      expect(html.contains('function getSlugFromLocation()'), isTrue);
      expect(
        html.contains("if (parts.length >= 2 && parts[0] === 'loja') return parts[1] || '';"),
        isTrue,
      );
      expect(html.contains('function getCanonicalCatalogUrl()'), isTrue);
      expect(html.contains('function isPublicCatalogUrl()'), isTrue);
    });

    test('loader do app administrativo continua com a marca MasterPalm', () {
      final adminStart =
          html.indexOf('} else {', html.indexOf('if (isCatalogFirstPaint()) {'));
      final admin = html.substring(adminStart, adminStart + 300);
      expect(admin.contains("logoEl.textContent = 'MasterPalm';"), isTrue);
    });
  });
}
