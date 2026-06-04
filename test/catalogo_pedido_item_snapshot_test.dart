import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/catalog_cart_item_snapshot.dart';
import 'package:master_palm/services/catalog_pre_pedido_compute.dart';

void main() {
  const produtoB = {
    'id': 'anel-duplo',
    'nome': 'Anel Duplo Coração Vazado',
    'preco': 78.0,
    'percentualDescontoPix': 10.0,
  };

  test('pedido salvo grava nomeSnapshot e precoPixSnapshot coerentes (PIX)', () {
    final cart = prepareCatalogCheckoutCartItems(
      cartLines: [
        {
          'id': 'anel-duplo',
          'nome': 'Anel Duplo Coração Vazado',
          'preco': 78.0,
          'quantidade': 1,
          'percentualDescontoPix': 10.0,
        },
      ],
      catalogProducts: [produtoB],
      pagamento: 'PIX',
    );

    final snap = computeCatalogPrePedidoMoneySnapshot(
      items: cart,
      entrega: {'valor': 0.0, 'freteGratis': true},
      pagamento: 'PIX',
    );

    expect(snap.itensList.length, 1);
    final item = snap.itensList.first;
    expect(item['nome'], 'Anel Duplo Coração Vazado');
    expect(item['nomeSnapshot'], 'Anel Duplo Coração Vazado');
    expect(item['precoUnitario'], closeTo(70.2, 0.01));
    expect(item['precoPixSnapshot'], closeTo(70.2, 0.01));
    expect(snap.total, closeTo(70.2, 0.01));
  });

  test('corrige nome stale no carrinho via catálogo antes do snapshot', () {
    final snap = computeCatalogPrePedidoMoneySnapshot(
      items: prepareCatalogCheckoutCartItems(
        cartLines: [
          {
            'id': 'anel-duplo',
            'nome': 'Anel Aparador Minimalista',
            'preco': 78.0,
            'quantidade': 1,
            'percentualDescontoPix': 10.0,
          },
        ],
        catalogProducts: [produtoB],
        pagamento: 'PIX',
      ),
      entrega: {'valor': 0.0, 'freteGratis': true},
      pagamento: 'PIX',
    );

    expect(snap.itensList.first['nome'], 'Anel Duplo Coração Vazado');
    expect(snap.itensList.first['nomeSnapshot'], 'Anel Duplo Coração Vazado');
    expect(snap.itensList.first['precoUnitario'], closeTo(70.2, 0.01));
  });

  test('pedidos antigos sem nomeSnapshot continuam exibindo nome legado', () {
    expect(
      catalogPedidoItemDisplayName({
        'nome': 'Anel Aparador Minimalista',
        'precoUnitario': 70.2,
      }),
      'Anel Aparador Minimalista',
    );
    expect(
      catalogPedidoItemDisplayName({
        'nome': 'Legado',
        'nomeSnapshot': 'Anel Duplo Coração Vazado',
      }),
      'Anel Duplo Coração Vazado',
    );
  });
}
