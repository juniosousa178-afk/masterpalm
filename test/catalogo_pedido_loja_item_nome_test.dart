import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/catalog_cart_item_snapshot.dart';
import 'package:master_palm/services/catalog_pre_pedido_compute.dart';

/// Simula o que o painel do lojista lê do documento de pré-pedido.
String lojistaLinhaPedido(Map<String, dynamic> item) {
  final nome = catalogPedidoItemDisplayName(item);
  final preco = (item['precoUnitario'] as num?)?.toDouble() ?? 0.0;
  final qty = (item['quantidade'] as num?)?.toInt() ?? 1;
  return '${qty}x $nome @ R\$ ${preco.toStringAsFixed(2)}';
}

void main() {
  test('lojista vê nome do snapshot, não nome desatualizado por id', () {
    final docItem = computeCatalogPrePedidoMoneySnapshot(
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
        catalogProducts: [
          {
            'id': 'anel-duplo',
            'nome': 'Anel Duplo Coração Vazado',
            'preco': 78.0,
          },
        ],
        pagamento: 'PIX',
      ),
      entrega: {'valor': 0.0, 'freteGratis': true},
      pagamento: 'PIX',
    ).itensList.first;

    final linha = lojistaLinhaPedido(docItem);
    expect(linha, contains('Anel Duplo Coração Vazado'));
    expect(linha, isNot(contains('Aparador')));
    expect(linha, contains('70.20'));
  });

  test('múltiplos itens mantêm identidade individual', () {
    final snap = computeCatalogPrePedidoMoneySnapshot(
      items: prepareCatalogCheckoutCartItems(
        cartLines: [
          {
            'id': 'anel-aparador',
            'nome': 'Anel Aparador Minimalista',
            'preco': 50.25,
            'quantidade': 1,
          },
          {
            'id': 'anel-duplo',
            'nome': 'Anel Duplo Coração Vazado',
            'preco': 78.0,
            'quantidade': 1,
            'percentualDescontoPix': 10.0,
          },
        ],
        catalogProducts: [
          {
            'id': 'anel-aparador',
            'nome': 'Anel Aparador Minimalista',
            'preco': 50.25,
          },
          {
            'id': 'anel-duplo',
            'nome': 'Anel Duplo Coração Vazado',
            'preco': 78.0,
            'percentualDescontoPix': 10.0,
          },
        ],
        pagamento: 'PIX',
      ),
      entrega: {'valor': 0.0, 'freteGratis': true},
      pagamento: 'PIX',
    );

    expect(snap.itensList[0]['nomeSnapshot'], 'Anel Aparador Minimalista');
    expect(snap.itensList[1]['nomeSnapshot'], 'Anel Duplo Coração Vazado');
    expect(snap.itensList[1]['precoUnitario'], closeTo(70.2, 0.01));
  });
}
