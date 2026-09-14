// Integration of the production Flutter adapter with a deterministic callable transport.
// Real Firestore transactions are separately covered by functions/test/stock-catalog-commands.test.mjs.
import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/estoque_service.dart';
import 'package:master_palm/services/stock_catalog_backend_service.dart';
import 'package:master_palm/services/venda_combo_estoque_expansion.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Box<Produto> box;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('stock_backend_hive_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
    box = await Hive.openBox<Produto>('products');
  });
  setUp(() async {
    await box.clear();
    EstoqueTransactionService.debugFirestoreOverride = null;
  });
  tearDown(() {
    StockCatalogBackendService.debugTransport = null;
  });
  tearDownAll(() async {
    await box.close();
    await dir.delete(recursive: true);
  });
  Map<String, dynamic> response(
          {int revision = 1, int units = 0, bool replay = false}) =>
      {
        'alreadyApplied': replay,
        'operationId': 'sale',
        'products': [
          {
            'productId': 'p',
            'quantidade': units,
            'stockRevision': revision,
            'stockOperationId': 'sale',
            'variacoes': {
              'P': {'Azul': units}
            },
            'estoquePorTamanho': {'P': units},
            'estoquePorCor': <String, int>{}
          },
        ],
      };
  Produto product({int revision = 0, int units = 1}) => Produto.vazio()
    ..idFirebase = 'p'
    ..nome = 'Peça'
    ..lojaId = 'a'
    ..quantidade = units
    ..stockRevision = revision;

  test(
      'production sale adapter sends roots only and hydrates confirmed canonical response',
      () async {
    final p = product();
    await box.add(p);
    final item = VendaItem(
        produtoNome: 'Peça',
        quantidade: 1,
        precoUnitario: 10,
        tamanho: 'P',
        cor: ' Azul ',
        lojaId: 'a');
    final roots = VendaComboEstoqueExpansion.montarItensParaBackend(
        itens: [item], produtos: [p]);
    StockCatalogBackendService.debugTransport = (name, data) async {
      expect(name, 'stockCatalogCommand');
      expect(data['operationId'], 'sale');
      expect(data['items'], roots);
      expect((data['items'] as List).length, 1);
      expect(data.containsKey('stockRevision'), false);
      return response();
    };
    final result = await EstoqueTransactionService
        .baixarEstoqueTransactionBatchIdempotente(
            lojaId: 'a',
            itens: [
              {'productId': 'untrusted-expanded-child', 'quantidade': 99}
            ],
            operationId: 'sale',
            backendItems: roots);
    expect(result.baixaAplicadaNestaExecucao, true);
    await EstoqueTransactionService.atualizarHiveAposTransacao(
        produtosBox: box,
        lojaId: 'a',
        result: result.transactionResults.single);
    expect(p.quantidade, 0);
    expect(p.stockRevision, 1);
    expect(p.variacoes!['P']['Azul'], 0);
    expect(hasPendingStockMutation(p), false);
  });
  test('late response cannot replace a newer Hive revision', () async {
    final p = product(revision: 3, units: 5);
    await box.add(p);
    final result =
        EstoqueTransactionService.resultadosDoBackend(response()).single;
    await EstoqueTransactionService.atualizarHiveAposTransacao(
        produtosBox: box, lojaId: 'a', result: result);
    expect(p.quantidade, 5);
    expect(p.stockRevision, 3);
  });
  test('unrelated pending count remains intact and becomes conflict', () async {
    final p = product(units: 4);
    markPendingStockMutation(p, operationId: 'count');
    await box.add(p);
    final result =
        EstoqueTransactionService.resultadosDoBackend(response()).single;
    await EstoqueTransactionService.atualizarHiveAposTransacao(
        produtosBox: box, lojaId: 'a', result: result);
    expect(p.quantidade, 4);
    expect(p.pendingStockOperationId, 'count');
    expect(stockSyncStateOf(p), StockSyncState.conflict);
  });
  test(
      'permission denial never falls back to direct Firestore or Hive decrement',
      () async {
    final p = product();
    await box.add(p);
    StockCatalogBackendService.debugTransport = (_, data) async =>
        throw FirebaseFunctionsException(
            code: 'permission-denied', message: 'Grant absent');
    await expectLater(
        EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
            lojaId: 'a',
            itens: [],
            operationId: 'sale',
            backendItems: [
              {'productId': 'p', 'quantity': 1}
            ]),
        throwsA(isA<FirebaseFunctionsException>()));
    expect(p.quantidade, 1);
    expect(p.stockRevision, 0);
  });
  test(
      'restore sends original operation identity, never a client-provided quantity',
      () async {
    StockCatalogBackendService.debugTransport = (name, data) async {
      expect(data['kind'], 'restore');
      expect(data['sourceOperationId'], 'sale');
      expect(data['items'], [
        {'productId': 'source-operation'}
      ]);
      return response(revision: 2, units: 1);
    };
    final r = await EstoqueTransactionService.devolverEstoqueTransactionBatch(
        lojaId: 'a',
        itens: [
          {'productId': 'p', 'quantidade': 999}
        ],
        vendaIdParaIdempotencia: 'sale');
    expect(r.single.quantidadeTotalAtualizada, 1);
  });
  test(
      'canonical color extras hydrate sem-tamanho without duplicating grade color aliases',
      () {
    final raw = response(units: 2);
    final row = (raw['products'] as List).single as Map;
    row['quantidade'] = 3;
    row['estoquePorCor'] = {'azul': 99, 'Verde': 1};
    final r = EstoqueTransactionService.resultadosDoBackend(raw).single;
    expect(r.variacoesAtualizadas!['sem-tamanho'], {'Verde': 1});
    expect(r.variacoesAtualizadas!['P'], {'Azul': 2});
  });
  test(
      'manual absolute adjustment persists identity before sending and confirms server revision',
      () async {
    final p = product(units: 5);
    await box.add(p);
    String? operationId;
    StockCatalogBackendService.debugTransport = (_, data) async {
      operationId = data['operationId'] as String;
      expect(p.pendingStockOperationId, operationId);
      expect((data['items'] as List).single['expectedRevision'], 0);
      expect((data['definition'] as Map)['quantidade'], 5);
      final r = response(revision: 1, units: 5);
      r['operationId'] = operationId;
      ((r['products'] as List).single as Map)['stockOperationId'] = operationId;
      return r;
    };
    expect(await EstoqueService.sincronizarAjusteManual(p, 'a'),
        ResultadoAjusteEstoque.sucesso);
    expect(p.stockRevision, 1);
    expect(p.pendingStockOperationId, null);
    expect(p.confirmedStockOperationId, operationId);
  });
  test(
      'failed manual adjustment retains the same identity and base revision on retry',
      () async {
    final p = product(units: 5);
    await box.add(p);
    final ids = <String>[];
    StockCatalogBackendService.debugTransport = (_, data) async {
      ids.add(data['operationId'] as String);
      expect((data['items'] as List).single['expectedRevision'], 0);
      throw FirebaseFunctionsException(
          code: 'permission-denied', message: 'No grant');
    };
    expect(await EstoqueService.sincronizarAjusteManual(p, 'a'),
        ResultadoAjusteEstoque.erro);
    expect(await EstoqueService.sincronizarAjusteManual(p, 'a'),
        ResultadoAjusteEstoque.erro);
    expect(ids.toSet().length, 1);
    expect(p.pendingStockOperationId, ids.first);
    expect(p.stockRevision, 0);
  });
  test(
      'failed purchase entry is not reported as confirmed and cannot be added twice',
      () async {
    final p = product();
    await box.add(p);
    StockCatalogBackendService.debugTransport = (_, data) async =>
        throw FirebaseFunctionsException(
            code: 'permission-denied', message: 'No grant');
    Future<EstoqueResult> enter() => EstoqueService.atualizarEstoque(
        produtosBox: box,
        lojaId: 'a',
        produtoId: 'p',
        tamanho: '',
        cor: '',
        quantidade: 2,
        operacao: 'entrada_compra');
    final first = await enter();
    expect(first.sucesso, false);
    expect(p.quantidade, 3);
    expect(hasPendingStockMutation(p), true);
    final second = await enter();
    expect(second.sucesso, false);
    expect(p.quantidade, 3);
  });

  test(
      'persisted order adapter sends only store/order IDs and hydrates server replay',
      () async {
    final p = product();
    await box.add(p);
    StockCatalogBackendService.debugTransport = (name, data) async {
      expect(name, 'stockCatalogOrderSale');
      expect(data, {'lojaId': 'a', 'orderId': 'pedido-original'});
      return response(replay: true);
    };
    final results = await EstoqueTransactionService.baixarEstoquePedido(
        lojaId: 'a', pedidoId: 'pedido-original');
    expect(results.single.confirmadoPeloBackend, true);
    await EstoqueTransactionService.atualizarHiveAposTransacao(
        produtosBox: box, lojaId: 'a', result: results.single);
    expect(p.quantidade, 0);
    expect(p.stockRevision, 1);
  });
  test('MANUAL_WEBHOOK_SHARED_OPERATION_ID uses backend order identity',
      () async {
    final expected = 'order_${sha256.convert(utf8.encode('pedido-original'))}';
    expect(EstoqueTransactionService.orderSaleOperationId('pedido-original'),
        expected);
    StockCatalogBackendService.debugTransport = (name, data) async {
      expect(name, 'stockCatalogOrderSale');
      expect(data, {'lojaId': 'a', 'orderId': 'pedido-original'});
      final r = response(revision: 2, units: 3);
      r['operationId'] = expected;
      ((r['products'] as List).single as Map)['stockOperationId'] = expected;
      return r;
    };
    final result =
        await EstoqueTransactionService.baixarEstoquePedidoIdempotente(
      lojaId: 'a',
      pedidoId: 'pedido-original',
    );
    expect(result.baixaAplicadaNestaExecucao, isTrue);
    expect(result.transactionResults.single.stockOperationId, expected);
  });
  test('persisted order replay has no double stock decrement', () async {
    var remoteUnits = 5;
    final appliedOps = <String>{};
    StockCatalogBackendService.debugTransport = (_, data) async {
      final op = EstoqueTransactionService.orderSaleOperationId(
          data['orderId'] as String);
      final firstApply = appliedOps.add(op);
      if (firstApply) remoteUnits--;
      final r = response(replay: !firstApply, units: remoteUnits);
      r['operationId'] = op;
      ((r['products'] as List).single as Map)['stockOperationId'] = op;
      return r;
    };
    final first =
        await EstoqueTransactionService.baixarEstoquePedidoIdempotente(
      lojaId: 'a',
      pedidoId: 'pedido-replay',
    );
    final second =
        await EstoqueTransactionService.baixarEstoquePedidoIdempotente(
      lojaId: 'a',
      pedidoId: 'pedido-replay',
    );
    expect(first.baixaAplicadaNestaExecucao, isTrue);
    expect(second.baixaJaAplicadaAnteriormente, isTrue);
    expect(remoteUnits, 4);
  });
  test('LOCAL_FAILURE_CAN_RESTORE_PAID_ORDER_STOCK=false', () {
    final src = File('lib/services/vendas_service.dart').readAsStringSync();
    expect(src, contains('baixarEstoquePedidoIdempotente'));
    expect(
      src,
      contains(
          '!usaPedidoPersistidoBackend && baixaOp.baixaAplicadaNestaExecucao'),
    );
  });
  test('backend pos-pagamento does not write legacy stock markers', () {
    final src =
        File('lib/services/pos_pagamento_service.dart').readAsStringSync();
    expect(src, contains('usarMarcadorLegado'));
    expect(src, contains('debugFirestoreOverride != null'));
    expect(src, contains('baixarEstoqueTransactionBatchIdempotente'));
    expect(src, contains('pos_pagamento_\${sha256.convert'));
  });
  test(
      'persisted order denial leaves Hive unchanged and propagates without direct fallback',
      () async {
    final p = product();
    await box.add(p);
    StockCatalogBackendService.debugTransport = (_, data) async =>
        throw FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'Order reconciliation required');
    await expectLater(
        EstoqueTransactionService.baixarEstoquePedido(
            lojaId: 'a', pedidoId: 'old-order'),
        throwsA(isA<FirebaseFunctionsException>()));
    expect(p.quantidade, 1);
    expect(p.stockRevision, 0);
  });
}
