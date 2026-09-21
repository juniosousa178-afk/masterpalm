// Reconciliação LOCAL de pending stock vs remoto — sem stock command / sem write remoto.
// Clear Hive pending + hydrate only when classificação for segura.

import 'package:flutter/foundation.dart';

import 'produto_effective_stock.dart';
import 'produto_estoque_grade_snapshot.dart';
import 'produto_stock_revision.dart';
import '../models/produto.dart';

/// Classificação forense / ação de reconciliação local.
enum PendingStockReconcileClass {
  /// Estado pretendido == remoto (norm); op diferente; rev pode ser == base.
  staleConfirmedEquivalent,

  /// Remoto avançou (rev > base) com outra operação — pending local superado.
  supersededPendingRemoteAdvanced,

  /// Pending genérico aggregate; remoto variation estruturado equivalente em soma.
  staleStructuralPending,

  /// Remoto structuralmente inconsistente (ex.: AN13PR) — não auto-limpar.
  manualStockStructureReviewRequired,

  /// Pendência real ainda não refletida no servidor.
  realPending,

  corruptPending,
  ambiguousPending,
}

extension PendingStockReconcileClassWire on PendingStockReconcileClass {
  String get wire => switch (this) {
        PendingStockReconcileClass.staleConfirmedEquivalent =>
          'STALE_CONFIRMED_EQUIVALENT',
        PendingStockReconcileClass.supersededPendingRemoteAdvanced =>
          'SUPERSEDED_PENDING_REMOTE_ADVANCED',
        PendingStockReconcileClass.staleStructuralPending =>
          'STALE_STRUCTURAL_PENDING',
        PendingStockReconcileClass.manualStockStructureReviewRequired =>
          'MANUAL_STOCK_STRUCTURE_REVIEW_REQUIRED',
        PendingStockReconcileClass.realPending => 'REAL_PENDING',
        PendingStockReconcileClass.corruptPending => 'CORRUPT_PENDING',
        PendingStockReconcileClass.ambiguousPending => 'AMBIGUOUS_PENDING',
      };

  bool get mayClearLocalPendingOnly => switch (this) {
        PendingStockReconcileClass.staleConfirmedEquivalent ||
        PendingStockReconcileClass.supersededPendingRemoteAdvanced ||
        PendingStockReconcileClass.staleStructuralPending =>
          true,
        _ => false,
      };

  bool get mustNeverFlush => switch (this) {
        PendingStockReconcileClass.supersededPendingRemoteAdvanced ||
        PendingStockReconcileClass.staleStructuralPending ||
        PendingStockReconcileClass.manualStockStructureReviewRequired ||
        PendingStockReconcileClass.staleConfirmedEquivalent =>
          true,
        _ => false,
      };
}

class PendingStockReconcileDecision {
  const PendingStockReconcileDecision({
    required this.classification,
    required this.stateEquivalent,
    required this.remoteRevEqualsBase,
    this.reason = '',
  });

  final PendingStockReconcileClass classification;
  final bool stateEquivalent;
  final bool remoteRevEqualsBase;
  final String reason;
}

bool _normalizedStatesEquivalent({
  required int intendedQty,
  required Map<String, int> intendedCells,
  required int remoteQty,
  required Map<String, int> remoteCells,
}) {
  if (intendedQty != remoteQty) return false;
  final a = normalizeSemCorAliasCells(intendedCells);
  final b = normalizeSemCorAliasCells(remoteCells);
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}

bool _pendingIsOnlyGenericAggregate(Map<String, int> cells) {
  if (cells.isEmpty) return true;
  final norm = normalizeSemCorAliasCells(cells);
  if (norm.isEmpty) {
    // só zeros / vazio
    final keys = cells.keys.toList();
    return keys.every((k) {
      final parts = k.split('|');
      final tam = parts.isNotEmpty ? parts[0] : '';
      final cor = parts.length > 1 ? parts[1] : '';
      return (tam.isEmpty || tam == 'sem-tamanho') &&
          (cor.isEmpty || cor == 'sem-cor');
    });
  }
  if (norm.length != 1) return false;
  final key = norm.keys.single;
  final parts = key.split('|');
  final tam = parts.isNotEmpty ? parts[0] : '';
  final cor = parts.length > 1 ? parts[1] : '';
  return (tam.isEmpty || tam == 'sem-tamanho') &&
      (cor.isEmpty || cor == 'sem-cor');
}

