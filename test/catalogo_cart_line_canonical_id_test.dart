// M2.3-R5 — canonicalização de aliases de produto (ID1–ID5).

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/catalog_cart_item_snapshot.dart';

void main() {
  group('ID1 — productId vazio, id válido', () {
    test('usa id como identidade canônica', () {
      final line = {'productId': '', 'id': 'produto-b', 'nome': 'B', 'preco': 10.0};
      expect(catalogCartLineFirstNonEmptyProductId(line), 'produto-b');
      expect(catalogCartLineStructuralRejectionCode(line), isNull);
    });
  });

  group('ID2 — productId só espaços', () {
    test('ignora e usa produtosId', () {
      final line = {
        'productId': '   ',
        'produtosId': 'produto-b',
        'nome': 'B',
        'preco': 10.0,
      };
      expect(catalogCartLineFirstNonEmptyProductId(line), 'produto-b');
    });
  });

  group('ID3 — todos vazios', () {
    test('rejeita empty_identity', () {
      final line = {'productId': '', 'id': '  ', 'nome': 'X', 'preco': 1.0};
      expect(catalogCartLineStructuralRejectionCode(line), 'empty_identity');
    });
  });

  group('ID4 — mesmo id com espaços', () {
    test('sem falso conflito de alias', () {
      final line = {
        'productId': 'produto-b',
        'id': ' produto-b ',
        'nome': 'B',
        'preco': 10.0,
      };
      expect(catalogCartLineRawProductIds(line), {'produto-b'});
      expect(catalogCartLineStructuralRejectionCode(line), isNull);
    });
  });

  group('ID5 — case sensitivity', () {
    test('produto-b e PRODUTO-B são aliases distintos (case-sensitive)', () {
      final line = {
        'productId': 'produto-b',
        'id': 'PRODUTO-B',
        'nome': 'B',
        'preco': 10.0,
      };
      expect(catalogCartLineStructuralRejectionCode(line), 'alias_conflict');
    });
  });
}
