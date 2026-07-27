// M2.3-R8.4.1 — preflight legado, cadastro/importação, combo atômico.

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/core/produto_stock_write_enforcement.dart';
import 'package:master_palm/core/stock_revision_client_build_resolver.dart';
import 'package:master_palm/core/stock_revision_operation_gate.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/venda_estoque_remoto_prep_service.dart';

void main() {
  tearDown(StockRevisionOperationGate.resetDebugOverrides);

  group('LEG-A — bloqueio antes de escrita', () {
    test('LEG-A1 venda antiga bloqueada no prep remoto', () async {
      StockRevisionOperationGate.debugClientBuildNumberOverride = 100;
      final p = Produto.vazio()..lojaId = 'loja-a1';
      await expectLater(
        VendaEstoqueRemotoPrepService.garantirProdutosProntosParaBaixa(
          lojaId: 'loja-a1',
          produtos: [p],
        ),
        throwsA(
          isA<StockRevisionUpdateRequiredException>().having(
            (e) => e.code,
            'code',
            StockRevisionUpdateRequiredException.updateRequiredCode,
          ),
        ),
      );
    });

    test('LEG-A2 cancelamento antigo bloqueado no devolver batch', () async {
      StockRevisionClientBuildResolver.instance.setTestOverride(285);
      StockRevisionOperationGate.debugWriterKindOverride =
          LegacyStockWriterKind.legacyApp;
      await expectLater(
        EstoqueTransactionService.devolverEstoqueTransactionBatch(
          lojaId: 'loja-a2',
          itens: const [
            {'productId': 'p1', 'quantidade': 1},
          ],
          estornoOrigemCatalogo: 'cancelamento',
        ),
        throwsA(isA<StockRevisionUpdateRequiredException>()),
      );
    });

    test('LEG-A3 exclusão antiga bloqueada no devolver batch', () async {
      StockRevisionClientBuildResolver.instance.setTestOverride(285);
      StockRevisionOperationGate.debugWriterKindOverride =
          LegacyStockWriterKind.legacyApp;
      await expectLater(
        EstoqueTransactionService.devolverEstoqueTransactionBatch(
          lojaId: 'loja-a3',
          itens: const [
            {'productId': 'p1', 'quantidade': 1},
          ],
          estornoOrigemCatalogo: 'venda_delete',
        ),
        throwsA(isA<StockRevisionUpdateRequiredException>()),
      );
    });

    test('LEG-A4 entrada antiga bloqueada antes de escrita', () {
      StockRevisionOperationGate.debugClientBuildNumberOverride = 50;
      expect(
        () => StockRevisionOperationGate.assertAllowed(
          StockRevisionOperationKind.entradaManual,
        ),
        throwsA(
          isA<StockRevisionUpdateRequiredException>().having(
            (e) => e.code,
            'code',
            StockRevisionUpdateRequiredException.updateRequiredCode,
          ),
        ),
      );
    });

    test('LEG-A5 combo antigo bloqueado no batch', () async {
      StockRevisionOperationGate.debugClientBuildNumberOverride = 1;
      await expectLater(
        EstoqueTransactionService.baixarEstoqueTransactionBatch(
          lojaId: 'loja-a5',
          itens: const [
            {'productId': 'c1', 'quantidade': 1},
            {'productId': 'c2', 'quantidade': 1},
          ],
        ),
        throwsA(isA<StockRevisionUpdateRequiredException>()),
      );
    });
  });

  group('CI — cadastro/importação contrato', () {
    setUp(() {
      StockRevisionClientBuildResolver.instance.setTestOverride(285);
    });

    test('CI1 create com grade exige revision fields', () {
      final payload = {
        'quantidade': 5,
        'stockRevision': 1,
        'stockOperationId': 'op-ci1',
      };
      expect(
        () => enforceStockRevisionWriteContract(
          updateData: payload,
          existingData: null,
        ),
        returnsNormally,
      );
    });

    test('CI2 create sem revision rejeitado', () {
      expect(
        () => enforceStockRevisionWriteContract(
          updateData: {'quantidade': 5},
          existingData: null,
        ),
        throwsA(isA<StockRevisionWriteRejectedException>()),
      );
    });

    test('CI3 import com revision válida', () {
      expect(
        () => enforceStockRevisionWriteContract(
          updateData: {
            'quantidade': 10,
            'stockRevision': 2,
            'stockOperationId': 'op-ci3',
          },
          existingData: {
            'quantidade': 5,
            'stockRevision': 1,
            'stockOperationId': 'op-prev',
          },
        ),
        returnsNormally,
      );
    });

    test('CI4 import stale revision rejeitado', () {
      expect(
        () => enforceStockRevisionWriteContract(
          updateData: {
            'quantidade': 10,
            'stockRevision': 1,
            'stockOperationId': 'op-stale',
          },
          existingData: {
            'quantidade': 5,
            'stockRevision': 3,
            'stockOperationId': 'op-remote',
          },
        ),
        throwsA(
          isA<StockRevisionWriteRejectedException>().having(
            (e) => e.code,
            'code',
            'REVISION_REGRESSION',
          ),
        ),
      );
    });

    test('CI5 linha inválida não passa contrato silenciosamente', () {
      expect(
        () => enforceStockRevisionWriteContract(
          updateData: {'quantidade': 1},
          existingData: {
            'quantidade': 5,
            'stockRevision': 2,
            'stockOperationId': 'op2',
          },
        ),
        throwsA(isA<StockRevisionWriteRejectedException>()),
      );
    });
  });
}