bool _remoteHasStructuredVariation(Map<String, dynamic> remote) {
  final kind = effectiveStockKindFromRemote(remote);
  if (kind != EffectiveStockKind.variation &&
      kind != EffectiveStockKind.grade) {
    return false;
  }
  final cells = normalizeSemCorAliasCells(
    effectiveCanonicalCellsFromRemote(remote),
  );
  for (final key in cells.keys) {
    final parts = key.split('|');
    final tam = parts.isNotEmpty ? parts[0] : '';
    final cor = parts.length > 1 ? parts[1] : '';
    final realTam = tam.isNotEmpty && tam != 'sem-tamanho';
    final realCor = cor.isNotEmpty && cor != 'sem-cor';
    if (realTam || realCor) return true;
  }
  return false;
}

bool _remoteNormalizedAggregateConsistent(Map<String, dynamic> remote) {
  final qty = (remote['quantidade'] as num?)?.toInt() ?? 0;
  final cells = normalizeSemCorAliasCells(
    effectiveCanonicalCellsFromRemote(remote),
  );
  if (cells.isEmpty) return qty == 0;
  return sumNormalizedCells(cells) == qty;
}

/// Classifica pending local contra snapshot remoto (read-only).
PendingStockReconcileDecision classifyPendingAgainstRemote({
  required Produto local,
  required Map<String, dynamic>? remote,
}) {
  final pendingOp = (local.pendingStockOperationId ?? '').trim();
  final base = local.pendingStockBaseRevision ?? local.stockRevision;
  final localGrade = ProdutoEstoqueGradeSnapshot.fromProduto(local);

  if (pendingOp.isEmpty) {
    return const PendingStockReconcileDecision(
      classification: PendingStockReconcileClass.corruptPending,
      stateEquivalent: false,
      remoteRevEqualsBase: false,
      reason: 'EMPTY_PENDING_OPERATION_ID',
    );
  }

  if (remote == null) {
    return PendingStockReconcileDecision(
      classification: PendingStockReconcileClass.ambiguousPending,
      stateEquivalent: false,
      remoteRevEqualsBase: false,
      reason: 'REMOTE_MISSING_OR_UNREADABLE',
    );
  }

  final remoteRev = parseStockRevisionFromRemote(remote);
  final remoteOp = parseStockOperationIdFromRemote(remote) ?? '';
  final remoteQty = (remote['quantidade'] as num?)?.toInt() ?? 0;
  final remoteCells = ProdutoEstoqueGradeSnapshot.fromRemote(remote).cells;
  final stateEq = _normalizedStatesEquivalent(
    intendedQty: local.quantidade,
    intendedCells: localGrade.cells,
    remoteQty: remoteQty,
    remoteCells: remoteCells,
  );
  final revEqBase = remoteRev == base;
  final confirmed = (local.confirmedStockOperationId ?? '').trim();

  // AN13PR-like: remoto com mismatch aggregate vs células normalizadas.
  if (!_remoteNormalizedAggregateConsistent(remote) &&
      _remoteHasStructuredVariation(remote) &&
      _pendingIsOnlyGenericAggregate(localGrade.cells)) {
    return PendingStockReconcileDecision(
      classification:
          PendingStockReconcileClass.manualStockStructureReviewRequired,
      stateEquivalent: stateEq,
      remoteRevEqualsBase: revEqBase,
      reason: 'NORMALIZED_REMOTE_AGGREGATE_MISMATCH',
    );
  }

  // STALE_STRUCTURAL: pending genérico; remoto estruturado; soma bate; same confirmed op.
  if (remoteOp != pendingOp &&
      revEqBase &&
      _pendingIsOnlyGenericAggregate(localGrade.cells) &&
      _remoteHasStructuredVariation(remote) &&
      _remoteNormalizedAggregateConsistent(remote) &&
      remoteQty == local.quantidade &&
      confirmed.isNotEmpty &&
      confirmed == remoteOp) {
    return PendingStockReconcileDecision(
      classification: PendingStockReconcileClass.staleStructuralPending,
      stateEquivalent: false,
      remoteRevEqualsBase: revEqBase,
      reason: 'GENERIC_PENDING_VS_STRUCTURED_REMOTE_EQUIVALENT_SUM',
    );
  }

  if (remoteOp == pendingOp && remoteRev > base) {
    return PendingStockReconcileDecision(
      classification: PendingStockReconcileClass.staleConfirmedEquivalent,
      stateEquivalent: true,
      remoteRevEqualsBase: false,
      reason: 'REMOTE_CONFIRMED_SAME_OPERATION',
    );
  }

  if (remoteOp != pendingOp && remoteRev > base) {
    return PendingStockReconcileDecision(
      classification:
          PendingStockReconcileClass.supersededPendingRemoteAdvanced,
      stateEquivalent: stateEq,
      remoteRevEqualsBase: false,
      reason: 'REMOTE_ADVANCED_OTHER_OPERATION',
    );
  }

  if (remoteOp != pendingOp && revEqBase && stateEq) {
    return PendingStockReconcileDecision(
      classification: PendingStockReconcileClass.staleConfirmedEquivalent,
      stateEquivalent: true,
      remoteRevEqualsBase: true,
      reason: 'REMOTE_REV_EQ_BASE_STATE_EQUIVALENT_OTHER_OP',
    );
  }

  if (remoteOp == pendingOp && remoteRev <= base) {
    return PendingStockReconcileDecision(
      classification: PendingStockReconcileClass.realPending,
      stateEquivalent: stateEq,
      remoteRevEqualsBase: revEqBase,
      reason: 'SAME_OP_NOT_YET_ADVANCED',
    );
  }

  if (remoteOp != pendingOp && revEqBase && !stateEq) {
    return PendingStockReconcileDecision(
      classification: PendingStockReconcileClass.ambiguousPending,
      stateEquivalent: false,
      remoteRevEqualsBase: true,
      reason: 'REMOTE_REV_EQ_BASE_STATE_DIVERGES',
    );
  }

  if (!stateEq && remoteRev < base) {
    return PendingStockReconcileDecision(
      classification: PendingStockReconcileClass.ambiguousPending,
      stateEquivalent: false,
      remoteRevEqualsBase: false,
      reason: 'REMOTE_REV_BEHIND_BASE',
    );
  }

  if (!stateEq) {
    return PendingStockReconcileDecision(
      classification: PendingStockReconcileClass.realPending,
      stateEquivalent: false,
      remoteRevEqualsBase: revEqBase,
      reason: 'INTENDED_STATE_NOT_ON_REMOTE',
    );
  }

  return PendingStockReconcileDecision(
    classification: PendingStockReconcileClass.ambiguousPending,
    stateEquivalent: stateEq,
    remoteRevEqualsBase: revEqBase,
    reason: 'INSUFFICIENT_EVIDENCE',
  );
}

