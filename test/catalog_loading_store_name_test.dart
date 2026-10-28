// Loading inicial do catálogo público: nunca exibe o slug da URL como nome da loja.
// O nome comercial vem da config da própria loja (mesmo campo do cabeçalho).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/public_catalog/catalog_helpers.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_early_shell_view.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_unified_loading.dart';

Future<void> _pumpShell(WidgetTester tester, {Key? key}) async {
  await tester.pumpWidget(MaterialApp(home: CatalogEarlyShellView(key: key)));
  await tester.pump();
}

void _expectNoSlugText(WidgetTester tester, String slug) {
  final shown = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => (t.data ?? '').toLowerCase().replaceAll(' ', '-'))
      .toList();
  for (final s in shown) {
    expect(s.contains(slug.toLowerCase()), isFalse, reason: 'slug "$slug" exibido: $s');
  }
}

String _catalogFirstPaintBlock(String html) {
  final start = html.indexOf('if (isCatalogFirstPaint()) {');
  final end = html.indexOf('} else {', start);
  expect(start, greaterThan(0));
  expect(end, greaterThan(start));
  return html.substring(start, end);
}

void main() {
  group('nome canônico (mesmo campo do cabeçalho do catálogo)', () {
    test('slug masterpalm26, nome cadastrado MasterPalm -> MasterPalm', () {
      expect(catalogHeaderStoreNameFromCfg({'nome': 'MasterPalm'}), 'MasterPalm');
      expect(catalogHeaderStoreNameFromCfg({'nomeLoja': 'MasterPalm'}), 'MasterPalm');
      expect(catalogHeaderStoreNameFromCfg({'nome': 'MasterPalm'}), isNot('Masterpalm26'));
    });

    test('nome com espaços preservado por completo', () {
      expect(
        catalogHeaderStoreNameFromCfg({'nomeLoja': 'Nathy Pratas e Folheados'}),
        'Nathy Pratas e Folheados',
      );
      expect(
        catalogHeaderStoreNameFromCfg({'name': '  Nathy Pratas e Folheados  '}),
        'Nathy Pratas e Folheados',
      );
    });

    test('nome ausente ou placeholder -> sem nome (cabeçalho usa o fallback existente)', () {
      expect(catalogHeaderStoreNameFromCfg({}), isNull);
      expect(catalogHeaderStoreNameFromCfg({'nome': '   '}), isNull);
      expect(catalogHeaderStoreNameFromCfg({'nome': 'Minha Loja'}), isNull);
    });

    test('nome vem só da config da loja passada (sem estado entre lojas)', () {
      expect(catalogHeaderStoreNameFromCfg({'nome': 'Loja A'}), 'Loja A');
      expect(catalogHeaderStoreNameFromCfg({'nome': 'Loja B'}), 'Loja B');
      expect(catalogHeaderStoreNameFromCfg({}), isNull, reason: 'nunca herda o nome anterior');
    });
  });

  group('shell de loading (web) enquanto a config carrega', () {
    testWidgets('não mostra o slug técnico; mostra só a copy neutra', (tester) async {
      await _pumpShell(tester);
      expect(find.text(CatalogUnifiedLoadingCopy.title), findsOneWidget);
      expect(find.text(CatalogUnifiedLoadingCopy.subtitle), findsOneWidget);
      expect(find.text('Masterpalm26'), findsNothing);
      expect(find.text('Nathy Pratas E Folheados'), findsNothing);
      _expectNoSlugText(tester, 'masterpalm26');
      _expectNoSlugText(tester, 'nathy-pratas-e-folheados');
      expect(find.byType(Text), findsNWidgets(2), reason: 'nenhum nome de loja no loading');
    });

    testWidgets('troca entre duas lojas nunca mostra o nome da loja anterior', (tester) async {
      await _pumpShell(tester, key: const ValueKey('loja-a'));
      final first = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();
      await _pumpShell(tester, key: const ValueKey('loja-b'));
      final second = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();
      expect(first, [CatalogUnifiedLoadingCopy.title, CatalogUnifiedLoadingCopy.subtitle]);
      expect(second, first);
    });

    testWidgets('onFirstFrame continua a disparar o handoff do loader HTML', (tester) async {
      var calls = 0;
      await tester.pumpWidget(MaterialApp(home: CatalogEarlyShellView(onFirstFrame: () => calls++)));
      await tester.pump();
      expect(calls, 1);
    });
  });

  testWidgets('loading unificado mostra o nome quando já conhecido da mesma loja', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CatalogUnifiedLoadingView(nomeLoja: 'MasterPalm'))));
    await tester.pump();
    expect(find.text('MasterPalm'), findsOneWidget);
  });

  group('web/index.html — loader inicial', () {
    final html = File('web/index.html').readAsStringSync();

    test('primeira pintura do catálogo não converte o slug em nome', () {
      final block = _catalogFirstPaintBlock(html);
      expect(block.contains('slugToStoreName'), isFalse);
      expect(block.contains('getSlugFromLocation'), isFalse);
      expect(block.contains("logoEl.style.display = 'none'"), isTrue);
      expect(block.contains("'Preparando sua loja...'"), isTrue);
      expect(block.contains("'Estamos carregando o catálogo para você.'"), isTrue);
    });

    test('slug, identificação da loja e URL canônica continuam intactos', () {
      expect(html.contains('function getSlugFromLocation()'), isTrue);
      expect(html.contains("if (parts.length >= 2 && parts[0] === 'loja') return parts[1] || '';"), isTrue);
      expect(html.contains('function getCanonicalCatalogUrl()'), isTrue);
      expect(html.contains('function isPublicCatalogUrl()'), isTrue);
    });

    test('loader do app administrativo continua com a marca MasterPalm', () {
      final adminStart = html.indexOf('} else {', html.indexOf('if (isCatalogFirstPaint()) {'));
      final admin = html.substring(adminStart, adminStart + 300);
      expect(admin.contains("logoEl.textContent = 'MasterPalm';"), isTrue);
    });
  });
}
