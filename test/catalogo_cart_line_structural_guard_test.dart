// M2.3-R4 — guardas estruturais offline (G1–G6) antes da canonicalização.

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/catalog_cart_item_snapshot.dart';

Map<String, dynamic> _validLine() => {
      'id': 'produto-a',
      'nome': 'Produto A',
      'preco': 10.0,
      'quantidade': 1,
      'tamanho': 'tam-a',
      'cor': 'sem-cor',
    };

void main() {
  group('G1 — aliases conflitantes', () {
    test('id vs productId conflitantes rejeita e não altera carrinho', () {
      final cart = [_validLine()];
      final before = cart.map((e) => Map<String, dynamic>.from(e)).toList();
      final incoming = {
        'id': 'produto-a',
        'productId': 'produto-b',
        'nome': 'Produto B',
        'preco': 20.0,
        'quantidade': 1,
        'tamanho': 'tam-b',
        'cor': 'sem-cor',
      };

      expect(catalogCartLineStructuralRejectionCode(incoming), 'alias_conflict');
      expect(
        () => freezeCatalogCartLineSnapshotOnAdd(incoming),
        throwsA(isA<CatalogCartLineRejectedException>()),
      );
      expect(tryFreezeCatalogCartLineSnapshotOnAdd(incoming), isFalse);
      expect(cart, before);
    });
  });

  group('G2 — produtosId conflitante', () {
    test('produtosId vs productId rejeita', () {
      final incoming = {
        'produtosId': 'produto-a',
        'productId': 'produto-b',
        'nome': 'X',
        'preco': 1.0,
      };
      expect(catalogCartLineStructuralRejectionCode(incoming), 'alias_conflict');
    });
  });

  group('G3 — identidade vazia', () {
    test('todos aliases vazios rejeita', () {
      final incoming = {'nome': 'X', 'preco': 1.0};
      expect(catalogCartLineStructuralRejectionCode(incoming), 'empty_identity');
    });
  });

  group('G4 — nome-fonte vazio', () {
    test('productId válido sem nome/name rejeita', () {
      final incoming = {'productId': 'produto-a', 'preco': 1.0};
      expect(catalogCartLineStructuralRejectionCode(incoming), 'empty_nome');
    });
  });

  group('G5 — preço inválido', () {
    test('ausente, não numérico, negativo, NaN e infinito rejeitam', () {
      expect(
        catalogCartLineStructuralRejectionCode({
          'id': 'p',
          'nome': 'N',
        }),
        'invalid_preco',
      );
      expect(
        catalogCartLineStructuralRejectionCode({
          'id': 'p',
          'nome': 'N',
          'preco': 'abc',
        }),
        'invalid_preco',
      );
      expect(
        catalogCartLineStructuralRejectionCode({
          'id': 'p',
          'nome': 'N',
          'preco': -1,
        }),
        'invalid_preco',
      );
      expect(
        catalogCartLineStructuralRejectionCode({
          'id': 'p',
          'nome': 'N',
          'preco': double.nan,
        }),
        'invalid_preco',
      );
      expect(
        catalogCartLineStructuralRejectionCode({
          'id': 'p',
          'nome': 'N',
          'preco': double.infinity,
        }),
        'invalid_preco',
      );
    });
  });

  group('G6 — snapshot preexistente conflitante', () {
    test('nomeSnapshot diferente de nome rejeita antes do freeze', () {
      final incoming = {
        'id': 'produto-a',
        'nome': 'Nome A',
        'nomeSnapshot': 'Nome B',
        'preco': 10.0,
      };
      expect(
        catalogCartLineStructuralRejectionCode(incoming),
        'snapshot_nome_conflict',
      );
    });
  });

  group('atomicidade na rejeição', () {
    test('carrinho antes == carrinho depois ao rejeitar merge', () {
      final cart = [_validLine()];
      final before = cart.map((e) => Map<String, dynamic>.from(e)).toList();
      final incoming = {
        'id': 'produto-b',
        'nome': 'Produto B',
        'preco': 20.0,
        'quantidade': 1,
        'tamanho': 'tam-a',
        'cor': 'sem-cor',
      };

      expect(
        () => refreshCatalogCartLineFromAdd(cart.first, incoming),
        throwsA(isA<CatalogCartLineRejectedException>()),
      );
      expect(cart, before);
    });
  });
}
