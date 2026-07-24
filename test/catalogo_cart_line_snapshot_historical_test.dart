// M2.3-R5 — snapshot histórico e G6 (S1–S5).

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/catalog_cart_item_snapshot.dart';

void main() {
  group('S1 — nova linha com snapshot pré-injetado conflitante', () {
    test('rejeita snapshot_nome_conflict', () {
      final line = {
        'id': 'produto-b',
        'nome': 'Nome B',
        'nomeSnapshot': 'Nome A',
        'preco': 10.0,
      };
      expect(
        catalogCartLineStructuralRejectionCode(line),
        'snapshot_nome_conflict',
      );
    });
  });

  group('S2 — linha histórica congelada', () {
    test('preserva snapshot sem rejeitar rename do catálogo', () {
      final line = {
        'schemaVersion': catalogCartItemSchemaVersion,
        'productId': 'produto-b',
        'id': 'produto-b',
        'nomeSnapshot': 'Nome antigo de B',
        'nome': 'Nome atual de B',
        'precoUnitarioSnapshot': 79.90,
        'preco': 79.90,
        'quantidade': 1,
      };
      expect(catalogCartLineIsFrozenHistorical(line), isTrue);
      expect(catalogCartLineStructuralRejectionCode(line), isNull);
      expect(line['nomeSnapshot'], 'Nome antigo de B');
    });
  });

  group('S3 — re-freeze idempotente', () {
    test('dois freezes produzem mesmo snapshot', () {
      final line = {
        'id': 'produto-a',
        'nome': 'Produto A',
        'preco': 50.0,
        'quantidade': 1,
        'tamanho': 'tam',
        'cor': 'c',
      };
      freezeCatalogCartLineSnapshotOnAdd(line);
      final after1 = Map<String, dynamic>.from(line);
      freezeCatalogCartLineSnapshotOnAdd(line);
      expect(line['nomeSnapshot'], after1['nomeSnapshot']);
      expect(line['productId'], after1['productId']);
      expect(line['precoUnitarioSnapshot'], after1['precoUnitarioSnapshot']);
      expect(line['schemaVersion'], after1['schemaVersion']);
    });
  });

  group('S4 — legado sem snapshots', () {
    test('aceita linha coerente id+nome+preco', () {
      final legacy = {
        'id': 'produto-a',
        'nome': 'Legado',
        'preco': 12.0,
        'quantidade': 1,
      };
      expect(catalogCartLineStructuralRejectionCode(legacy), isNull);
      freezeCatalogCartLineSnapshotOnAdd(legacy);
      expect(legacy['productId'], 'produto-a');
      expect(legacy['nomeSnapshot'], 'Legado');
    });
  });

  group('S5 — productIdSnapshot conflitante', () {
    test('rejeita snapshot_product_conflict', () {
      final line = {
        'productId': 'produto-b',
        'productIdSnapshot': 'produto-a',
        'nome': 'X',
        'preco': 1.0,
      };
      expect(
        catalogCartLineStructuralRejectionCode(line),
        'snapshot_product_conflict',
      );
    });
  });
}
