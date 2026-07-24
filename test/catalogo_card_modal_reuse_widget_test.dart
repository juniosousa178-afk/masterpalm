// M2.3-R4 — reuso real card/modal na grade (seção 13).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/public_catalog/catalog_cart_identity_trace.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_product_card.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_product_selection_sheet.dart';
import 'package:master_palm/services/catalog_cart_item_snapshot.dart';

const _nomeA = 'Colar Coração Cravejado Rosa';
const _nomeB = 'Colar Ponto de Luz Gota 45cm';
const _tamA = 'coracao-rosa';
const _tamB = '45cm-v12';
const _lojaId = 'loja-card-r4';

Map<String, dynamic> _produtoA() => {
      'id': 'produto-a',
      'nome': _nomeA,
      'preco': 99.90,
      'slug': 'colar-a',
      'estoquePorTamanho': {_tamA: 3},
      'imageUrl': '',
      'imagens': <String>[],
    };

Map<String, dynamic> _produtoB() => {
      'id': 'produto-b',
      'nome': _nomeB,
      'preco': 79.90,
      'slug': 'colar-b',
      'estoquePorTamanho': {_tamB: 5},
      'imageUrl': '',
      'imagens': <String>[],
    };

Future<void> _pumpIgnoreImageErrors(WidgetTester tester, [Duration? duration]) async {
  await tester.pump(duration);
  while (tester.takeException() != null) {}
}

Widget _cardFrom(
  Map<String, dynamic> p,
  bool Function(Map<String, dynamic>) onAdd,
) {
  return CatalogProductCard(
    id: p['id'] as String,
    name: p['nome'] as String,
    price: (p['preco'] as num).toDouble(),
    imageUrl: p['imageUrl'] as String,
    imagens: List<String>.from(p['imagens'] as List),
    descricao: '',
    slug: p['slug'] as String,
    estoquePorTamanho: Map<String, int>.from(p['estoquePorTamanho'] as Map),
    estoquePorCor: const {},
    onAdd: onAdd,
    lojaId: _lojaId,
    onAbrirCarrinho: () {},
    produtoCatalogoMap: p,
    quantidade: 3,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('grade real: A no índice 0, sheet, filtro, B no índice 0, add B',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cart = <Map<String, dynamic>>[];
    final traces = <CatalogCartIdentityTraceEvent>[];
    catalogCartIdentityTraceReset();
    catalogCartIdentityTraceSubscribe(traces.add);
    var current = _produtoA();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                children: [
                  TextButton(
                    onPressed: () => setState(() => current = _produtoB()),
                    child: const Text('FILTER_REORDER'),
                  ),
                  Expanded(
                    child: _cardFrom(current, (item) {
                      final copy = Map<String, dynamic>.from(item);
                      copy['quantidade'] = 1;
                      freezeCatalogCartLineSnapshotOnAdd(copy);
                      cart.add(copy);
                      return true;
                    }),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await _pumpIgnoreImageErrors(tester);
    await tester.pumpAndSettle();

    final cardFinder = find.byType(CatalogProductCard);
    expect(cardFinder, findsOneWidget);
    final cardState = tester.state(cardFinder);
    expect(cardState.widget.runtimeType.toString(), 'CatalogProductCard');

    await tester.tap(find.text('Comprar').first);
    await _pumpIgnoreImageErrors(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await _pumpIgnoreImageErrors(tester);

    expect(find.byType(CatalogProductSelectionSheet), findsOneWidget);
    await tester.tap(find.text(_tamA));
    await tester.pumpAndSettle();

    final sheetCtx = tester.element(find.byType(CatalogProductSelectionSheet));
    Navigator.of(sheetCtx).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('FILTER_REORDER'));
    await tester.pumpAndSettle();

    final cardAfter = tester.widget<CatalogProductCard>(cardFinder);
    expect(cardAfter.id, 'produto-b');
    expect(cardAfter.name, _nomeB);

    await tester.tap(find.text('Comprar').first);
    await _pumpIgnoreImageErrors(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await _pumpIgnoreImageErrors(tester);
    await tester.tap(find.text(_tamB));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar ao carrinho'));
    await tester.pumpAndSettle();

    expect(cart.length, 1);
    final line = cart.single;
    expect(line['productId'] ?? line['id'], 'produto-b');
    expect(line['nomeSnapshot'] ?? line['nome'], _nomeB);
    expect(line['tamanho'], _tamB);
    expect(line['nome'], isNot(contains('Coração')));

    expect(
      traces.any((t) => t.productId == 'produto-b'),
      isTrue,
      reason: 'trace deve registrar productId de B',
    );
  });
}
