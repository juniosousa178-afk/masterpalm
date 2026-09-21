// MIRJOIAS P0 — pending reconciliation classifiers + safe local clears.

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_effective_stock.dart';
import 'package:master_palm/core/produto_pending_stock_reconciliation.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/mirjoias_client_stock_diagnostic_export.dart';

Produto _p({
  required String id,
  required String code,
  required int qty,
  required int rev,
  String? pendingOp,
  int? pendingBase,
  String? confirmedOp,
  Map<String, dynamic>? variacoes,
  Map<String, int>? ept,
}) {
  return Produto.vazio()
    ..nome = code
    ..codigoBarras = code
    ..idFirebase = id
    ..lojaId = 'mirjoias'
    ..quantidade = qty
    ..stockRevision = rev
    ..pendingStockOperationId = pendingOp
    ..pendingStockBaseRevision = pendingBase
    ..confirmedStockOperationId = confirmedOp
    ..variacoes = variacoes
    ..estoquePorTamanho = ept ?? const {};
}

void main() {
  group('stale confirmed equivalent (rev == base)', () {
    test('remoteRev == base, state equivalent, different op → clear local', () {
      final local = _p(
        id: 'mirjoias-anel-bolinha-t-25-semijoia-3',
        code: 'AN05SM',
        qty: 1,
        rev: 1,
        pendingOp: 'pend-local-op',
        pendingBase: 1,
        confirmedOp: 'old-confirmed',
        variacoes: {
          '25': {'sem-cor': 1},
        },
        ept: {'25': 1},
      );
      final remote = {
        'quantidade': 1,
        'stockRevision': 1,
        'stockOperationId': 'remote-op-other',
        'stockKind': 'variation',
        'variacoes': {
          '25': {'sem-cor': 1},
        },
        'estoquePorTamanho': {'25': 1},
      };

      final decision = classifyPendingAgainstRemote(local: local, remote: remote);
      expect(
        decision.classification,
        PendingStockReconcileClass.staleConfirmedEquivalent,
      );
      expect(decision.stateEquivalent, isTrue);
      expect(decision.remoteRevEqualsBase, isTrue);

      final cleared = clearLocalPendingAndHydrateFromRemote(
        local,
        remote: remote,
        expectedClass: PendingStockReconcileClass.staleConfirmedEquivalent,
      );
      expect(cleared, isTrue);
      expect(hasPendingStockMutation(local), isFalse);
      expect(local.quantidade, 1);
      expect(local.estoquePorTamanho['25'], 1);
      expect(local.stockRevision, 1);
      expect(local.confirmedStockOperationId, 'remote-op-other');
    });

    test('AN05SM exact fixture → SALE_ALLOWED after clear', () {
      final local = _p(
        id: 'mirjoias-anel-bolinha-t-25-semijoia-3',
        code: 'AN05SM',
        qty: 1,
        rev: 1,
        pendingOp: 'stale-pend',
        pendingBase: 1,
        variacoes: {
          '25': {'sem-cor': 1},
        },
        ept: {'25': 1},
      );
      final remote = {
        'quantidade': 1,
        'stockRevision': 1,
        'stockOperationId': 'd8e222d4-b142-4290-9106-21c45cf2944f',
        'stockKind': 'variation',
        'variacoes': {
          '25': {'sem-cor': 1},
        },
        'estoquePorTamanho': {'25': 1},
      };
      expect(reconcileSafeLocalPendingAgainstRemote(local, remote: remote), isTrue);
      expect(hasPendingStockMutation(local), isFalse);
      expect(local.quantidade, 1);
    });

    test('pending qty0 stale equivalent → clear safely', () {
      final local = _p(
        id: 'p-zero',
        code: 'Z0',
        qty: 0,
        rev: 3,
        pendingOp: 'pend-z',
        pendingBase: 3,
      );
      final remote = {
        'quantidade': 0,
        'stockRevision': 3,
        'stockOperationId': 'remote-z',
        'stockKind': 'simple',
      };
      expect(reconcileSafeLocalPendingAgainstRemote(local, remote: remote), isTrue);
      expect(hasPendingStockMutation(local), isFalse);
      expect(estoqueQuantidadeUiLabel(local), 'Qtd: 0');
    });
  });

  group('superseded remote advanced', () {
    test('remoteRev > base → SUPERSEDED, never flush semantics', () {
      final local = _p(
        id: 'mirjoias-anel-reto-t-16-t-18-prata-925',
        code: 'AN03PR',
        qty: 2,
        rev: 4,
        pendingOp: 'pend-old',
        pendingBase: 4,
        variacoes: {
          '16': {'sem-cor': 1},
          '18': {'sem-cor': 1},
        },
        ept: {'16': 1, '18': 1},
      );
      final remote = {
        'quantidade': 1,
        'stockRevision': 5,
        'stockOperationId': 'newer-op',
        'stockKind': 'variation',
        'variacoes': {
          '16': {'sem-cor': 1},
        },
        'estoquePorTamanho': {'16': 1},
      };
      final decision = classifyPendingAgainstRemote(local: local, remote: remote);
      expect(
        decision.classification,
        PendingStockReconcileClass.supersededPendingRemoteAdvanced,
      );
      expect(decision.classification.mustNeverFlush, isTrue);

      expect(reconcileSafeLocalPendingAgainstRemote(local, remote: remote), isTrue);
      expect(local.quantidade, 1);
      expect(local.estoquePorTamanho.keys.toList(), ['16']);
      expect(local.estoquePorTamanho.containsKey('18'), isFalse);
      expect(hasPendingStockMutation(local), isFalse);
    });
  });

  group('structural stale BR23SM', () {
    test('generic pending qty4 vs remote M2/G2 → structural stale clear', () {
      final local = _p(
        id: 'mirjoias-br23sm',
        code: 'BR23SM',
        qty: 4,
        rev: 2,
        pendingOp: 'pend-generic',
        pendingBase: 2,
        confirmedOp: 'confirmed-remote',
        // only aggregate cell
        variacoes: null,
        ept: const {},
      );
      // Force generic cell via quantidade-only snapshot
      expect(ProdutoEstoqueGradeSnapshotHint.hasGenericOnly(local), isTrue);

      final remote = {
        'quantidade': 4,
        'stockRevision': 2,
        'stockOperationId': 'confirmed-remote',
        'stockKind': 'variation',
        'variacoes': {
          'M': {'sem-cor': 2},
          'G': {'sem-cor': 2},
        },
        'estoquePorTamanho': {'M': 2, 'G': 2},
      };

      final decision = classifyPendingAgainstRemote(local: local, remote: remote);
      expect(
        decision.classification,
        PendingStockReconcileClass.staleStructuralPending,
      );
      expect(reconcileSafeLocalPendingAgainstRemote(local, remote: remote), isTrue);
      expect(local.estoquePorTamanho['M'], 2);
      expect(local.estoquePorTamanho['G'], 2);
      expect(local.quantidade, 4);
      expect(hasPendingStockMutation(local), isFalse);
    });
  });

  group('AN13PR manual — do not clear', () {
    test('normalized remote aggregate mismatch → MANUAL, no clear', () {
      final local = _p(
        id: 'mirjoias-an13pr',
        code: 'AN13PR',
        qty: 4,
        rev: 1,
        pendingOp: 'pend-an13',
        pendingBase: 1,
        confirmedOp: 'op-x',
      );
      final remote = {
        'quantidade': 4,
        'stockRevision': 1,
        'stockOperationId': 'op-other',
        'stockKind': 'variation',
        // raw includes sem-cor aliases that normalize below aggregate
        'variacoes': {
          '14': {'ESMERALDA': 1, 'sem-cor': 2},
          '16': {'sem-cor': 1},
        },
        'estoquePorTamanho': {'14': 3, '16': 1},
      };
      final decision = classifyPendingAgainstRemote(local: local, remote: remote);
      expect(
        decision.classification,
        PendingStockReconcileClass.manualStockStructureReviewRequired,
      );
      expect(reconcileSafeLocalPendingAgainstRemote(local, remote: remote), isFalse);
      expect(hasPendingStockMutation(local), isTrue);
    });
  });

  group('local untracked mutation', () {
    test('same rev/op qty differs without pending → detect, no remote write', () {
      final local = _p(
        id: 'p-untracked',
        code: 'U1',
        qty: 1,
        rev: 5,
        confirmedOp: 'same-op',
      );
      final remote = {
        'quantidade': 0,
        'stockRevision': 5,
        'stockOperationId': 'same-op',
        'stockKind': 'simple',
      };
      expect(
        isLocalUntrackedQtyMutation(local: local, remote: remote),
        isTrue,
      );
    });

    test(
      'applyAuthoritative updateQuantity:false does not adopt rev when qty differs',
      () {
        final local = _p(
          id: 'p-guard',
          code: 'G1',
          qty: 1,
          rev: 3,
          confirmedOp: 'local-old',
        );
        final remote = {
          'quantidade': 0,
          'stockRevision': 9,
          'stockOperationId': 'remote-new',
          'stockKind': 'simple',
        };
        applyAuthoritativeRemoteStockToProduto(
          local,
          remote: remote,
          updateQuantity: false,
        );
        expect(local.quantidade, 1);
        expect(local.stockRevision, 3);
        expect(local.confirmedStockOperationId, 'local-old');
      },
    );
  });

  group('UI label', () {
    test('pending uses sync message not qtd N', () {
      final local = _p(
        id: 'p',
        code: 'X',
        qty: 0,
        rev: 1,
        pendingOp: 'pend',
        pendingBase: 1,
      );
      expect(estoqueQuantidadeUiLabel(local), 'Sincronização de estoque pendente');
    });
  });

  group('diagnostic classification wires', () {
    test('exporter includes new classes', () {
      expect(
        MirjoiasPendingClassification.staleConfirmedEquivalent.wire,
        'STALE_CONFIRMED_EQUIVALENT',
      );
      expect(
        MirjoiasPendingClassification.supersededPendingRemoteAdvanced.wire,
        'SUPERSEDED_PENDING_REMOTE_ADVANCED',
      );
    });
  });

  group('idempotency', () {
    test('retry clear is idempotent', () {
      final local = _p(
        id: 'p',
        code: 'AN05SM',
        qty: 1,
        rev: 1,
        pendingOp: 'pend',
        pendingBase: 1,
        variacoes: {
          '25': {'sem-cor': 1},
        },
        ept: {'25': 1},
      );
      final remote = {
        'quantidade': 1,
        'stockRevision': 1,
        'stockOperationId': 'op',
        'stockKind': 'variation',
        'variacoes': {
          '25': {'sem-cor': 1},
        },
        'estoquePorTamanho': {'25': 1},
      };
      expect(reconcileSafeLocalPendingAgainstRemote(local, remote: remote), isTrue);
      expect(reconcileSafeLocalPendingAgainstRemote(local, remote: remote), isTrue);
      expect(hasPendingStockMutation(local), isFalse);
    });
  });
}

/// Helper — produto só com célula agregada implícita (qty sem grade).
class ProdutoEstoqueGradeSnapshotHint {
  static bool hasGenericOnly(Produto p) {
    return pendingIsOnlyGenericAggregateForTest(
      {
        if (p.quantidade > 0) 'sem-tamanho|sem-cor': p.quantidade,
      },
    );
  }
}
