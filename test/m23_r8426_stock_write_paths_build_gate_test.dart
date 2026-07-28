// M2.3-R8.4.26 — caminhos de escrita bloqueados/permitidos por build.

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_stock_write_enforcement.dart';
import 'package:master_palm/core/stock_revision_client_build_resolver.dart';
import 'package:master_palm/core/stock_revision_operation_gate.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/venda_estoque_remoto_prep_service.dart';

import 'support/stock_revision_client_build_test_support.dart';

void main() {
  tearDown(() {
    resetStockClientBuildForTest();
    StockRevisionOperationGate.resetDebugOverrides();
  });

  final existingRemote = {
    'quantidade': 10,
    'stockRevision': 1,
    'stockOperationId': 'op-base',
  };

  void expectBlockedAt95(StockRevisionOperationKind kind) {
    initializeCompatibleStockClientBuildForTest(95);
    expect(
      () => StockRevisionOperationGate.assertAllowed(kind),
      throwsA(isA<StockRevisionUpdateRequiredException>()),
    );
  }

  void expectAllowedAt285(StockRevisionOperationKind kind) {
    initializeCompatibleStockClientBuildForTest(285);
    expect(
      () => StockRevisionOperationGate.assertAllowed(kind),
      returnsNormally,
    );
  }

  group('R8426 gate por operação — build 95 bloqueado', () {
    for (final kind in StockRevisionOperationKind.values) {
      test('bloqueia ${kind.name}', () {
        expectBlockedAt95(kind);
      });
    }
  });

  group('R8426 gate por operação — build 285 permitido', () {
    for (final kind in StockRevisionOperationKind.values) {
      test('permite ${kind.name}', () {
        expectAllowedAt285(kind);
      });
    }
  });

  group('R8426 serviços — build 95 bloqueado', () {
    test('venda prep service', () async {
      initializeCompatibleStockClientBuildForTest(95);
      final p = Produto.vazio()..lojaId = 'loja-r8426';
      await expectLater(
        VendaEstoqueRemotoPrepService.garantirProdutosProntosParaBaixa(
          lojaId: 'loja-r8426',
          produtos: [p],
        ),
        throwsA(isA<StockRevisionUpdateRequiredException>()),
      );
    });

    test('combo transaction batch', () async {
      initializeCompatibleStockClientBuildForTest(95);
      await expectLater(
        EstoqueTransactionService.baixarEstoqueTransactionBatch(
          lojaId: 'loja-r8426',
          itens: const [
            {'productId': 'p1', 'quantidade': 1},
          ],
        ),
        throwsA(isA<StockRevisionUpdateRequiredException>()),
      );
    });

    test('devolução transaction batch', () async {
      initializeCompatibleStockClientBuildForTest(95);
      await expectLater(
        EstoqueTransactionService.devolverEstoqueTransactionBatch(
          lojaId: 'loja-r8426',
          itens: const [
            {'productId': 'p1', 'quantidade': 1},
          ],
          estornoOrigemCatalogo: 'cancelamento',
        ),
        throwsA(isA<StockRevisionUpdateRequiredException>()),
      );
    });

    test('enforce write contract', () {
      initializeCompatibleStockClientBuildForTest(95);
      expect(
        () => enforceStockRevisionWriteContract(
          updateData: {
            'quantidade': 8,
            'stockRevision': 2,
            'stockOperationId': 'op-r8426',
          },
          existingData: existingRemote,
        ),
        throwsA(isA<StockRevisionWriteRejectedException>()),
      );
    });
  });

  group('R8426 serviços — build 285 permitido no gate', () {
    test('venda prep não lança UPDATE_REQUIRED por build', () async {
      initializeCompatibleStockClientBuildForTest(285);
      expect(
        () => StockRevisionOperationGate.assertAllowed(
          StockRevisionOperationKind.venda,
        ),
        returnsNormally,
      );
    });

    test('enforce write contract com revision válida', () {
      initializeCompatibleStockClientBuildForTest(285);
      expect(
        () => enforceStockRevisionWriteContract(
          updateData: {
            'quantidade': 8,
            'stockRevision': 2,
            'stockOperationId': 'op-r8426-ok',
          },
          existingData: existingRemote,
        ),
        returnsNormally,
      );
    });
  });

  group('R8426 fail-closed antes da inicialização', () {
    test('venda bloqueada sem resolver inicializado', () {
      resetStockClientBuildForTest();
      expect(
        () => StockRevisionOperationGate.assertAllowed(
          StockRevisionOperationKind.venda,
        ),
        throwsA(isA<StockRevisionClientBuildUnavailableException>()),
      );
    });
  });
}
