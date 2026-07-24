// M2.3-R6.1 — busca real (ValueListenableBuilder + sanitize) com sheet aberto.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/public_catalog/catalog_url_query_codec.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_product_card.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_product_selection_sheet.dart';
import 'package:master_palm/services/catalog_cart_item_snapshot.dart';

const _lojaId = 'loja-r61-search';
const _tamA = 'variacao-a';

Map<String, dynamic> _produtoA() => {
      'id': 'produto-a',
      'nome': 'Colar Coração Cravejado Rosa',
      'descricao': 'coracao cravejado',
      'preco': 99.90,
      'slug': 'a',
      'estoquePorTamanho': {_tamA: 3},
      'imageUrl': '',
      'imagens': <String>[],
    };

Map<String, dynamic> _produtoB() => {
      'id': 'produto-b',
      'nome': 'Colar Ponto de Luz Gota 45cm',
      'descricao': 'gota 45cm',
      'preco': 79.90,
      'slug': 'b',
      'estoquePorTamanho': {'variacao-b': 5},
      'imageUrl': '',
      'imagens': <String>[],
    };

List<Map<String, dynamic>> _filtrarPorBusca(
  List<Map<String, dynamic>> produtos,
  String search,
) {
  final q = (catalogSanitizeSearchQuery(search) ?? '').toLowerCase();
  return produtos.where((p) {
    if (q.isEmpty) return true;
    final n = (p['nome'] ?? '').toString().toLowerCase();
    final d = (p['descricao'] ?? '').toString().toLowerCase();
    return n.contains(q) || d.contains(q);
  }).toList();
}

Future<void> _pumpIgnoreImages(WidgetTester tester) async {
  await tester.pump();
  while (tester.takeException() != null) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('busca via ValueListenableBuilder troca card com sheet aberto',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final searchNotifier = ValueNotifier<String>('');
    final produtos = [_produtoA(), _produtoB()];
    final cart = <Map<String, dynamic>>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextField(
                decoration: const InputDecoration(labelText: 'Busca catálogo'),
                onChanged: (v) => searchNotifier.value = v,
              ),
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: searchNotifier,
                  builder: (context, search, _) {
                    final lista = _filtrarPorBusca(produtos, search);
                    final p = lista.first;
                    return CatalogProductCard(
                      id: p['id'] as String,
                      name: p['nome'] as String,
                      price: (p['preco'] as num).toDouble(),
                      imageUrl: '',
                      imagens: const [],
                      descricao: p['descricao'] as String,
                      slug: p['slug'] as String,
                      estoquePorTamanho:
                          Map<String, int>.from(p['estoquePorTamanho'] as Map),
                      onAdd: (item) {
                        final copy = Map<String, dynamic>.from(item);
                        freezeCatalogCartLineSnapshotOnAdd(copy);
                        cart.add(copy);
                        return true;
                      },
                      lojaId: _lojaId,
                      onAbrirCarrinho: () {},
                      produtoCatalogoMap: p,
                      quantidade: 5,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Comprar').first);
    await _pumpIgnoreImages(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      tester
          .widget<CatalogProductSelectionSheet>(
            find.byType(CatalogProductSelectionSheet),
          )
          .productId,
      'produto-a',
    );

    await tester.tap(find.text(_tamA));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'gota');
    await tester.pumpAndSettle();

    expect(
      tester.widget<CatalogProductCard>(find.byType(CatalogProductCard)).id,
      'produto-b',
    );
    expect(
      tester
          .widget<CatalogProductSelectionSheet>(
            find.byType(CatalogProductSelectionSheet),
          )
          .productId,
      'produto-a',
    );

    await tester.tap(find.text('Adicionar ao carrinho'));
    await tester.pumpAndSettle();

    expect(cart.single['id'], 'produto-a');
    expect(cart.single['nomeSnapshot'] ?? cart.single['nome'],
        'Colar Coração Cravejado Rosa');
    expect(cart.single['tamanho'], _tamA);
  });
}
