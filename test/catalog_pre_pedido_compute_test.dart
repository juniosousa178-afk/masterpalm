// Regressão mínima: montagem canônica de itens + totais antes de persistir pré-pedido.
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/catalog_pre_pedido_compute.dart';

void main() {
  test(
    'pré-pedido catálogo: itens canônicos, subtotal e total coerentes (caminho feliz)',
    () {
      final cart = [
        {
          'id': 'sku1',
          'produtosId': 'sku1',
          'nome': 'Camisa',
          'quantidade': 2,
          'preco': 50.0,
        },
        {
          'id': '',
          'name': 'Boné',
          'qty': 1,
          'price': 30.0,
        },
      ];
      final entrega = {
        'nome': 'PAC',
        'valor': 10.0,
        'freteGratis': false,
        'tipo': 'correios',
      };

      final snap = computeCatalogPrePedidoMoneySnapshot(
        items: cart,
        entrega: entrega,
        pagamento: 'CARTAO',
        desconto: 5.0,
      );

      expect(snap.itensList.length, 2);

      final i0 = snap.itensList[0];
      expect(i0['id'], 'sku1');
      expect(i0['produtosId'], 'sku1');
      expect(i0['nome'], 'Camisa');
      expect(i0['quantidade'], 2);
      expect(i0['precoUnitario'], 50.0);
      expect(i0['total'], 100.0);

      final i1 = snap.itensList[1];
      expect(i1['nome'], 'Boné');
      expect(i1['quantidade'], 1);
      expect(i1['precoUnitario'], 30.0);
      expect(i1['total'], 30.0);

      expect(snap.subtotal, 130.0);
      expect(snap.total, 135.0);

      final pix = computeCatalogPrePedidoMoneySnapshot(
        items: [
          {
            'id': 'x',
            'nome': 'P',
            'quantidade': 1,
            'preco': 100.0,
            'percentualDescontoPix': 10,
          },
        ],
        entrega: {'valor': 15.0, 'freteGratis': false},
        pagamento: 'pix',
        desconto: 0,
      );
      expect(pix.subtotal, 90.0);
      expect(pix.total, 105.0);
    },
  );

  test(
    'pré-pedido catálogo: frete grátis não soma valor de frete ao total',
    () {
      final snap = computeCatalogPrePedidoMoneySnapshot(
        items: [
          {'id': 'a', 'nome': 'Item', 'quantidade': 1, 'preco': 40.0},
        ],
        entrega: {
          'nome': 'Grátis',
          'valor': 25.0,
          'freteGratis': true,
        },
        pagamento: 'PIX',
        desconto: 0,
      );
      expect(snap.itensList.length, 1);
      expect(snap.subtotal, 40.0);
      expect(snap.total, 40.0);
    },
  );
}
