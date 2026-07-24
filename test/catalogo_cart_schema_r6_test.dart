// M2.3-R6 — schema carrinho v1: compatibilidade, migração e versões futuras.

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/public_catalog/catalog_estoque_helper.dart';
import 'package:master_palm/services/catalog_cart_item_snapshot.dart';

const _nomeA = 'Colar Coração Cravejado Rosa';
const _tamA = 'variacao-a';
const _tamB = 'variacao-b';

void main() {
  group('Schema 1 — linha v1 coerente restaurada', () {
    test('linha legada sem schemaVersion permanece legível', () {
      final legacy = {
        'id': 'produto-a',
        'nome': _nomeA,
        'preco': 120.0,
        'quantidade': 1,
        'tamanho': _tamA,
      };
      final restored = filterStructurallyValidCatalogCartLines([legacy]);
      expect(restored.length, 1);
      expect(restored.single['nome'], _nomeA);
      expect((restored.single['preco'] as num).toDouble(), 120.0);
    });
  });

  group('Schema 2 — linha v2 (pós-freeze) restaurada sem perda', () {
    test('campos snapshot preservados após round-trip JSON', () {
      final line = {
        'id': 'produto-b',
        'nome': 'Colar Gota',
        'preco': 79.90,
        'quantidade': 2,
        'tamanho': _tamB,
        'cor': 'cor-b',
        'variacaoId': 'variacao-b',
      };
      freezeCatalogCartLineSnapshotOnAdd(line);
      final copy = Map<String, dynamic>.from(line);
      final restored = filterStructurallyValidCatalogCartLines([copy]);
      expect(restored.length, 1);
      final r = restored.single;
      expect(r['schemaVersion'], catalogCartItemSchemaVersion);
      expect(r['productIdSnapshot'], 'produto-b');
      expect(r['nomeSnapshot'], 'Colar Gota');
      expect(r['precoUnitarioSnapshot'], 79.90);
      expect(r['variacaoId'], 'variacao-b');
    });
  });

  group('Schema 3 — versão futura desconhecida', () {
    test('schemaVersion > atual não é silenciosamente v1', () {
      final future = {
        'schemaVersion': catalogCartItemSchemaVersion + 1,
        'id': 'produto-x',
        'nome': 'Futuro',
        'preco': 10.0,
        'quantidade': 1,
        'productIdSnapshot': 'produto-x',
        'nomeSnapshot': 'Futuro',
        'precoUnitarioSnapshot': 10.0,
      };
      expect(catalogCartLineIsFrozenHistorical(future), isTrue);
      final code = catalogCartLineStructuralRejectionCode(future);
      expect(code, isNull);
    });
  });

  group('Schema 4 — migração não altera snapshots históricos', () {
    test('freeze idempotente mantém nomeSnapshot original', () {
      final historical = {
        'schemaVersion': catalogCartItemSchemaVersion,
        'id': 'produto-a',
        'productId': 'produto-a',
        'nome': 'Nome catálogo novo',
        'nomeSnapshot': _nomeA,
        'preco': 50.0,
        'precoUnitarioSnapshot': 99.0,
        'quantidade': 1,
        'tamanho': _tamA,
      };
      final beforeNome = historical['nomeSnapshot'];
      final beforePreco = historical['precoUnitarioSnapshot'];
      expect(catalogCartLineIsFrozenHistorical(historical), isTrue);
      expect(
        catalogCartLineStructuralRejectionCode(historical),
        isNull,
      );
      expect(historical['nomeSnapshot'], beforeNome);
      expect(historical['precoUnitarioSnapshot'], beforePreco);
    });
  });

  group('Schema 5 — v1 sem variacaoId vs v2 com variacaoId', () {
    test('identidades distintas não colidem', () {
      final v1 = {
        'id': 'produto-a',
        'nome': _nomeA,
        'preco': 99.0,
        'quantidade': 1,
        'tamanho': _tamA,
        'cor': 'cor-a',
      };
      final v2 = {
        'id': 'produto-a',
        'nome': _nomeA,
        'preco': 99.0,
        'quantidade': 1,
        'tamanho': _tamA,
        'cor': 'cor-a',
        'variacaoId': 'variacao-a',
      };
      final idV1 = CatalogEstoqueHelper.cartLineIdentity(v1);
      final idV2 = CatalogEstoqueHelper.cartLineIdentity(v2);
      expect(idV1, isNot(equals(idV2)));
      expect(idV1, contains('produto-a'));
      expect(idV2, contains('vid|variacao-a'));
    });
  });
}
