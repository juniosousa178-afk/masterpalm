import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/catalog_cart_item_snapshot.dart';
import 'package:master_palm/screens/public_catalog/catalog_estoque_helper.dart';

void main() {
  const produtoA = {
    'id': 'anel-aparador',
    'nome': 'Anel Aparador Minimalista',
    'preco': 78.0,
    'percentualDescontoPix': 10.0,
  };
  const produtoB = {
    'id': 'anel-duplo',
    'nome': 'Anel Duplo Coração Vazado',
    'preco': 78.0,
    'percentualDescontoPix': 10.0,
  };

  test('carrinho: linhas distintas mantêm productId e nome do mesmo produto', () {
    final cart = <Map<String, dynamic>>[];
    final addB = {
      'id': 'anel-duplo',
      'produtosId': 'anel-duplo',
      'nome': 'Anel Duplo Coração Vazado',
      'preco': 78.0,
      'quantidade': 1,
      'tamanho': '',
      'cor': '',
    };
    cart.add(Map<String, dynamic>.from(addB));

    expect(cart.length, 1);
    expect(cart.first['id'], 'anel-duplo');
    expect(cart.first['nome'], contains('Duplo'));
    expect(cart.first['preco'], 78.0);
  });

  test('merge por id atualiza nome e preço (não só quantidade)', () {
    final existing = <String, dynamic>{
      'id': 'anel-duplo',
      'nome': 'Anel Aparador Minimalista',
      'preco': 50.25,
      'quantidade': 1,
      'tamanho': '21',
      'cor': 'prata',
    };
    final incoming = <String, dynamic>{
      'id': 'anel-duplo',
      'nome': 'Anel Duplo Coração Vazado',
      'preco': 78.0,
      'quantidade': 1,
      'tamanho': '21',
      'cor': 'prata',
    };

    final keyA = CatalogEstoqueHelper.cartLineIdentity(existing);
    final keyB = CatalogEstoqueHelper.cartLineIdentity(incoming);
    expect(keyA, keyB);

    refreshCatalogCartLineFromAdd(existing, incoming);
    expect(existing['nome'], 'Anel Duplo Coração Vazado');
    expect(existing['preco'], 78.0);
    expect(existing['quantidade'], 1);
  });

  test('não mistura nome de A com preço de B no checkout enriquecido', () {
    final cart = [
      {
        'id': 'anel-duplo',
        'nome': 'Anel Aparador Minimalista',
        'preco': 78.0,
        'quantidade': 1,
        'percentualDescontoPix': 10.0,
      },
    ];
    final prepared = prepareCatalogCheckoutCartItems(
      cartLines: cart,
      catalogProducts: [produtoA, produtoB],
      pagamento: 'PIX',
    );
    expect(prepared.first['nome'], 'Anel Duplo Coração Vazado');
    expect(prepared.first['nomeSnapshot'], 'Anel Duplo Coração Vazado');
    final pix = (prepared.first['precoPixSnapshot'] as num?)?.toDouble();
    expect(pix, closeTo(70.2, 0.01));
  });

  test('fingerprint inclui nome — troca de título invalida reutilização de pré-pedido', () {
    final a = catalogCartFingerprintPart({
      'id': 'x',
      'quantidade': 1,
      'nome': 'Anel Aparador Minimalista',
    });
    final b = catalogCartFingerprintPart({
      'id': 'x',
      'quantidade': 1,
      'nome': 'Anel Duplo Coração Vazado',
    });
    expect(a, isNot(b));
  });
}
