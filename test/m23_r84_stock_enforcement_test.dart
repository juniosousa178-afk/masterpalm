// M2.3-R8.4 — conflict, pendências Q1–Q4, legado LEG1–LEG5, OFF3.

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_estoque_grade_snapshot.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/core/produto_stock_write_enforcement.dart';
import 'package:master_palm/models/produto.dart';

const _tamA = 'tam-a';
const _tamB = 'tam-b';

Map<String, dynamic> _remote({
  required int qA,
  required int qB,
  int revision = 0,
  String? operationId,
}) {
  return {
    'quantidade': qA + qB,
    'variacoes': {
      _tamA: {'sem-cor': qA},
      _tamB: {'sem-cor': qB},
    },
    'estoquePorTamanho': {_tamA: qA, _tamB: qB},
    kProdutoStockRevisionField: revision,
    if (operationId != null) kProdutoStockOperationIdField: operationId,
  };
}

Produto _local({
  required int qA,
  required int qB,
  int stockRevision = 0,
  String? pendingOp,
  int? pendingBase,
  String? stockSyncState,
}) {
  return Produto(
    nome: 'Prod R84',
    custoReal: 10,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 50,
    quantidade: qA + qB,
    precoUnitario: 50,
    categoria: 'Geral',
    dataEntrada: DateTime(2026, 1, 1),
    lojaId: 'loja-r84',
    idFirebase: 'prod-r84',
    variacoes: {
      _tamA: {'sem-cor': qA},
      _tamB: {'sem-cor': qB},
    },
    estoquePorTamanho: {_tamA: qA, _tamB: qB},
    stockRevision: stockRevision,
    pendingStockOperationId: pendingOp,
    pendingStockBaseRevision: pendingBase,
    stockSyncState: stockSyncState,
  );
}

