import 'package:master_palm/services/produto_vendas_catalogo_denorm_service.dart';
import 'package:master_palm/models/produto.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/services/migrate_collections_service.dart';
import 'package:master_palm/services/consolidate_stores.dart';
import 'package:master_palm/services/sync_firestore_script.dart';
import 'package:master_palm/utils/migrar_para_estoque.dart';
import 'dart:convert';
import 'package:master_palm/screens/public_catalog/catalog_estoque_helper.dart';
import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/stock_catalog_backend_service.dart';

void main() {
  tearDown(() => StockCatalogBackendService.debugTransport = null);
  test('publication sends identifiers only', () async {
    StockCatalogBackendService.debugTransport = (name, data) async {
      expect(name, 'catalogPublishOne');
      expect(data, {'lojaId': 'a', 'productId': 'p'});
      return {'available': true};
    };
    await StockCatalogBackendService.publishOne('a', 'p');
  });
  test('uncertain commit retries the exact operation identity', () async {
    final calls = <Map<String, dynamic>>[];
    StockCatalogBackendService.debugTransport = (name, data) async {
      calls.add(Map.of(data));
      if (calls.length == 1) {
        throw FirebaseFunctionsException(
            code: 'unavailable', message: 'timeout');
      }
      return {'alreadyApplied': true, 'products': <dynamic>[]};
    };
    final result = await StockCatalogBackendService.command(
        lojaId: 'a',
        operationId: 'sale-1',
        kind: 'sale',
        items: [
          {'productId': 'p', 'quantity': 1}
        ]);
    expect(result['alreadyApplied'], true);
    expect(calls.length, 2);
    expect(calls[0], calls[1]);
  });
  test('permission denial propagates without insecure fallback', () async {
    var calls = 0;
    StockCatalogBackendService.debugTransport = (name, data) async {
      calls++;
      throw FirebaseFunctionsException(
          code: 'permission-denied', message: 'grant absent');
    };
    await expectLater(
        StockCatalogBackendService.command(
            lojaId: 'a',
            operationId: 'sale-1',
            kind: 'sale',
            items: [
              {'productId': 'p', 'quantity': 1}
            ]),
        throwsA(isA<FirebaseFunctionsException>()));
    expect(calls, 1);
  });
  test('cross-path identifiers rejected locally', () {
    expect(() => StockCatalogBackendService.publishOne('a/other', 'p'),
        throwsArgumentError);
  });
  test(
      'editorial allowlist matches backend and excludes protected stock fields',
      () {
    final server =
        File('functions/src/catalogStockProjection.js').readAsStringSync();
    final block = server
        .split('export const EDITORIAL_FIELDS = Object.freeze([')[1]
        .split(']);')
        .first;
    final names =
        RegExp("'([^']+)'").allMatches(block).map((m) => m.group(1)!).toSet();
    expect(StockCatalogBackendService.editorialFields, names);
    expect(
        names.intersection({
          'quantidade',
          'stockRevision',
          'variacoes',
          'itensCombo',
          'estoque_atual'
        }),
        isEmpty);
  });
  test('editorial command strips stock from an old full-product snapshot',
      () async {
    StockCatalogBackendService.debugTransport = (name, data) async {
      expect(name, 'stockCatalogCommand');
      expect(data['kind'], 'editorial');
      expect(data['editorial'], {
        'nome': 'Novo',
        'descontoComboValor': 3,
        'publicadoNoCatalogo': true
      });
      expect(data['items'], [
        {'productId': 'p'}
      ]);
      return {'products': []};
    };
    await StockCatalogBackendService.saveEditorial('a', 'p', {
      'nome': 'Novo',
      'descontoComboValor': 3,
      'publicadoNoCatalogo': true,
      'quantidade': 9,
      'variacoes': {
        'P': {'Azul': 9}
      },
      'stockRevision': 99,
    });
  });
  test('identical later editorial intent gets a new identity', () async {
    final ids = <String>[];
    StockCatalogBackendService.debugTransport = (_, data) async {
      ids.add(data['operationId'] as String);
      return {'products': []};
    };
    await StockCatalogBackendService.saveEditorial('a', 'p', {'nome': 'A'});
    await StockCatalogBackendService.saveEditorial('a', 'p', {'nome': 'A'});
    expect(ids.toSet().length, 2);
  });

  final projectionFixtures = jsonDecode(
      File('test/fixtures/stock_catalog_projection.json')
          .readAsStringSync()) as List;
  for (final raw in projectionFixtures) {
    final fixture = Map<String, dynamic>.from(raw as Map);
    test('shared Flutter/server projection: ${fixture['name']}', () {
      final display = Map<String, dynamic>.from(fixture['display'] as Map);
      final result = CatalogEstoqueHelper.processStockFromFirestoreMap(display,
          isCombo: false);
      expect(result.quantidadeTotal, fixture['total']);
      expect(result.incluirNoCatalogo, (fixture['total'] as int) > 0);
    });
  }

  test(
      'retired stock migration and cleanup reject before Firebase initialization',
      () async {
    await expectLater(
        MigrateCollectionsService().migrateAll(), throwsStateError);
    await expectLater(migrarParaEstoque('a'), throwsStateError);
    await expectLater(
        SyncFirestoreScript.limparDadosTeste('a'), throwsStateError);
    final consolidation = await ConsolidateStoresService.consolidate();
    expect(consolidation['success'], false);
    expect(consolidation['error'], contains('Consolidação legada desativada'));
  });

  test('repeated catalog side effect does not issue a second counter mutation',
      () async {
    StockCatalogBackendService.debugTransport =
        (_, data) async => throw StateError('Unexpected command');
    // No Hive/Firestore access is needed: the server order operation owns ranking.
    final box = _UnusedProductBox();
    for (var n = 0; n < 2; n++) {
      await ProdutoVendasCatalogoDenormService.incrementarAposVendaCatalogo(
          lojaId: 'a',
          items: [
            {'productId': 'p', 'quantidade': 1}
          ],
          produtosBox: box);
    }
  });
  test('no double counter increment is owned by order operation replay',
      () async {
    var counter = 0;
    final seen = <String>{};
    StockCatalogBackendService.debugTransport = (name, data) async {
      expect(name, 'stockCatalogOrderSale');
      final op = StockCatalogBackendService.orderSaleOperationId(
          data['orderId'] as String);
      final firstApply = seen.add(op);
      if (firstApply) counter++;
      return {
        'alreadyApplied': !firstApply,
        'operationId': op,
        'products': <dynamic>[],
      };
    };
    await StockCatalogBackendService.orderSale('a', 'pedido-contador');
    await StockCatalogBackendService.orderSale('a', 'pedido-contador');
    expect(counter, 1);
  });
}

class _UnusedProductBox implements Box<Produto> {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected Hive access');
}
