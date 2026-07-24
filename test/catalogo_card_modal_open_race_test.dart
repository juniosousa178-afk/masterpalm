// M2.3-R5 — modal aberto durante atualização da grade + corrida de callback.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_product_card.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_product_selection_sheet.dart';
import 'package:master_palm/services/catalog_cart_item_snapshot.dart';

const _nomeA = 'Colar Coração';
const _nomeB = 'Colar Gota';
const _tamA = 'coracao-rosa';
const _tamB = '45cm-v12';
const _lojaId = 'loja-modal-r5';

Map<String, dynamic> _produtoA() => {
      'id': 'produto-a',
      'nome': _nomeA,
      'preco': 99.90,
      'slug': 'a',
      'estoquePorTamanho': {_tamA: 3},
      'imageUrl': '',
      'imagens': <String>[],
    };

Map<String, dynamic> _produtoB() => {
      'id': 'produto-b',
      'nome': _nomeB,
      'preco': 79.90,
      'slug': 'b',
      'estoquePorTamanho': {_tamB: 5},
      'imageUrl': '',
      'imagens': <String>[],
    };

Future<void> _pumpIgnoreImages(WidgetTester tester) async {
  await tester.pump();
  while (tester.takeException() != null) {}
}

Widget _card(
  Map<String, dynamic> p,
  bool Function(Map<String, dynamic>) onAdd,
) {
  return CatalogProductCard(
    id: p['id'] as String,
    name: p['nome'] as String,
    price: (p['preco'] as num).toDouble(),
    imageUrl: '',
    imagens: const [],
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

  testWidgets('sheet aberto de A permanece A após grade trocar para B', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cart = <Map<String, dynamic>>[];
    var current = _produtoA();
    StateSetter? swapGrade;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              swapGrade = setState;
              return Column(
                children: [
                  TextButton(
                    onPressed: () => setState(() => current = _produtoB()),
                    child: const Text('SWAP_GRADE'),
                  ),
                  Expanded(
                    child: _card(current, (item) {
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
    await tester.pumpAndSettle();

    await tester.tap(find.text('Comprar').first);
    await _pumpIgnoreImages(tester);
    await tester.pump(const Duration(milliseconds: 400));

    final sheet = tester.widget<CatalogProductSelectionSheet>(
      find.byType(CatalogProductSelectionSheet),
    );
    expect(sheet.productId, 'produto-a');
    expect(sheet.name, _nomeA);

    swapGrade!(() => current = _produtoB());
    await tester.pumpAndSettle();

    final cardAfter = tester.widget<CatalogProductCard>(find.byType(CatalogProductCard));
    expect(cardAfter.id, 'produto-b');

    expect(
      tester.widget<CatalogProductSelectionSheet>(
        find.byType(CatalogProductSelectionSheet),
      ).productId,
      'produto-a',
    );

    await tester.tap(find.text(_tamA));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar ao carrinho'));
    await tester.pumpAndSettle();

    expect(cart.length, 1);
    final line = cart.single;
    expect(line['productId'] ?? line['id'], 'produto-a');
    expect(line['nomeSnapshot'] ?? line['nome'], _nomeA);
    expect(line['tamanho'], _tamA);
    expect((line['preco'] as num).toDouble(), closeTo(99.90, 0.01));
  });

  testWidgets('callback tardio usa mapa capturado de A, não índice atual B',
      (tester) async {
    final gate = Completer<void>();
    Map<String, dynamic>? captured;
    var current = _produtoA();

    Future<void> onAddDelayed(Map<String, dynamic> item) async {
      captured = Map<String, dynamic>.from(item);
      await gate.future;
      final copy = Map<String, dynamic>.from(captured!);
      copy['quantidade'] = 1;
      freezeCatalogCartLineSnapshotOnAdd(copy);
      return;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              children: [
                TextButton(
                  onPressed: () => setState(() => current = _produtoB()),
                  child: const Text('SWAP'),
                ),
                CatalogProductVariationPickHarness(
                  product: current,
                  onAddDelayed: onAddDelayed,
                ),
              ],
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('COMMIT_A'));
    await tester.pump();
    await tester.tap(find.text('SWAP'));
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();

    expect(captured!['id'], 'produto-a');
    expect(captured!['nome'], _nomeA);
  });
}

/// Harness mínimo que simula card/sheet capturando item no clique.
class CatalogProductVariationPickHarness extends StatelessWidget {
  const CatalogProductVariationPickHarness({
    super.key,
    required this.product,
    required this.onAddDelayed,
  });

  final Map<String, dynamic> product;
  final Future<void> Function(Map<String, dynamic> item) onAddDelayed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () {
        onAddDelayed({
          'id': product['id'],
          'produtosId': product['id'],
          'nome': product['nome'],
          'preco': product['preco'],
          'tamanho': product['id'] == 'produto-a' ? _tamA : _tamB,
          'cor': '',
        });
      },
      child: const Text('COMMIT_A'),
    );
  }
}
