// Máquina de estados: sale_sync_completed vs operation_completed — Fase 6.5 design.

enum PdvV1JournalState {
  prepared,
  remoteStockPending,
  remoteStockApplied,
  hiveSalePending,
  hiveSaleCompleted,
  receivablePending,
  receivableCompleted,
  comboCapPending,
  comboCapCompleted,
  productCacheRefreshPending,
  productCacheRefreshCompleted,
  syncQueuePending,
  syncQueueCompleted,
  syncRemotePending,
  syncRemoteCompleted,
  saleSyncPending,
  saleSyncCompleted,
  catalogProjectionPending,
  catalogProjectionCompleted,
  movementPending,
  movementCompleted,
  effectsCompleted,
  operationCompleted,
  manualInterventionRequired,
}

enum PdvV1EffectGate {
  none,
  saleSync,
  operationCompleted,
}

class PdvV1SubstateSpec {
  const PdvV1SubstateSpec({
    required this.state,
    required this.truthSource,
    required this.idempotencyKey,
    required this.blocksSaleSync,
    required this.blocksOperationCompleted,
    required this.recovery,
    required this.allowedNext,
  });

  final PdvV1JournalState state;
  final String truthSource;
  final String idempotencyKey;
  final bool blocksSaleSync;
  final bool blocksOperationCompleted;
  final String recovery;
  final List<PdvV1JournalState> allowedNext;
}

/// Efeitos obrigatórios para operation_completed (V1 PDV nova venda).
const pdvV1MandatoryEffectsForOperationCompleted = [
  PdvV1JournalState.hiveSaleCompleted,
  PdvV1JournalState.productCacheRefreshCompleted,
  PdvV1JournalState.comboCapCompleted,
  PdvV1JournalState.syncRemoteCompleted,
];

/// sale_sync_completed exige apenas remote stock + hive sale + sync remoto da venda.
const pdvV1MandatoryForSaleSyncCompleted = [
  PdvV1JournalState.remoteStockApplied,
  PdvV1JournalState.hiveSaleCompleted,
  PdvV1JournalState.saleSyncCompleted,
];

bool pdvV1CanMarkSaleSyncCompleted(Set<PdvV1JournalState> completed) {
  for (final s in pdvV1MandatoryForSaleSyncCompleted) {
    if (!completed.contains(s)) return false;
  }
  if (completed.contains(PdvV1JournalState.manualInterventionRequired)) {
    return false;
  }
  return true;
}

bool pdvV1CanMarkOperationCompleted(Set<PdvV1JournalState> completed) {
  if (completed.contains(PdvV1JournalState.manualInterventionRequired)) {
    return false;
  }
  for (final s in pdvV1MandatoryEffectsForOperationCompleted) {
    if (!completed.contains(s)) return false;
  }
  return true;
}

/// sale_sync_completed pode preceder operation_completed.
bool pdvV1SaleSyncBeforeOperationAllowed(Set<PdvV1JournalState> completed) {
  return pdvV1CanMarkSaleSyncCompleted(completed) &&
      !pdvV1CanMarkOperationCompleted(completed);
}

const pdvV1SubstateCatalog = <PdvV1SubstateSpec>[
  PdvV1SubstateSpec(
    state: PdvV1JournalState.remoteStockApplied,
    truthSource: 'Firestore TX estoque_produtos + marcador V1',
    idempotencyKey: 'operationId',
    blocksSaleSync: true,
    blocksOperationCompleted: true,
    recovery: 'GET marcador + retry TX idempotente',
    allowedNext: [PdvV1JournalState.hiveSalePending],
  ),
  PdvV1SubstateSpec(
    state: PdvV1JournalState.hiveSaleCompleted,
    truthSource: 'Journal preparedSnapshot + saleId',
    idempotencyKey: 'saleId:snapshotHash',
    blocksSaleSync: true,
    blocksOperationCompleted: true,
    recovery: 'HiveUpsertPorSaleId',
    allowedNext: [
      PdvV1JournalState.receivablePending,
      PdvV1JournalState.comboCapPending,
      PdvV1JournalState.productCacheRefreshPending,
      PdvV1JournalState.syncQueuePending,
    ],
  ),
  PdvV1SubstateSpec(
    state: PdvV1JournalState.receivableCompleted,
    truthSource: 'Firestore contas_receber (autoritativo V1)',
    idempotencyKey: 'saleId:conta_receber:p{N}',
    blocksSaleSync: false,
    blocksOperationCompleted: true,
    recovery: 'upsert FS + dedup Hive',
    allowedNext: [PdvV1JournalState.saleSyncPending],
  ),
  PdvV1SubstateSpec(
    state: PdvV1JournalState.comboCapCompleted,
    truthSource: 'estoque_produtos componentes (remoto)',
    idempotencyKey: 'operationId:combo_cap:comboId',
    blocksSaleSync: false,
    blocksOperationCompleted: true,
    recovery: 'recalcular teto absoluto idempotente',
    allowedNext: [PdvV1JournalState.catalogProjectionPending],
  ),
  PdvV1SubstateSpec(
    state: PdvV1JournalState.saleSyncCompleted,
    truthSource: 'estoque_vendas/{saleId}',
    idempotencyKey: 'saleId',
    blocksSaleSync: false,
    blocksOperationCompleted: false,
    recovery: 'syncVenda idempotente',
    allowedNext: [
      PdvV1JournalState.catalogProjectionPending,
      PdvV1JournalState.effectsCompleted,
    ],
  ),
  PdvV1SubstateSpec(
    state: PdvV1JournalState.syncRemoteCompleted,
    truthSource: 'estoque_vendas/{saleId} confirmado',
    idempotencyKey: 'saleId',
    blocksSaleSync: false,
    blocksOperationCompleted: true,
    recovery: 'syncVenda idempotente',
    allowedNext: [PdvV1JournalState.catalogProjectionPending],
  ),
  PdvV1SubstateSpec(
    state: PdvV1JournalState.catalogProjectionCompleted,
    truthSource: 'estoque_produtos → produtos/draft',
    idempotencyKey: 'operationId:catalog:productId',
    blocksSaleSync: false,
    blocksOperationCompleted: false,
    recovery: 'CatalogoWebAposEstoqueService',
    allowedNext: [PdvV1JournalState.effectsCompleted],
  ),
  PdvV1SubstateSpec(
    state: PdvV1JournalState.operationCompleted,
    truthSource: 'Journal — todos efeitos obrigatórios OK',
    idempotencyKey: 'operationId',
    blocksSaleSync: false,
    blocksOperationCompleted: false,
    recovery: 'no-op',
    allowedNext: [],
  ),
];
