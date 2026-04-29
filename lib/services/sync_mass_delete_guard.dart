// lib/services/sync_mass_delete_guard.dart
// Guardas P0 contra deleção em massa suspeita (Hive incompleto / allowed vazio).

/// Limite absoluto de documentos a apagar numa única passagem sem confirmação explícita.
const int kSyncMassDeleteMaxAbsolute = 20;

/// Fração máxima do remoto que pode ser apagada sem [allowMassDelete].
const double kSyncMassDeleteMaxFraction = 0.30;

/// Motivo do bloqueio (para logs/testes).
enum SyncMassDeleteBlockReason {
  none,
  allowedEmptyWithRemote,
  deleteCountOverAbsoluteCap,
  deleteFractionOverCap,
  localIdsEmptyWithRemote,
}

abstract final class SyncMassDeleteGuard {
  /// Catálogo (`draft_produtos` / `produtos`): [allowedCount] = tamanho do conjunto permitido.
  static SyncMassDeleteBlockReason catalogBlockReason({
    required int allowedCount,
    required int remoteCount,
    required int deleteCandidatesCount,
    required bool allowMassDelete,
  }) {
    if (allowMassDelete) return SyncMassDeleteBlockReason.none;
    if (allowedCount == 0 && remoteCount > 0) {
      return SyncMassDeleteBlockReason.allowedEmptyWithRemote;
    }
    if (deleteCandidatesCount > kSyncMassDeleteMaxAbsolute) {
      return SyncMassDeleteBlockReason.deleteCountOverAbsoluteCap;
    }
    if (remoteCount > 0 &&
        deleteCandidatesCount > remoteCount * kSyncMassDeleteMaxFraction) {
      return SyncMassDeleteBlockReason.deleteFractionOverCap;
    }
    return SyncMassDeleteBlockReason.none;
  }

  static bool shouldBlockCatalogMassDelete({
    required int allowedCount,
    required int remoteCount,
    required int deleteCandidatesCount,
    required bool allowMassDelete,
  }) {
    return catalogBlockReason(
          allowedCount: allowedCount,
          remoteCount: remoteCount,
          deleteCandidatesCount: deleteCandidatesCount,
          allowMassDelete: allowMassDelete,
        ) !=
        SyncMassDeleteBlockReason.none;
  }

  /// `estoque_produtos`: [localIdsCount] = produtos locais com `idFirebase` não vazio para a loja.
  static SyncMassDeleteBlockReason estoqueExcedentesBlockReason({
    required int localIdsCount,
    required int remoteCount,
    required int deleteCandidatesCount,
    required bool allowMassDelete,
  }) {
    if (allowMassDelete) return SyncMassDeleteBlockReason.none;
    if (localIdsCount == 0 && remoteCount > 0) {
      return SyncMassDeleteBlockReason.localIdsEmptyWithRemote;
    }
    if (deleteCandidatesCount > kSyncMassDeleteMaxAbsolute) {
      return SyncMassDeleteBlockReason.deleteCountOverAbsoluteCap;
    }
    if (remoteCount > 0 &&
        deleteCandidatesCount > remoteCount * kSyncMassDeleteMaxFraction) {
      return SyncMassDeleteBlockReason.deleteFractionOverCap;
    }
    return SyncMassDeleteBlockReason.none;
  }

  static bool shouldBlockEstoqueExcedentesMassDelete({
    required int localIdsCount,
    required int remoteCount,
    required int deleteCandidatesCount,
    required bool allowMassDelete,
  }) {
    return estoqueExcedentesBlockReason(
          localIdsCount: localIdsCount,
          remoteCount: remoteCount,
          deleteCandidatesCount: deleteCandidatesCount,
          allowMassDelete: allowMassDelete,
        ) !=
        SyncMassDeleteBlockReason.none;
  }
}
