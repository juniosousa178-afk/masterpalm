// SALE_STOCK_REGRESSION_002 — monotonic revision hardening (synthetic only).

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_estoque_grade_snapshot.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/core/produto_stock_write_enforcement.dart';
import 'package:master_palm/models/produto.dart';

const _loja = 'loja-reg002';
const _prod = 'prod-reg002';

Map<String, dynamic> _remoteGrade({
  required int qty,
  int revision = 0,
  String operationId = 'op-remote',
}) {
  return {
    'quantidade': qty,
    'variacoes': {},
    'estoquePorTamanho': {},
    kProdutoStockRevisionField: revision,
    kProdutoStockOperationIdField: operationId,
  };
}

Map<String, dynamic> _writePayload({
  required int qty,
  required int revision,
  required String operationId,
}) {
  return {
    'quantidade': qty,
    kProdutoStockRevisionField: revision,
    kProdutoStockOperationIdField: operationId,
  };
}

Produto _localProduto({
  required int qty,
  int stockRevision = 0,
  String? pendingOp,
  int? pendingBase,
}) {
  return Produto(
    nome: 'Prod REG002',
    custoReal: 1,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 10,
    quantidade: qty,
    precoUnitario: 10,
    categoria: 'Geral',
    dataEntrada: DateTime(2026, 1, 1),
    lojaId: _loja,
    idFirebase: _prod,
    stockRevision: stockRevision,
    pendingStockOperationId: pendingOp,
    pendingStockBaseRevision: pendingBase,
  );
}

void main() {
  group('S1 — sale decrement contract (10 → 9, rev N → N+1)', () {
    test('S1_DECREMENT_TEST_PRESENT valid +1 revision accepted', () {
      const prevRev = 8;
      const nextRev = 9;
      final existing = _remoteGrade(
        qty: 10,
        revision: prevRev,
        operationId: 'op-base',
      );
      final update = _writePayload(
        qty: 9,
        revision: nextRev,
        operationId: 'op-sale',
      );

      expect(
        () => enforceStockRevisionWriteContract(
          updateData: update,
          existingData: existing,
        ),
        returnsNormally,
      );
    });
  });

  group('S2 — stale write must not restore stock', () {
    test('S2_STALE_WRITE_RESTORE_TEST_PRESENT same revision rejected', () {
      const rev = 9;
      final existing = _remoteGrade(qty: 9, revision: rev, operationId: 'op-a');
      final stale = _writePayload(
        qty: 10,
        revision: rev,
        operationId: 'op-stale-b',
      );

      expect(
        () => enforceStockRevisionWriteContract(
          updateData: stale,
          existingData: existing,
        ),
        throwsA(isA<StockRevisionWriteRejectedException>()),
      );
    });

    test('S2 stale revision regression rejected', () {
      final existing = _remoteGrade(qty: 9, revision: 9, operationId: 'op-a');
      final stale = _writePayload(
        qty: 10,
        revision: 8,
        operationId: 'op-stale',
      );

      expect(
        () => enforceStockRevisionWriteContract(
          updateData: stale,
          existingData: existing,
        ),
        throwsA(
          predicate<StockRevisionWriteRejectedException>(
            (e) => e.code == 'REVISION_REGRESSION',
          ),
        ),
      );
    });
  });

  group('newer legitimate write', () {
    test('NEWER_REVISION_WRITE_TEST_PRESENT N+1 accepted', () {
      final existing = _remoteGrade(qty: 9, revision: 9, operationId: 'op-a');
      final newer = _writePayload(qty: 8, revision: 10, operationId: 'op-b');

      expect(
        () => enforceStockRevisionWriteContract(
          updateData: newer,
          existingData: existing,
        ),
        returnsNormally,
      );
    });
  });

  group('multi-device stale client', () {
    test(
      'MULTI_DEVICE_STALE_CLIENT_TEST_PRESENT push skip blocks stale dominate',
      () {
        // Device A sold: remote authoritative qty=9 rev=9.
        final remoteAfterSale = _remoteGrade(
          qty: 9,
          revision: 9,
          operationId: 'op-sale',
        );
        // Device B stale Hive still qty=10 rev=9.
        final staleLocal = _localProduto(qty: 10, stockRevision: 9);

        expect(
          evaluatePushStockSkipByRevision(
            local: staleLocal,
            existingData: remoteAfterSale,
          ),
          isTrue,
        );
      },
    );
  });

  group('pull revision guard preserved (6af9a88)', () {
    test('CURRENT_PULL_REVISION_GUARD_PRESERVED pending local preserved', () {
      final local = _localProduto(
        qty: 9,
        stockRevision: 8,
        pendingOp: 'op-pending',
        pendingBase: 8,
      );
      final staleRemote = _remoteGrade(
        qty: 10,
        revision: 8,
        operationId: 'op-other',
      );

      final decision = evaluatePullStockMergeByRevision(
        local: local,
        remoteData: staleRemote,
      );
      expect(decision, PullStockMergeDecision.preserveLocalGrade);
    });
  });
}
