// Revisão monotônica de estoque — ordenação sem relógio misto (R8.3).

import 'package:master_palm/core/produto_estoque_grade_snapshot.dart';
import 'package:master_palm/models/produto.dart';
import 'package:uuid/uuid.dart';

/// Contador monotônico da grade em `estoque_produtos` / espelho.
const String kProdutoStockRevisionField = 'stockRevision';

/// ID da última mutação autoritativa de estoque no documento remoto.
const String kProdutoStockOperationIdField = 'stockOperationId';

/// Estado explícito de sincronização de estoque no Hive.
enum StockSyncState { confirmed, pendingLocal, conflict }

/// Campo Firestore/Hive persistido quando há conflito irreconciliável.
const String kProdutoStockSyncStateField = 'stockSyncState';

StockSyncState stockSyncStateOf(Produto p) {
  final persisted = p.stockSyncState?.trim();
  if (persisted == StockSyncState.conflict.name) {
    return StockSyncState.conflict;
  }
  if (p.pendingStockOperationId != null &&
      p.pendingStockOperationId!.trim().isNotEmpty) {
    return StockSyncState.pendingLocal;
  }
  return StockSyncState.confirmed;
}

/// Marca conflito quando remoto avança com operationId diferente da pendência.
void markStockConflict(
  Produto p, {
  String? remoteOperationId,
  int? remoteRevision,
}) {
  p.stockSyncState = StockSyncState.conflict.name;
}

void clearStockSyncConflict(Produto p) {
  if (p.stockSyncState == StockSyncState.conflict.name) {
    p.stockSyncState = null;
  }
}

/// Detecta conflito real no pull (OFF3).
bool shouldMarkStockConflictOnPull({
  required Produto local,
  required Map<String, dynamic> remoteData,
}) {
  if (!hasPendingStockMutation(local)) return false;
  final remoteRev = parseStockRevisionFromRemote(remoteData);
  final remoteOp = parseStockOperationIdFromRemote(remoteData);
  final pendingOp = local.pendingStockOperationId!.trim();
  if (remoteOp == pendingOp) return false;
  return remoteRev > (local.pendingStockBaseRevision ?? local.stockRevision);
}

/// Classificação do escritor remoto para coexistência legado/novo.
enum LegacyStockWriterKind { newApp, legacyApp }

int parseStockRevisionFromRemote(Map<String, dynamic>? data) =>
    (data?[kProdutoStockRevisionField] as num?)?.toInt() ?? 0;

