// M2.3-R5 — cartLineIdentity + variacaoId (V1–V7).

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/public_catalog/catalog_estoque_helper.dart';
import 'package:master_palm/services/catalog_cart_item_snapshot.dart';

Map<String, dynamic> _line({
  required String productId,
  String? variacaoId,
  String tamanho = '45cm',
  String cor = 'sem-cor',
  String extra = '',
  double preco = 79.90,
  int quantidade = 1,
}) =>
    {
      'productId': productId,
      'id': productId,
      'nome': 'Produto',
      'preco': preco,
      'quantidade': quantidade,
      if (variacaoId != null) 'variacaoId': variacaoId,
      'tamanho': tamanho,
      'cor': cor,
      if (extra.isNotEmpty) 'extraValor': extra,
    };

void main() {
  group('V1 — mesma aparência, variacaoId diferente', () {
    test('não colidem', () {
      final a = _line(
        productId: 'produto-b',
        variacaoId: 'variacao-001',
        tamanho: '45cm',
      );
      final b = _line(
        productId: 'produto-b',
        variacaoId: 'variacao-002',
        tamanho: '45cm',
      );
      expect(CatalogEstoqueHelper.cartLineIdentity(a),
          isNot(CatalogEstoqueHelper.cartLineIdentity(b)));
      expect(CatalogEstoqueHelper.cartLineIdentity(a), 'produto-b|vid|variacao-001');
    });
  });

  group('V2 — mesma variacaoId, rótulo tamanho diferente', () {
    test('mesma identidade quando variacaoId estável', () {
      final a = _line(
        productId: 'produto-b',
        variacaoId: 'variacao-001',
        tamanho: '45cm',
      );
      final b = _line(
        productId: 'produto-b',
        variacaoId: 'variacao-001',
        tamanho: '45 cm',
      );
      expect(CatalogEstoqueHelper.cartLineIdentity(a),
          CatalogEstoqueHelper.cartLineIdentity(b));
    });
  });

  group('V3 — ausência de variacaoId (legado)', () {
    test('fallback tamanho|cor|extra', () {
      final line = _line(productId: 'produto-a', tamanho: 'tam-x', cor: 'rosa');
      expect(
        CatalogEstoqueHelper.cartLineIdentity(line),
        'produto-a|tam-x|rosa|',
      );
    });
  });

  group('V4 — variacaoId igual, produtos diferentes', () {
    test('linhas distintas', () {
      final a = _line(productId: 'produto-a', variacaoId: 'variacao-001');
      final b = _line(productId: 'produto-b', variacaoId: 'variacao-001');
      expect(CatalogEstoqueHelper.cartLineIdentity(a),
          isNot(CatalogEstoqueHelper.cartLineIdentity(b)));
    });
  });

  group('V5 — uma linha com variacaoId, outra sem', () {
    test('não mesclam silenciosamente', () {
      final com = _line(productId: 'produto-b', variacaoId: 'variacao-001');
      final sem = _line(productId: 'produto-b', tamanho: '45cm');
      expect(CatalogEstoqueHelper.cartLineIdentity(com),
          isNot(CatalogEstoqueHelper.cartLineIdentity(sem)));
    });
  });

  group('V6 — preços diferentes, mesmos rótulos, variacaoId distintas', () {
    test('não colidem', () {
      final a = _line(
        productId: 'produto-b',
        variacaoId: 'variacao-preco-10',
        preco: 10,
      );
      final b = _line(
        productId: 'produto-b',
        variacaoId: 'variacao-preco-20',
        preco: 20,
      );
      expect(CatalogEstoqueHelper.cartLineIdentity(a),
          isNot(CatalogEstoqueHelper.cartLineIdentity(b)));
    });
  });

  group('V7 — mesma variação, quantidade somada no merge', () {
    test('mesma identidade permite refresh', () {
      final existing = _line(
        productId: 'produto-b',
        variacaoId: 'variacao-001',
        quantidade: 1,
      );
      freezeCatalogCartLineSnapshotOnAdd(existing);
      final incoming = _line(
        productId: 'produto-b',
        variacaoId: 'variacao-001',
        quantidade: 1,
        preco: 88.0,
        tamanho: '45cm',
      );
      final keyA = CatalogEstoqueHelper.cartLineIdentity(existing);
      final keyB = CatalogEstoqueHelper.cartLineIdentity(incoming);
      expect(keyA, keyB);
      refreshCatalogCartLineFromAdd(existing, incoming);
      expect(existing['productId'], 'produto-b');
      expect(existing['variacaoId'], 'variacao-001');
    });
  });

  group('combo — identidade própria', () {
    test('combo com componentes distintos', () {
      final a = {
        'productId': 'combo-1',
        'itensComboComSelecao': [
          {'productId': 'p1', 'tamanho': 'm', 'cor': '', 'quantidade': 1},
        ],
      };
      final b = {
        'productId': 'combo-1',
        'itensComboComSelecao': [
          {'productId': 'p2', 'tamanho': 'm', 'cor': '', 'quantidade': 1},
        ],
      };
      expect(CatalogEstoqueHelper.cartLineIdentity(a),
          isNot(CatalogEstoqueHelper.cartLineIdentity(b)));
    });
  });
}
