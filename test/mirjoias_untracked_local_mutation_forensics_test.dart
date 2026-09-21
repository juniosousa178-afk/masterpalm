// MIRJOIAS — untracked local mutation forensic preservation (no remote writes).

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_effective_stock.dart';
import 'package:master_palm/core/produto_pending_stock_reconciliation.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/core/produto_untracked_stock_conflict.dart';
import 'package:master_palm/models/produto.dart';

Produto _local({
  required int qty,
  required int rev,
  required String op,
  String? pending,
}) {
  return Produto.vazio()
    ..nome = 'Forensic SKU'
    ..codigoBarras = 'FX01'
    ..idFirebase = 'mirjoias-forensic-sku'
    ..lojaId = 'mirjoias'
    ..quantidade = qty
    ..stockRevision = rev
    ..confirmedStockOperationId = op
    ..pendingStockOperationId = pending;
}

Map<String, dynamic> _remote({
  required int qty,
  required int rev,
  required String op,
}) =>
    {
      'quantidade': qty,
      'stockRevision': rev,
      'stockOperationId': op,
      'stockKind': 'simple',
    };

void main() {
  setUp(UntrackedStockConflictStore.clearAll);

  group('A detect conflict', () {
    test('same rev/op local1 remote0 no pending → LOCAL_UNTRACKED', () {
      final local = _local(qty: 1, rev: 2, op: 'op-same');
      final remote = _remote(qty: 0, rev: 2, op: 'op-same');
      expect(
        isLocalUntrackedQtyMutation(local: local, remote: remote),
        isTrue,
      );
    });
  });

  group('B hydrate preserves evidence', () {
    test('subsequent remote hydration keeps conflict evidence', () {
      final local = _local(qty: 1, rev: 2, op: 'op-same');
      final remote = _remote(qty: 0, rev: 2, op: 'op-same');

      applyAuthoritativeRemoteStockToProduto(
        local,
        remote: remote,
        updateQuantity: true,
      );
      expect(local.quantidade, 0);

      final evidence = UntrackedStockConflictStore.get(
        storeId: 'mirjoias',
        productId: 'mirjoias-forensic-sku',
      );
      expect(evidence, isNotNull);
      expect(evidence!.observedLocalQty, 1);
      expect(evidence.observedRemoteQty, 0);
      expect(evidence.revision, 2);
      expect(evidence.operationId, 'op-same');
    });
  });

  group('C D no remote write / no auto pending', () {
    test('hydrate does not create pending', () {
      final local = _local(qty: 1, rev: 2, op: 'op-same');
      final remote = _remote(qty: 0, rev: 2, op: 'op-same');
      applyAuthoritativeRemoteStockToProduto(
        local,
        remote: remote,
        updateQuantity: true,
      );
      expect(hasPendingStockMutation(local), isFalse);
      expect(local.pendingStockOperationId, isNull);
    });
  });

  group('E normal hydrate', () {
    test('local==remote hydrates normally without conflict store', () {
      final local = _local(qty: 2, rev: 3, op: 'op-ok');
      final remote = _remote(qty: 2, rev: 3, op: 'op-ok');
      applyAuthoritativeRemoteStockToProduto(
        local,
        remote: remote,
        updateQuantity: true,
      );
      expect(local.quantidade, 2);
      expect(
        UntrackedStockConflictStore.get(
          storeId: 'mirjoias',
          productId: 'mirjoias-forensic-sku',
        ),
        isNull,
      );
    });
  });

  group('F remote newer', () {
    test('remote newer revision is not classified as untracked', () {
      final local = _local(qty: 3, rev: 4, op: 'op-old');
      final remote = _remote(qty: 0, rev: 5, op: 'op-new');
      expect(
        isLocalUntrackedQtyMutation(local: local, remote: remote),
        isFalse,
      );
    });
  });

  group('G sale prep', () {
    test('sale refresh path does not erase prior forensic evidence', () {
      final local = _local(qty: 1, rev: 2, op: 'op-same');
      final remote = _remote(qty: 0, rev: 2, op: 'op-same');
      preserveUntrackedConflictBeforeHydrate(
        local: local,
        remote: remote,
        source: 'pre-sale',
      );

      // Same core path used by refreshAuthoritativeStockCacheForSale.
      applyAuthoritativeRemoteStockToProduto(
        local,
        remote: remote,
        updateQuantity: true,
      );

      final evidence = UntrackedStockConflictStore.get(
        storeId: 'mirjoias',
        productId: 'mirjoias-forensic-sku',
      );
      expect(evidence, isNotNull);
      expect(evidence!.observedLocalQty, 1);
      expect(evidence.source, 'pre-sale'); // earliest kept
      expect(local.quantidade, 0);
    });
  });

  group('H pending reconcile unrelated', () {
    test('pending clear of other product does not drop untracked evidence', () {
      final untracked = _local(qty: 1, rev: 2, op: 'op-same');
      final remoteUt = _remote(qty: 0, rev: 2, op: 'op-same');
      preserveUntrackedConflictBeforeHydrate(
        local: untracked,
        remote: remoteUt,
        source: 'unrelated-untracked',
      );

      final pending = _local(qty: 1, rev: 1, op: 'old', pending: 'pend-a')
        ..idFirebase = 'mirjoias-other-pending'
        ..codigoBarras = 'AN05SM';
      final remotePending = {
        'quantidade': 1,
        'stockRevision': 1,
        'stockOperationId': 'remote-confirmed-op',
        'stockKind': 'simple',
        'variacoes': {
          '25': {'sem-cor': 1},
        },
      };
      expect(
        reconcileSafeLocalPendingAgainstRemote(
          pending,
          remote: remotePending,
        ),
        isTrue,
      );

      final evidence = UntrackedStockConflictStore.get(
        storeId: 'mirjoias',
        productId: 'mirjoias-forensic-sku',
      );
      expect(evidence, isNotNull);
      expect(evidence!.observedLocalQty, 1);
    });
  });

  group('tryConfirm fingerprint', () {
    test('adopting newer rev/op with divergent qty captures conflict', () {
      final local = _local(qty: 3, rev: 4, op: 'op-old');
      final remote = _remote(qty: 0, rev: 5, op: 'op-new');
      expect(
        tryConfirmWouldCreateUntrackedFingerprint(local: local, remote: remote),
        isTrue,
      );
      expect(tryConfirmStockFromRemote(local, remote), isTrue);
      expect(local.stockRevision, 5);
      expect(local.confirmedStockOperationId, 'op-new');
      expect(local.quantidade, 3);
      expect(
        isLocalUntrackedQtyMutation(local: local, remote: remote),
        isTrue,
      );
      expect(
        UntrackedStockConflictStore.get(
          storeId: 'mirjoias',
          productId: 'mirjoias-forensic-sku',
        )?.observedLocalQty,
        3,
      );
    });
  });

  group('I 34-conflict fixture batch', () {
    test('every conflict captured exactly once', () {
      const n = 34;
      for (var i = 0; i < n; i++) {
        final local = Produto.vazio()
          ..nome = 'SKU $i'
          ..codigoBarras = 'C$i'
          ..idFirebase = 'mirjoias-batch-$i'
          ..lojaId = 'mirjoias'
          ..quantidade = i == 0 ? 6 : (i == 1 ? 3 : 1)
          ..stockRevision = 2
          ..confirmedStockOperationId = 'op-batch-$i';
        final remote = {
          'quantidade': i == 0 ? 4 : 0,
          'stockRevision': 2,
          'stockOperationId': 'op-batch-$i',
          'stockKind': 'simple',
        };
        final c = preserveUntrackedConflictBeforeHydrate(
          local: local,
          remote: remote,
          source: 'batch-fixture',
        );
        expect(c, isNotNull);
        applyAuthoritativeRemoteStockToProduto(
          local,
          remote: remote,
          updateQuantity: true,
        );
      }
      expect(UntrackedStockConflictStore.countForStore('mirjoias'), n);
      // Re-run capture — still n (idempotent).
      for (var i = 0; i < n; i++) {
        final local = Produto.vazio()
          ..nome = 'SKU $i'
          ..codigoBarras = 'C$i'
          ..idFirebase = 'mirjoias-batch-$i'
          ..lojaId = 'mirjoias'
          ..quantidade = i == 0 ? 6 : (i == 1 ? 3 : 1)
          ..stockRevision = 2
          ..confirmedStockOperationId = 'op-batch-$i';
        final remote = {
          'quantidade': i == 0 ? 4 : 0,
          'stockRevision': 2,
          'stockOperationId': 'op-batch-$i',
          'stockKind': 'simple',
        };
        preserveUntrackedConflictBeforeHydrate(
          local: local,
          remote: remote,
          source: 'batch-fixture-retry',
        );
      }
      expect(UntrackedStockConflictStore.countForStore('mirjoias'), n);
    });
  });

  group('J idempotency fingerprint', () {
    test('same state does not duplicate; new state adds event', () {
      final local = _local(qty: 1, rev: 2, op: 'op-same');
      final remote = _remote(qty: 0, rev: 2, op: 'op-same');
      preserveUntrackedConflictBeforeHydrate(
        local: local,
        remote: remote,
        source: 'first',
      );
      preserveUntrackedConflictBeforeHydrate(
        local: local,
        remote: remote,
        source: 'second',
      );
      expect(UntrackedStockConflictStore.countForStore('mirjoias'), 1);

      final local2 = _local(qty: 2, rev: 2, op: 'op-same');
      preserveUntrackedConflictBeforeHydrate(
        local: local2,
        remote: remote,
        source: 'new-state',
      );
      expect(UntrackedStockConflictStore.countForStore('mirjoias'), 2);
    });
  });
}