void main() {
  group('OFF3 — conflito real', () {
    test('OFF3_STOCK_CONFLICT_GREEN', () {
      const opA = 'op-a-off3';
      const opB = 'op-b-off3';
      final local = _local(
        qA: 4,
        qB: 4,
        stockRevision: 5,
        pendingOp: opA,
        pendingBase: 5,
      );
      final remote = _remote(qA: 3, qB: 3, revision: 6, operationId: opB);

      expect(shouldMarkStockConflictOnPull(local: local, remoteData: remote),
          isTrue);

      final pull = evaluatePullStockMergeByRevision(
        local: local,
        remoteData: remote,
      );
      expect(pull, PullStockMergeDecision.preserveLocalGrade);

      markStockConflict(local, remoteOperationId: opB, remoteRevision: 6);
      expect(stockSyncStateOf(local), StockSyncState.conflict);

      final gradeBefore = ProdutoEstoqueGradeSnapshot.fromProduto(local);
      final afterPull = evaluatePullStockMergeByRevision(
        local: local,
        remoteData: remote,
      );
      expect(afterPull, PullStockMergeDecision.preserveLocalGrade);
      expect(
        ProdutoEstoqueGradeSnapshot.fromProduto(local).gradeDiffersFrom(
          gradeBefore,
        ),
        isFalse,
      );

      expect(
        evaluatePushStockSkipByRevision(local: local, existingData: remote),
        isTrue,
      );
    });
  });

  group('Q1–Q4 pendências', () {
    test('Q1 confirmação de A não encerra B', () {
      final local = _local(
        qA: 4,
        qB: 4,
        stockRevision: 5,
        pendingOp: 'op-a',
        pendingBase: 5,
      );
      final remoteConfirmA = _remote(
        qA: 3,
        qB: 4,
        revision: 6,
        operationId: 'op-a',
      );
      expect(
        tryConfirmStockFromRemote(local, remoteConfirmA),
        isTrue,
      );
      expect(local.pendingStockOperationId, isNull);

      markPendingStockMutation(local, operationId: 'op-b', baseRevision: 6);
      final remoteAt6 = _remote(
        qA: 3,
        qB: 4,
        revision: 6,
        operationId: 'op-a',
      );
      expect(
        shouldMarkStockConflictOnPull(local: local, remoteData: remoteAt6),
        isFalse,
      );
      expect(local.pendingStockOperationId, 'op-b');
    });

    test('Q2 servidor confirma B antes do readback de A', () {
      final local = _local(
        qA: 4,
        qB: 4,
        stockRevision: 5,
        pendingOp: 'op-a',
        pendingBase: 5,
      );
      final remoteB = _remote(qA: 2, qB: 4, revision: 7, operationId: 'op-b');
      expect(parseStockRevisionFromRemote(remoteB), 7);
      markStockConflict(local, remoteOperationId: 'op-b', remoteRevision: 7);
      expect(stockSyncStateOf(local), StockSyncState.conflict);
      expect(local.stockRevision, 5);
      expect(
        ProdutoEstoqueGradeSnapshot.fromProduto(local).cells[
            ProdutoEstoqueGradeSnapshot.variacaoId(_tamA)],
        4,
      );
    });

    test('Q3 retry de A após B confirmada é stale', () {
      final existing = _remote(qA: 2, qB: 4, revision: 7, operationId: 'op-b');
      expect(
        () => enforceStockRevisionWriteContract(
          updateData: {
            'quantidade': 8,
            'stockRevision': 6,
            'stockOperationId': 'op-a',
          },
          existingData: existing,
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

    test('Q4 restart preserva fila e IDs', () {
      final local = _local(
        qA: 4,
        qB: 4,
        stockRevision: 5,
        pendingOp: 'op-a',
        pendingBase: 5,
        stockSyncState: StockSyncState.conflict.name,
      );
      final reloaded = _local(
        qA: 4,
        qB: 4,
        stockRevision: local.stockRevision,
        pendingOp: local.pendingStockOperationId,
        pendingBase: local.pendingStockBaseRevision,
        stockSyncState: local.stockSyncState,
      );
      expect(stockSyncStateOf(reloaded), StockSyncState.conflict);
      expect(reloaded.pendingStockOperationId, 'op-a');
      expect(reloaded.pendingStockBaseRevision, 5);
    });
  });

  group('LEG1–LEG5 legado', () {
    test('LEG1 venda sem revision rejeitada', () {
      expect(
        () => enforceStockRevisionWriteContract(
          updateData: {'quantidade': 5},
          existingData: _remote(qA: 5, qB: 5, revision: 3, operationId: 'op0'),
          clientBuildNumber: 200,
        ),
        throwsA(
          isA<StockRevisionWriteRejectedException>().having(
            (e) => e.code,
            'code',
            'LEGACY_CLIENT_FORCED_UPDATE',
          ),
        ),
      );
    });

    test('LEG2 entrada legado rejeitada', () {
      expect(
        () => enforceStockRevisionWriteContract(
          updateData: {'quantidade': 20},
          existingData: _remote(qA: 10, qB: 10, revision: 1, operationId: 'op1'),
          writer: LegacyStockWriterKind.legacyApp,
        ),
        throwsA(
          isA<StockRevisionWriteRejectedException>().having(
            (e) => e.code,
            'code',
            'LEGACY_WRITER_BLOCKED',
          ),
        ),
      );
    });

    test('LEG3 cancelamento sem revision rejeitado', () {
      expect(
        () => enforceStockRevisionWriteContract(
          updateData: {
            'variacoes': {
              _tamA: {'sem-cor': 6},
            },
          },
          existingData: _remote(qA: 5, qB: 5, revision: 4, operationId: 'op4'),
          writer: LegacyStockWriterKind.legacyApp,
        ),
        throwsA(isA<StockRevisionWriteRejectedException>()),
      );
    });

    test('LEG4 documento legado sem revision — pull conservador', () {
      final local = _local(qA: 5, qB: 5, stockRevision: 2);
      final legacyRemote = {
        'quantidade': 20,
        'variacoes': {
          _tamA: {'sem-cor': 10},
          _tamB: {'sem-cor': 10},
        },
      };
      final decision = evaluatePullStockMergeByRevision(
        local: local,
        remoteData: legacyRemote,
      );
      expect(decision, PullStockMergeDecision.preserveLocalGrade);
    });

    test('LEG5 após migração revision não volta a null', () {
      final local = _local(qA: 5, qB: 5, stockRevision: 1);
      confirmStockMutation(local, operationId: 'op-mig', revision: 1);
      expect(local.stockRevision, 1);
      expect(local.pendingStockOperationId, isNull);
    });
  });
}
