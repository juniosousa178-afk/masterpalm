// M2.3-R4 — matriz de colisão cartLineIdentity.

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/public_catalog/catalog_estoque_helper.dart';

void main() {
  Map<String, dynamic> line({
    required String productId,
    String tamanho = '45cm-v12',
    String cor = 'sem-cor',
    String extra = '',
    String? variacaoId,
  }) =>
      {
        'productId': productId,
        'id': productId,
        'produtosId': productId,
        'tamanho': tamanho,
        'cor': cor,
        if (extra.isNotEmpty) 'extraValor': extra,
        if (variacaoId != null) 'variacaoId': variacaoId,
      };

  test('mesmo produto mesma variação — mesma linha', () {
    final a = line(productId: 'produto-a');
    final b = line(productId: 'produto-a');
    expect(CatalogEstoqueHelper.cartLineIdentity(a),
        CatalogEstoqueHelper.cartLineIdentity(b));
  });

  test('mesmo produto variação diferente — linhas distintas', () {
    final a = line(productId: 'produto-a', tamanho: 'tam-1');
    final b = line(productId: 'produto-a', tamanho: 'tam-2');
    expect(CatalogEstoqueHelper.cartLineIdentity(a),
        isNot(CatalogEstoqueHelper.cartLineIdentity(b)));
  });

  test('produtos diferentes mesmo tamanho — não colidem', () {
    final a = line(productId: 'produto-a', tamanho: '45cm-v12', cor: 'sem-cor');
    final b = line(productId: 'produto-b', tamanho: '45cm-v12', cor: 'sem-cor');
    expect(CatalogEstoqueHelper.cartLineIdentity(a),
        isNot(CatalogEstoqueHelper.cartLineIdentity(b)));
  });

  test('produtos diferentes mesma cor — não colidem', () {
    final a = line(productId: 'produto-a', cor: 'rosa');
    final b = line(productId: 'produto-b', cor: 'rosa');
    expect(CatalogEstoqueHelper.cartLineIdentity(a),
        isNot(CatalogEstoqueHelper.cartLineIdentity(b)));
  });

  test('produtos diferentes mesmo variacaoId textual — não colidem', () {
    final a = line(productId: 'produto-a', variacaoId: 'var-x');
    final b = line(productId: 'produto-b', variacaoId: 'var-x');
    expect(CatalogEstoqueHelper.cartLineIdentity(a),
        isNot(CatalogEstoqueHelper.cartLineIdentity(b)));
  });

  test('mesmo produto sem variação nomes diferentes — mesma identidade canônica', () {
    final a = {
      'productId': 'produto-a',
      'nome': 'Nome antigo',
      'tamanho': '',
      'cor': '',
    };
    final b = {
      'productId': 'produto-a',
      'nome': 'Nome novo',
      'tamanho': '',
      'cor': '',
    };
    expect(CatalogEstoqueHelper.cartLineIdentity(a),
        CatalogEstoqueHelper.cartLineIdentity(b));
  });

  test('legado só productId vs só id — mesma linha se valores iguais', () {
    final legado = {'id': 'produto-a', 'tamanho': 't', 'cor': 'c'};
    final novo = {'productId': 'produto-a', 'tamanho': 't', 'cor': 'c'};
    expect(CatalogEstoqueHelper.cartLineIdentity(legado),
        CatalogEstoqueHelper.cartLineIdentity(novo));
  });

  test('fórmula inclui productId|tamanho|cor|extra', () {
    final id = CatalogEstoqueHelper.cartLineIdentity(
      line(productId: 'produto-a', tamanho: 't', cor: 'c', extra: 'e'),
    );
    expect(id, 'produto-a|t|c|e');
  });
}
