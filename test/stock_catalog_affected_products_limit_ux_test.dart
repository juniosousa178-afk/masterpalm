import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/dart_error_unwrap.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/stock_catalog_affected_products.dart';
import 'package:master_palm/services/stock_catalog_backend_service.dart';
import 'package:master_palm/services/venda_edicao_estoque_diff.dart';

List<Map<String, dynamic>> _saleItems(int n, {int qty = -1}) => [
      for (var i = 0; i < n; i++)
        <String, dynamic>{'productId': 'p$i', 'quantidade': qty},
    ];

List<Map<String, dynamic>> _restockItems(int n) => [
      for (var i = 0; i < n; i++)
        <String, dynamic>{'productId': 'r$i', 'quantidade': 1},
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    EstoqueTransactionService.debugFirestoreOverride = null;
    StockCatalogBackendService.debugTransport = null;
  });

  tearDown(() {
    StockCatalogBackendService.debugTransport = null;
  });

  group('saved-sale edit size-limit precheck', () {
    test('1. 24 sale productIds -> pass', () {
      expect(
        () => StockCatalogAffectedProducts.assertCommandsWithinLimit(
          saleCount: 24,
          restockCount: 0,
        ),
        returnsNormally,
      );
      expect(
        StockCatalogAffectedProducts.distinctProductIdCount(_saleItems(24)),
        24,
      );
    });

    test('2. 25 sale productIds -> pass', () {
      expect(
        () => StockCatalogAffectedProducts.assertCommandsWithinLimit(
          saleCount: 25,
          restockCount: 0,
        ),
        returnsNormally,
      );
      expect(
        () => StockCatalogAffectedProducts.assertItemMapsWithinLimit(
          _saleItems(25),
        ),
        returnsNormally,
      );
    });

    test('3. 26 sale productIds -> local block', () {
      expect(
        () => StockCatalogAffectedProducts.assertCommandsWithinLimit(
          saleCount: 26,
          restockCount: 0,
        ),
        throwsA(isA<SavedSaleStockSizeLimitException>()),
      );
    });

    test('4. 26 restock productIds -> local block', () {
      expect(
        () => StockCatalogAffectedProducts.assertCommandsWithinLimit(
          saleCount: 0,
          restockCount: 26,
        ),
        throwsA(isA<SavedSaleStockSizeLimitException>()),
      );
      expect(
        () => StockCatalogAffectedProducts.assertSignedDeltaWithinLimit(
          _restockItems(26),
        ),
        throwsA(isA<SavedSaleStockSizeLimitException>()),
      );
    });

    test('5. 25 sale + 25 restock -> pass precheck', () {
      expect(
        () => StockCatalogAffectedProducts.assertCommandsWithinLimit(
          saleCount: 25,
          restockCount: 25,
        ),
        returnsNormally,
      );
      final signed = [..._saleItems(25), ..._restockItems(25)];
      expect(
        () => StockCatalogAffectedProducts.assertSignedDeltaWithinLimit(signed),
        returnsNormally,
      );
      final counts = StockCatalogAffectedProducts.countsFromSignedDelta(signed);
      expect(counts.sale, 25);
      expect(counts.restock, 25);
    });

    test('6. 5 sale + 26 restock -> entire edit blocked before dispatch',
        () async {
      var calls = 0;
      StockCatalogBackendService.debugTransport = (_, __) async {
        calls++;
        return {'alreadyApplied': false, 'products': <dynamic>[]};
      };
      final signed = [..._saleItems(5), ..._restockItems(26)];
      await expectLater(
        EstoqueTransactionService.reconciliarEdicaoEstoqueTransactionBatch(
          lojaId: 'loja-limit-ux',
          itensAssinados: signed,
          operationId: 'op-mixed-restock',
          deltaHash: 'hash-mixed-restock',
        ),
        throwsA(isA<SavedSaleStockSizeLimitException>()),
      );
      expect(calls, 0);
    });

    test('7. 26 sale + 5 restock -> entire edit blocked before dispatch',
        () async {
      var calls = 0;
      StockCatalogBackendService.debugTransport = (_, __) async {
        calls++;
        return {'alreadyApplied': false, 'products': <dynamic>[]};
      };
      final signed = [..._saleItems(26), ..._restockItems(5)];
      await expectLater(
        EstoqueTransactionService.reconciliarEdicaoEstoqueTransactionBatch(
          lojaId: 'loja-limit-ux',
          itensAssinados: signed,
          operationId: 'op-mixed-sale',
          deltaHash: 'hash-mixed-sale',
        ),
        throwsA(isA<SavedSaleStockSizeLimitException>()),
      );
      expect(calls, 0);
    });

    test('8. P/M/G same product -> count 1', () {
      final items = [
        {'productId': 'anel', 'size': 'P', 'quantity': 1},
        {'productId': 'anel', 'size': 'M', 'quantity': 1},
        {'productId': 'anel', 'size': 'G', 'quantity': 1},
      ];
      expect(StockCatalogAffectedProducts.distinctProductIdCount(items), 1);
      expect(
        () => StockCatalogAffectedProducts.assertItemMapsWithinLimit(items),
        returnsNormally,
      );
    });

    test('9. duplicate lines same product -> count 1', () {
      final items = [
        {'productId': 'p1', 'quantity': 2},
        {'productId': 'p1', 'quantity': 1},
        {'productId': 'p1', 'quantity': 4},
      ];
      expect(StockCatalogAffectedProducts.distinctProductIdCount(items), 1);
    });

    test('10. large original sale + one-product delta -> pass', () {
      final antigas = [
        for (var i = 0; i < 30; i++)
          <String, dynamic>{
            'productId': 'orig$i',
            'nome': 'N$i',
            'quantidade': 1,
            'tamanho': '',
            'cor': '',
          },
      ];
      final novas = [
        for (final m in antigas) Map<String, dynamic>.from(m),
      ];
      novas[0] = {...novas[0], 'quantidade': 2};
      final delta = VendaEdicaoEstoqueDiff.calcularDelta(
        linhasAntigas: antigas,
        linhasNovas: novas,
      );
      final signed = VendaEdicaoEstoqueDiff.linhasAssinadasCanonicas(delta);
      final counts = StockCatalogAffectedProducts.countsFromSignedDelta(signed);
      expect(counts.sale, 1);
      expect(counts.restock, 0);
      expect(
        () => StockCatalogAffectedProducts.assertSignedDeltaWithinLimit(signed),
        returnsNormally,
      );
    });

    test('11. over-limit -> zero business network requests', () async {
      var calls = 0;
      StockCatalogBackendService.debugTransport = (_, __) async {
        calls++;
        return {'alreadyApplied': false, 'products': <dynamic>[]};
      };
      await expectLater(
        EstoqueTransactionService.reconciliarEdicaoEstoqueTransactionBatch(
          lojaId: 'loja-limit-ux',
          itensAssinados: _saleItems(26),
          operationId: 'op-over',
          deltaHash: 'hash-over',
        ),
        throwsA(isA<SavedSaleStockSizeLimitException>()),
      );
      expect(calls, 0);
    });

    test('12. resource-exhausted backend fallback -> PT-BR limit UX', () {
      final err = FirebaseFunctionsException(
        code: 'resource-exhausted',
        message: 'Too many affected products',
      );
      final msg = formatSalvarVendaErrorForUser(err);
      expect(msg, contains('limite atual é de 25 produtos'));
      expect(msg, contains('A venda original não foi alterada.'));
      expect(msg, contains('Revise a alteração ou cancele a edição.'));
      expect(msg.toLowerCase(), isNot(contains('internet')));
      expect(msg.toLowerCase(), isNot(contains('tente novamente')));
      expect(msg, isNot(contains('Too many affected products')));
      expect(
        StockCatalogAffectedProducts.isLimitUserMessage(msg),
        isTrue,
      );
    });

    test('13. resource-exhausted -> no automatic retry', () async {
      var calls = 0;
      StockCatalogBackendService.debugTransport = (_, __) async {
        calls++;
        throw FirebaseFunctionsException(
          code: 'resource-exhausted',
          message: 'Too many affected products',
        );
      };
      await expectLater(
        StockCatalogBackendService.command(
          lojaId: 'loja-limit-ux',
          operationId: 'sale-limit',
          kind: 'sale',
          items: [
            {'productId': 'p', 'quantity': 1},
          ],
        ),
        throwsA(isA<FirebaseFunctionsException>()),
      );
      expect(calls, 1);
    });

    test('14. over-limit -> no queue enqueue', () {
      final vendas = File('lib/services/vendas_service.dart').readAsStringSync();
      final editStart = vendas.indexOf('static Future<Venda> editarVendaMulti');
      expect(editStart, greaterThan(-1));
      final editSlice = vendas.substring(editStart, editStart + 18000);
      final assertAt = editSlice.indexOf(
        'StockCatalogAffectedProducts.assertSignedDeltaWithinLimit',
      );
      final saveAt = editSlice.indexOf('await venda.save()');
      final syncAt = editSlice.indexOf('_agendarSyncRemotoAposEdicaoLocal');
      final prepAt = editSlice.indexOf('garantirProdutosProntosParaBaixa');
      expect(assertAt, greaterThan(-1));
      expect(saveAt, greaterThan(assertAt));
      expect(syncAt, greaterThan(assertAt));
      expect(prepAt, greaterThan(assertAt));
      expect(editSlice.contains('SyncQueueService.enqueue'), isFalse);
    });

    test('15. valid <=25 edit path preserved', () {
      expect(
        () => StockCatalogAffectedProducts.assertSignedDeltaWithinLimit(
          _saleItems(1),
        ),
        returnsNormally,
      );
      expect(
        () => StockCatalogAffectedProducts.assertCommandsWithinLimit(
          saleCount: 1,
          restockCount: 1,
        ),
        returnsNormally,
      );
      final vendas = File('lib/services/vendas_service.dart').readAsStringSync();
      expect(vendas.contains('VendaEdicaoEstoqueDiff.calcularDelta'), isTrue);
      expect(
        vendas.contains('reconciliarEdicaoEstoqueTransactionBatch'),
        isTrue,
      );
    });
  });

  group('count semantics', () {
    test('empty command count is 0 and does not throw', () {
      expect(StockCatalogAffectedProducts.distinctProductIdCount(const []), 0);
      expect(
        StockCatalogAffectedProducts.countsFromSignedDelta(const []),
        (sale: 0, restock: 0),
      );
      expect(
        () => StockCatalogAffectedProducts.assertSignedDeltaWithinLimit(
          const [],
        ),
        returnsNormally,
      );
    });

    test('same productId in sale and restock counts once per command', () {
      final signed = [
        {'productId': 'p1', 'quantidade': -2},
        {'productId': 'p1', 'quantidade': 1},
      ];
      final counts = StockCatalogAffectedProducts.countsFromSignedDelta(signed);
      expect(counts.sale, 1);
      expect(counts.restock, 1);
      expect(
        () => StockCatalogAffectedProducts.assertSignedDeltaWithinLimit(signed),
        returnsNormally,
      );
    });

    test('simple products count by distinct productId', () {
      final items = [
        for (var i = 0; i < 10; i++)
          {'productId': 'simple$i', 'quantity': 1},
      ];
      expect(StockCatalogAffectedProducts.distinctProductIdCount(items), 10);
    });

    test('blank productId is ignored', () {
      expect(
        StockCatalogAffectedProducts.distinctProductIdCount([
          {'productId': ' ', 'quantity': 1},
          {'productId': '', 'quantity': 1},
          {'productId': 'p1', 'quantity': 1},
        ]),
        1,
      );
    });
  });

  group('UX mapping', () {
    test('single over-limit command shows its exact count', () {
      const err = SavedSaleStockSizeLimitException(
        saleCount: 31,
        restockCount: 5,
      );
      expect(err.userTitle, 'Não foi possível salvar a alteração');
      expect(err.userMessage, contains('31 produtos'));
      expect(err.userMessage, isNot(contains('Saída:')));
      expect(err.userMessage, contains('A venda original não foi alterada.'));
      expect(
        formatSalvarVendaErrorForUser(err),
        err.userMessage,
      );
    });

    test('both over-limit commands show independent counts without union', () {
      const err = SavedSaleStockSizeLimitException(
        saleCount: 31,
        restockCount: 28,
      );
      expect(err.userMessage, contains('Saída: 31 produtos'));
      expect(err.userMessage, contains('devolução: 28 produtos'));
      expect(err.userMessage, isNot(contains('59')));
    });

    test('limit error is not a connection error', () {
      final msg = formatSalvarVendaErrorForUser(
        const SavedSaleStockSizeLimitException(
          saleCount: 26,
          restockCount: 0,
        ),
      );
      expect(msg.toLowerCase(), isNot(contains('internet')));
      expect(msg.toLowerCase(), isNot(contains('conexão')));
      expect(msg.toLowerCase(), isNot(contains('conexao')));
    });
  });

  group('source contracts', () {
    test('precheck sits after delta and before business writes', () {
      final vendas = File('lib/services/vendas_service.dart').readAsStringSync();
      final aplicar = File('lib/services/vendas_service.dart')
          .readAsStringSync()
          .split('static Future<String?> _aplicarDeltaEstoqueEdicaoVenda')[1]
          .split('static Future<Venda> editarVendaMulti')[0];
      expect(
        aplicar.contains(
          'StockCatalogAffectedProducts.assertSignedDeltaWithinLimit',
        ),
        isTrue,
      );
      expect(
        aplicar.indexOf('assertSignedDeltaWithinLimit') <
            aplicar.indexOf('VendaOperationJournalService.reserveOrRecover'),
        isTrue,
      );

      final edit = vendas.split('static Future<Venda> editarVendaMulti')[1];
      final deltaAt = edit.indexOf('VendaEdicaoEstoqueDiff.calcularDelta');
      final assertAt = edit.indexOf(
        'StockCatalogAffectedProducts.assertSignedDeltaWithinLimit',
      );
      final prepAt = edit.indexOf('garantirProdutosProntosParaBaixa');
      final applyAt = edit.indexOf('_aplicarDeltaEstoqueEdicaoVenda');
      expect(deltaAt, greaterThan(-1));
      expect(assertAt, greaterThan(deltaAt));
      expect(prepAt, greaterThan(assertAt));
      expect(applyAt, greaterThan(assertAt));
    });

    test('reconcile validates both commands before first command()', () {
      final src =
          File('lib/services/estoque_transaction_service.dart').readAsStringSync();
      final fn = src.split(
        'reconciliarEdicaoEstoqueTransactionBatch({',
      )[1];
      final assertSigned = fn.indexOf('assertSignedDeltaWithinLimit');
      final assertCmds = fn.indexOf('assertCommandsWithinLimit');
      final saleCmd = fn.indexOf("kind: 'sale'");
      final restockCmd = fn.indexOf("kind: 'restock'");
      expect(assertSigned, greaterThan(-1));
      expect(assertCmds, greaterThan(assertSigned));
      expect(saleCmd, greaterThan(assertCmds));
      expect(restockCmd, greaterThan(assertCmds));
    });

    test('client chunking was not added', () {
      for (final path in [
        'lib/services/stock_catalog_affected_products.dart',
        'lib/services/estoque_transaction_service.dart',
        'lib/services/vendas_service.dart',
        'lib/services/stock_catalog_backend_service.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(src.contains('chunk'), isFalse, reason: path);
        expect(src.contains('sublist(0, 25)'), isFalse, reason: path);
        expect(src.contains('MAX_PRODUCTS +'), isFalse, reason: path);
      }
    });

    test('backend MAX_PRODUCTS remains 25', () {
      final src =
          File('functions/src/stockCatalogCommands.js').readAsStringSync();
      expect(src.contains('const MAX_PRODUCTS = 25;'), isTrue);
    });

    test('nova venda uses dedicated limit title', () {
      final src = File('lib/screens/nova_venda_modal.dart').readAsStringSync();
      expect(src.contains('StockCatalogAffectedProducts.userTitle'), isTrue);
      expect(
        src.contains('SAVED_SALE_EDIT_SIZE_LIMIT') ||
            src.contains('StockCatalogAffectedProducts.errorCategory'),
        isTrue,
      );
    });
  });
}