/// Limpa pending local e hidrata do remoto. **Zero writes remotos.**
bool clearLocalPendingAndHydrateFromRemote(
  Produto local, {
  required Map<String, dynamic> remote,
  required PendingStockReconcileClass expectedClass,
}) {
  if (!hasPendingStockMutation(local)) return false;
  final decision = classifyPendingAgainstRemote(local: local, remote: remote);
  if (decision.classification != expectedClass) return false;
  if (!decision.classification.mayClearLocalPendingOnly) return false;

  local.pendingStockOperationId = null;
  local.pendingStockBaseRevision = null;
  clearStockSyncConflict(local);

  applyAuthoritativeRemoteStockToProduto(
    local,
    remote: remote,
    updateQuantity: true,
  );
  return true;
}

/// Orquestra clears seguros (equivalent / superseded / structural).
/// Retorna true se pending foi limpo.
bool reconcileSafeLocalPendingAgainstRemote(
  Produto local, {
  required Map<String, dynamic> remote,
}) {
  if (!hasPendingStockMutation(local)) return true;
  final decision = classifyPendingAgainstRemote(local: local, remote: remote);
  if (!decision.classification.mayClearLocalPendingOnly) return false;
  return clearLocalPendingAndHydrateFromRemote(
    local,
    remote: remote,
    expectedClass: decision.classification,
  );
}

/// Detecta qty local ≠ remoto com mesma rev/op e sem pending.
bool isLocalUntrackedQtyMutation({
  required Produto local,
  required Map<String, dynamic> remote,
}) {
  if (hasPendingStockMutation(local)) return false;
  final remoteQty = (remote['quantidade'] as num?)?.toInt();
  if (remoteQty == null) return false;
  if (local.quantidade == remoteQty) return false;
  final remoteRev = parseStockRevisionFromRemote(remote);
  final remoteOp = parseStockOperationIdFromRemote(remote) ?? '';
  final localOp = (local.confirmedStockOperationId ?? '').trim();
  return local.stockRevision == remoteRev &&
      localOp.isNotEmpty &&
      localOp == remoteOp;
}

@visibleForTesting
bool pendingIsOnlyGenericAggregateForTest(Map<String, int> cells) =>
    _pendingIsOnlyGenericAggregate(cells);
