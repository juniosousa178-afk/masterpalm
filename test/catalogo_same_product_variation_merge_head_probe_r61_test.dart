// M2.3-R6.1 — merge real pré-patch: mesmas etiquetas, variacaoId distinto.

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/public_catalog/catalog_estoque_helper.dart';
import 'package:master_palm/services/catalog_cart_item_snapshot.dart';

const _productId = 'produto-b';
const _tam = '45cm';
const _cor = 'sem-cor';

String headCartLineIdentity(Map<String, dynamic> item) {
  final id = '${item['id'] ?? item['produtosId'] ?? ''}';
  final tam = (item['tamanho'] ?? '').toString().trim().toLowerCase();
  final cr = (item['cor'] ?? '').toString().trim().toLowerCase();
  final ex = (item['extraValor'] ?? item['variacaoExtra'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  return '$id|$tam|$cr|$ex';
}

void headRefreshCatalogCartLineFromAdd(
  Map<String, dynamic> existingLine,
  Map<String, dynamic> incoming,
) {
  for (final key in [
    'id',
    'produtosId',
    'nome',
    'preco',
    'tamanho',
    'cor',
    'variacaoId',
  ]) {
    if (incoming.containsKey(key)) {
      existingLine[key] = incoming[key];
    }
  }
}

bool headAddToCart(
  List<Map<String, dynamic>> cart,
  Map<String, dynamic> item,
) {
  final key = headCartLineIdentity(item);
  final idx = cart.indexWhere((e) => headCartLineIdentity(e) == key);
  if (idx >= 0) {
    final cur = (cart[idx]['quantidade'] as num?)?.toInt() ?? 1;
    final add = (item['quantidade'] as num?)?.toInt() ?? 1;
    cart[idx]['quantidade'] = cur + add;
    headRefreshCatalogCartLineFromAdd(cart[idx], item);
    return true;
  }
  final copy = Map<String, dynamic>.from(item);
  cart.add(copy);
  return true;
}

Map<String, dynamic> _line1() => {
      'id': _productId,
      'produtosId': _productId,
      'nome': 'Var 001',
      'preco': 79.90,
      'quantidade': 1,
      'tamanho': _tam,
      'cor': _cor,
      'variacaoId': 'variacao-001',
    };

Map<String, dynamic> _line2() => {
      'id': _productId,
      'produtosId': _productId,
      'nome': 'Var 002',
      'preco': 89.90,
      'quantidade': 1,
      'tamanho': _tam,
      'cor': _cor,
      'variacaoId': 'variacao-002',
    };

void main() {
  test('HEAD — identidade colide sem variacaoId na chave', () {
    expect(headCartLineIdentity(_line1()), headCartLineIdentity(_line2()));
    expect(
      CatalogEstoqueHelper.cartLineIdentity(_line1()),
      isNot(CatalogEstoqueHelper.cartLineIdentity(_line2())),
    );
  });

  test('HEAD — _addToCart mescla duas variações com rótulos iguais', () {
    final cart = <Map<String, dynamic>>[];
    expect(headAddToCart(cart, _line1()), isTrue);
    expect(headAddToCart(cart, _line2()), isTrue);
    expect(cart.length, 1);
    expect(cart.single['quantidade'], 2);
    expect(cart.single['variacaoId'], 'variacao-002');
    expect(cart.single['preco'], 89.90);
  });

  test('pós-patch — duas linhas independentes no carrinho', () {
    final cart = <Map<String, dynamic>>[];
    void postAdd(Map<String, dynamic> item) {
      final key = CatalogEstoqueHelper.cartLineIdentity(item);
      final idx =
          cart.indexWhere((e) => CatalogEstoqueHelper.cartLineIdentity(e) == key);
      if (idx >= 0) {
        refreshCatalogCartLineFromAdd(cart[idx], item);
        cart[idx]['quantidade'] =
            ((cart[idx]['quantidade'] as num?)?.toInt() ?? 1) +
                ((item['quantidade'] as num?)?.toInt() ?? 1);
      } else {
        final copy = Map<String, dynamic>.from(item);
        freezeCatalogCartLineSnapshotOnAdd(copy);
        cart.add(copy);
      }
    }

    postAdd(_line1());
    postAdd(_line2());
    expect(cart.length, 2);
    expect(cart[0]['variacaoId'], 'variacao-001');
    expect(cart[1]['variacaoId'], 'variacao-002');
    expect(cart[0]['quantidade'], 1);
    expect(cart[1]['quantidade'], 1);
  });
}
