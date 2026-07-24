// M2.3-R6.1 — callbacks congelados na abertura do modal.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_product_card.dart';
import 'package:master_palm/services/catalog_cart_item_snapshot.dart';

const _lojaId = 'loja-r61-callback';
const _tamA = 'variacao-a';

Map<String, dynamic> _produtoA() => {
      'id': 'produto-a',
      'nome': 'Colar Coração Cravejado Rosa',
      'preco': 99.90,
      'slug': 'a',
      'estoquePorTamanho': {_tamA: 2},
      'imageUrl': '',
      'imagens': <String>[],
    };

Map<String, dynamic> _produtoB() => {
      'id': 'produto-b',
      'nome': 'Colar Ponto de Luz Gota 45cm',
      'preco': 79.90,
      'slug': 'b',
      'estoquePorTamanho': {'variacao-b': 3},
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
    onAdd: onAdd,
    lojaId: _lojaId,
    onAbrirCarrinho: () {},
    produtoCatalogoMap: p,
    quantidade: 3,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('callbackA recebe linha de A após card virar B', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var callbackInvoked = 'none';
    Map<String, dynamic>? lineReceived;
    var current = _produtoA();
    void Function(void Function())? swapGrade;

    bool callbackA(Map<String, dynamic> item) {
      callbackInvoked = 'A';
      lineReceived = Map<String, dynamic>.from(item);
      return true;
    }

    bool callbackB(Map<String, dynamic> item) {
      callbackInvoked = 'B';
      return true;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              swapGrade = setState;
              return Column(
                children: [
                  Expanded(
                    child: _card(
                      current,
                      current['id'] == 'produto-a' ? callbackA : callbackB,
                    ),
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

    swapGrade!(() => current = _produtoB());
    await tester.pumpAndSettle();

    await tester.tap(find.text(_tamA));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar ao carrinho'));
    await tester.pumpAndSettle();

    expect(callbackInvoked, 'A');
    expect(lineReceived!['id'], 'produto-a');
    expect(lineReceived!['nome'], 'Colar Coração Cravejado Rosa');
    expect(lineReceived!['tamanho'], _tamA);

    final frozen = Map<String, dynamic>.from(lineReceived!);
    freezeCatalogCartLineSnapshotOnAdd(frozen);
    expect(frozen['productId'] ?? frozen['id'], 'produto-a');
    expect(frozen['nomeSnapshot'], 'Colar Coração Cravejado Rosa');
  });
}
