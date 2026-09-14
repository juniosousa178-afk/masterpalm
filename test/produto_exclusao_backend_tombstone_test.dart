import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_exclusao_remota_service.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:master_palm/services/stock_catalog_backend_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProdutoExclusaoTombstoneService.resetCacheForTests();
  });

  tearDown(() {
    StockCatalogBackendService.debugTransport = null;
    ProdutoExclusaoTombstoneService.resetCacheForTests();
  });

  test('delete and undo use backend command isolated by lojaId/productId',
      () async {
    final calls = <Map<String, dynamic>>[];
    StockCatalogBackendService.debugTransport = (name, data) async {
      expect(name, 'stockCatalogCommand');
      calls.add(Map<String, dynamic>.from(data));
      return {
        'operationId': data['operationId'],
        'products': [
          {'productId': 'produto-a', 'quantidade': 0, 'stockRevision': 8}
        ],
      };
    };

    final produto = Produto.vazio()
      ..idFirebase = 'produto-a'
      ..lojaId = 'loja-a'
      ..stockRevision = 7;

    expect(
      await ProdutoExclusaoRemotaService.marcarEstoqueProdutoPendenteSoftDelete(
        produto: produto,
        lojaId: 'loja-a',
      ),
      isTrue,
    );
    await ProdutoExclusaoRemotaService.limparEstoquePendenteSoftDelete(
      lojaId: 'loja-a',
      produtoIdFirebase: 'produto-a',
      expectedRevision: produto.stockRevision,
    );

    expect(calls.map((c) => c['kind']), ['delete', 'undo']);
    for (final call in calls) {
      expect(call['lojaId'], 'loja-a');
      expect((call['items'] as List).single['productId'], 'produto-a');
    }
    expect((calls.first['items'] as List).single['expectedRevision'], 7);
    expect((calls.last['items'] as List).single['expectedRevision'], 8);
  });

  test('VARIATION_DELETE uses backend and never full-product tombstone', () async {
    final calls = <Map<String, dynamic>>[];
    StockCatalogBackendService.debugTransport = (name, data) async {
      expect(name, 'stockCatalogCommand');
      calls.add(Map<String, dynamic>.from(data));
      return {
        'operationId': data['operationId'],
        'products': [
          {'productId': 'produto-a', 'quantidade': 5, 'stockRevision': 3}
        ],
      };
    };

    final key = ProdutoExclusaoTombstoneService.vKeyCelula('M', 'Azul');
    expect(
      await ProdutoExclusaoTombstoneService
          .registrarTombstoneExclusaoVarSessaoExplicita(
        lojaId: 'loja-a',
        estoqueDocId: 'produto-a',
        chaves: {key},
        expectedRevision: 3,
      ),
      isTrue,
    );

    expect(calls, hasLength(1));
    expect(calls.single['kind'], 'tombstoneVariation');
    expect(calls.single['tombstoneKeys'], [key]);
    expect((calls.single['items'] as List).single['expectedRevision'], 3);
    expect(calls.single['kind'], isNot('delete'));
  });

  test('clearVariationTombstone reuses durable backend operation', () async {
    final calls = <Map<String, dynamic>>[];
    StockCatalogBackendService.debugTransport = (name, data) async {
      calls.add(Map<String, dynamic>.from(data));
      return {
        'operationId': data['operationId'],
        'products': [
          {'productId': 'produto-a', 'quantidade': 5, 'stockRevision': 4}
        ],
      };
    };

    final key = ProdutoExclusaoTombstoneService.tKeySoloTamanho('M');
    // Seed local cache as if variation was previously tombstoned.
    ProdutoExclusaoTombstoneService.debugFirestoreOverride = FakeFirebaseFirestore();
    await ProdutoExclusaoTombstoneService
        .registrarTombstoneExclusaoVarSessaoExplicita(
      lojaId: 'loja-a',
      estoqueDocId: 'produto-a',
      chaves: {key},
      expectedRevision: 3,
    );
    // Switch to production path (no override) while keeping in-memory keys.
    ProdutoExclusaoTombstoneService.debugFirestoreOverride = null;

    await ProdutoExclusaoTombstoneService.liberarTombstonesVariacoesAtivas(
      lojaId: 'loja-a',
      estoqueDocId: 'produto-a',
      variacoesMap: {
        'M': {'Azul': 2},
      },
      estoquePorTamanho: {'M': 2},
      expectedRevision: 4,
    );

    final backendCalls =
        calls.where((c) => c['kind'] == 'clearVariationTombstone').toList();
    expect(backendCalls, hasLength(1));
    expect(backendCalls.single['tombstoneKeys'], contains(key));
  });

  test('PARTIAL_LEGACY_TOMBSTONE_MEANS_FULL_DELETE=false', () async {
    final firestore = FakeFirebaseFirestore();
    ProdutoExclusaoTombstoneService.debugFirestoreOverride = firestore;
    await firestore
        .collection('lojas')
        .doc('loja-a')
        .collection(FSPaths.exclusaoProdutoCol)
        .doc('produto-a')
        .set({
      'p': false,
      'v': {ProdutoExclusaoTombstoneService.tKeySoloTamanho('M'): true},
    });

    expect(
      await ProdutoExclusaoTombstoneService.isProdutoBloqueadoRemoto(
        lojaId: 'loja-a',
        estoqueDocId: 'produto-a',
      ),
      isFalse,
    );
  });

  test('STALE_QUEUE_CAN_RESURRECT_DELETED_PRODUCT=false', () {
    final estoqueSync =
        File('lib/services/estoque_service.dart').readAsStringSync();
    final catalogSync =
        File('lib/services/catalogo_sync_service.dart').readAsStringSync();

    expect(estoqueSync,
        contains('[DELETE_GUARD] syncProduto bloqueado (tombstone)'));
    expect(estoqueSync, contains('isProdutoBloqueadoRemoto'));
    expect(catalogSync, contains('isProdutoBloqueadoRemoto'));
    expect(catalogSync, contains('StockCatalogBackendService.saveEditorial'));
  });
}
