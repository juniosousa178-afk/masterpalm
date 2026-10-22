import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/widgets/estoque_acoes_lote_sheet.dart';

const viewports = {
  'desktop 1366x657 (navegador)': Size(1366, 657),
  'desktop 1920x929 (navegador)': Size(1920, 929),
  'mobile 390x844': Size(390, 844),
  'mobile 360x740': Size(360, 740),
};

const titulos = {
  EstoqueAcaoLote.adicionarCatalogo: 'Adicionar ao Catálogo',
  EstoqueAcaoLote.removerCatalogo: 'Remover do Catálogo',
  EstoqueAcaoLote.definirDescontoPix: 'Definir desconto no Pix em lote',
  EstoqueAcaoLote.removerDescontoPix: 'Remover desconto no Pix',
  EstoqueAcaoLote.promocao: 'Promoção em lote',
  EstoqueAcaoLote.dividirSemJuros: 'Dividir sem juros em lote',
  EstoqueAcaoLote.alterarCategoria: 'Alterar Categoria em Lote',
  EstoqueAcaoLote.alterarSubcategoria: 'Alterar Subcategoria em Lote',
  EstoqueAcaoLote.mercadoLivre: 'Mercado Livre',
  EstoqueAcaoLote.tiktokShop: 'TikTok Shop',
  EstoqueAcaoLote.shopee: 'Shopee',
  EstoqueAcaoLote.excluir: 'Excluir Produtos',
};

Future<List<EstoqueAcaoLote?>> abrir(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final escolhas = <EstoqueAcaoLote?>[];
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async =>
                escolhas.add(await EstoqueAcoesLoteSheet.mostrar(context, rotuloSelecionados: '1 produto selecionado')),
            child: const Text('Ações'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Ações'));
  await tester.pumpAndSettle();
  return escolhas;
}

/// Whole tile inside the sheet's scroll viewport and the screen, with no scrolling.
bool visivelSemRolar(WidgetTester tester, String titulo, Size size) {
  final tile = tester.getRect(find.widgetWithText(ListTile, titulo));
  final viewport = tester.getRect(find.byType(Scrollable).last);
  return tile.top >= viewport.top && tile.bottom <= viewport.bottom && tile.bottom <= size.height;
}

void main() {
  for (final e in viewports.entries) {
    testWidgets('${e.key}: ações de Pix visíveis sem rolar e "Remover" devolve a ação certa', (tester) async {
      final escolhas = await abrir(tester, e.value);
      expect(tester.takeException(), isNull);
      expect(find.text('1 produto selecionado'), findsOneWidget);
      expect(visivelSemRolar(tester, 'Definir desconto no Pix em lote', e.value), isTrue, reason: 'definir');
      expect(visivelSemRolar(tester, 'Remover desconto no Pix', e.value), isTrue, reason: 'remover');
      await tester.tap(find.widgetWithText(ListTile, 'Remover desconto no Pix'));
      await tester.pumpAndSettle();
      expect(escolhas, [EstoqueAcaoLote.removerDescontoPix]);
      expect(find.byType(EstoqueAcoesLoteSheet), findsNothing);
    });
  }

  testWidgets('todas as 12 ações continuam alcançáveis (rolando) e devolvem o próprio id', (tester) async {
    for (final entry in titulos.entries) {
      final escolhas = await abrir(tester, viewports['mobile 360x740']!);
      final tile = find.widgetWithText(ListTile, entry.value);
      await tester.scrollUntilVisible(tile, 120, scrollable: find.byType(Scrollable).last);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(escolhas, [entry.key], reason: entry.value);
    }
    expect(titulos.keys.toSet(), EstoqueAcaoLote.values.toSet());
  });

  testWidgets('fechar não escolhe nada', (tester) async {
    final escolhas = await abrir(tester, viewports['mobile 390x844']!);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(escolhas, [null]);
  });

  test('EstoqueScreen (rota /estoque) abre esta folha e liga "Remover desconto no Pix" à ação nova', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains("'/estoque': (_) => const EstoqueScreen()"));
    final tela = File('lib/screens/estoque_screen.dart').readAsStringSync();
    final inicio = tela.indexOf('Future<void> _mostrarMenuAcoes() async {');
    expect(inicio, greaterThan(0));
    final menu = tela.substring(inicio, tela.indexOf('\n  }\n', inicio));
    expect(menu, contains('EstoqueAcoesLoteSheet.mostrar('));
    expect(menu, matches(RegExp(r'case EstoqueAcaoLote\.removerDescontoPix:\s+_removerDescontoPixLote\(\);')));
    expect(menu, matches(RegExp(r'case EstoqueAcaoLote\.definirDescontoPix:\s+_descontoPixLote\(\);')));
    expect(tela, contains('onPressed: _publicando ? null : _mostrarMenuAcoes'));
    expect(tela, isNot(contains("titulo: 'Remover desconto no Pix'")), reason: 'single menu source');
  });
}