String? parseStockOperationIdFromRemote(Map<String, dynamic>? data) {
  final v = data?[kProdutoStockOperationIdField];
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

String newStockOperationId() => const Uuid().v4();

/// Marca mutação local ainda não confirmada pelo servidor.
void markPendingStockMutation(
  Produto p, {
  required String operationId,
  int? baseRevision,
}) {
  p.pendingStockOperationId = operationId;
  p.pendingStockBaseRevision = baseRevision ?? p.stockRevision;
}

/// Indica pendência explícita — **não** usa relógio local vs servidor.
bool hasPendingStockMutation(Produto p) =>
    p.pendingStockOperationId != null &&
    p.pendingStockOperationId!.trim().isNotEmpty;

/// Confirma mutação quando o remoto devolve o mesmo [operationId] e revisão.
void confirmStockMutation(
  Produto p, {
  required String operationId,
  required int revision,
  DateTime? serverStockAt,
}) {
  if (hasPendingStockMutation(p) &&
      p.pendingStockOperationId!.trim() != operationId.trim()) {
    return;
  }
  p.stockRevision = revision;
  p.confirmedStockOperationId = operationId;
  p.pendingStockOperationId = null;
  p.pendingStockBaseRevision = null;
  clearStockSyncConflict(p);
  if (serverStockAt != null) {
    applyServerStockVersionToProduto(p, serverStockAt);
  }
}

/// Tenta confirmar ou adotar revisão remota após pull/push/readback.
bool tryConfirmStockFromRemote(Produto p, Map<String, dynamic> remote) {
  final remoteOp = parseStockOperationIdFromRemote(remote);
  final remoteRev = parseStockRevisionFromRemote(remote);
  final serverAt = parseFirestoreStockUpdatedAtField(remote);

  if (hasPendingStockMutation(p)) {
    final pendingOp = p.pendingStockOperationId!.trim();
    if (remoteOp == pendingOp &&
        remoteRev > (p.pendingStockBaseRevision ?? 0)) {
      confirmStockMutation(
        p,
        operationId: remoteOp!,
        revision: remoteRev,
        serverStockAt: serverAt,
      );
      return true;
    }
    return false;
  }

  if (remoteRev >= p.stockRevision) {
    p.stockRevision = remoteRev;
    if (remoteOp != null) {
      p.confirmedStockOperationId = remoteOp;
    }
    if (serverAt != null) {
      applyServerStockVersionToProduto(p, serverAt);
    }
    return true;
  }
  return false;
}

Map<String, dynamic> attachStockRevisionFields(
  Map<String, dynamic> updateData, {
  required int nextRevision,
  required String operationId,
}) {
  updateData[kProdutoStockRevisionField] = nextRevision;
  updateData[kProdutoStockOperationIdField] = operationId;
  return updateData;
}

LegacyStockWriterKind classifyRemoteStockWriter(Map<String, dynamic> remote) {
  if (remote.containsKey(kProdutoStockRevisionField)) {
    return LegacyStockWriterKind.newApp;
  }
  if (parseStockOperationIdFromRemote(remote) != null) {
    return LegacyStockWriterKind.newApp;
  }
  return LegacyStockWriterKind.legacyApp;
}

/// Pull por revisão — **não** compara `DateTime.now()` com `serverTimestamp`.
PullStockMergeDecision evaluatePullStockMergeByRevision({
  required Produto local,
  required Map<String, dynamic> remoteData,
}) {
  final localGrade = ProdutoEstoqueGradeSnapshot.fromProduto(local);
  final remoteGrade = ProdutoEstoqueGradeSnapshot.fromRemote(remoteData);
  final gradesEqual = !remoteGrade.gradeDiffersFrom(localGrade);

  final remoteRev = parseStockRevisionFromRemote(remoteData);
  final localRev = local.stockRevision;
  final remoteOp = parseStockOperationIdFromRemote(remoteData);
  final pending = hasPendingStockMutation(local);

  if (remoteRev < localRev) {
    return PullStockMergeDecision.preserveLocalGrade;
  }

  if (pending) {
    final pendingOp = local.pendingStockOperationId!.trim();
    if (remoteOp == pendingOp) {
      return PullStockMergeDecision.acceptRemote;
    }
    if (shouldMarkStockConflictOnPull(local: local, remoteData: remoteData)) {
      return PullStockMergeDecision.preserveLocalGrade;
    }
    if (remoteRev > (local.pendingStockBaseRevision ?? localRev)) {
      return PullStockMergeDecision.preserveLocalGrade;
    }
    return PullStockMergeDecision.preserveLocalGrade;
  }

  if (remoteRev > localRev) {
    return PullStockMergeDecision.acceptRemote;
  }

  if (gradesEqual) {
    return PullStockMergeDecision.acceptRemote;
  }

  final remoteIncreases = remoteGrade.cellsStrictlyGreaterThan(localGrade);
  if (remoteIncreases.isNotEmpty) {
    return PullStockMergeDecision.preserveLocalGrade;
  }

  if (classifyRemoteStockWriter(remoteData) ==
          LegacyStockWriterKind.legacyApp &&
      localRev > 0) {
    return PullStockMergeDecision.preserveLocalGrade;
  }

  final remoteDecreases = remoteGrade.cellsStrictlyLessThan(localGrade);
  if (remoteDecreases.isNotEmpty) {
    return PullStockMergeDecision.preserveLocalGrade;
  }

  return PullStockMergeDecision.acceptRemote;
}

/// Remoto com grade rica (variações ou estoque por tamanho preenchidos).
bool remoteDataHasRichGrade(Map<String, dynamic>? data) {
  if (data == null) return false;
  final v = data['variacoes'];
  if (v is Map && v.isNotEmpty) return true;
  final e = data['estoquePorTamanho'];
  if (e is Map && e.isNotEmpty) return true;
  return false;
}

bool localProdutoHasRichGrade(Produto local) {
  if (local.variacoes != null && local.variacoes!.isNotEmpty) return true;
  if (local.estoquePorTamanho.isNotEmpty) return true;
  return false;
}

/// Push/autosync por revisão — nunca usa relógio misto.
bool evaluatePushStockSkipByRevision({
  required Produto local,
  required Map<String, dynamic>? existingData,
  bool forcePushFromCadastro = false,
}) {
  if (forcePushFromCadastro) return false;
  if (existingData == null || existingData.isEmpty) return false;

  if (stockSyncStateOf(local) == StockSyncState.conflict) return true;

  if (hasPendingStockMutation(local)) return false;

  final localGrade = ProdutoEstoqueGradeSnapshot.fromProduto(local);
  final remoteGrade = ProdutoEstoqueGradeSnapshot.fromRemote(existingData);
  if (!localGrade.gradeDiffersFrom(remoteGrade)) return true;

  final remoteRev = parseStockRevisionFromRemote(existingData);
  final localRev = local.stockRevision;

  if (remoteRev > localRev) return true;
  if (remoteRev < localRev) return false;

  // Conversão estrutural (simples↔grade, limpeza de células) — não bloquear.
  final localKeys = localGrade.cells.keys.toSet();
  final remoteKeys = remoteGrade.cells.keys.toSet();
  if (localKeys.intersection(remoteKeys).isEmpty &&
      remoteDataHasRichGrade(existingData)) {
    // Só libera bypass para conversão/limpeza (local sem grade rica).
    // Grade local stale com células diferentes do remoto continua bloqueada.
    if (localProdutoHasRichGrade(local)) return true;
    return false;
  }

  final localDominates = localGrade.cellsStrictlyGreaterThan(remoteGrade);
  if (localDominates.isNotEmpty) return true;

  final remoteOp = parseStockOperationIdFromRemote(existingData);
  if (remoteOp != null &&
      remoteOp == local.confirmedStockOperationId &&
      localGrade.gradeDiffersFrom(remoteGrade)) {
    return true;
  }

  return false;
}
