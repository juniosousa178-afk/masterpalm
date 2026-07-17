// Política: quando a UI da Nova Venda pode liberar loading pós-persistência local.

/// Checkpoint seguro para encerrar spinner/sucesso sem esperar sync/campanha.
bool canReleaseUiAfterLocalPersist({
  required bool hivePersisted,
  required bool journalCompleted,
  required bool isFiado,
  required bool fiadoReceivableReady,
  required bool saleIntentPersistedOrSkipped,
}) {
  if (!hivePersisted || !journalCompleted) return false;
  if (isFiado) return fiadoReceivableReady;
  return saleIntentPersistedOrSkipped;
}

/// Operações que NÃO devem bloquear a UI após o checkpoint local.
bool isSecondaryPostPersistWork(String stage) {
  switch (stage) {
    case 'sync_begin':
    case 'sync_ok':
    case 'sync_warning':
    case 'campaign':
    case 'sale_intent_complete':
      return true;
    default:
      return false;
  }
}
