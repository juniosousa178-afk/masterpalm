// Contrato projeção produtos/catálogo V1 — Fase 6.5 design.

enum PdvV1ProdutosWriteInTxDecision {
  /// Manter write produtos na TX principal como projeção atômica (Fase 6.5).
  remainInMainTransactionAsProjection,

  /// Só após recomposição comprovada em staging (não adotado na 6.5).
  moveToPostProcessIdempotent,
}

enum PdvV1CatalogEffectKind {
  productProjection,
  productCacheRefresh,
  catalogProjection,
  removalOfZeroStockItem,
}

class PdvV1CatalogEffectSpec {
  const PdvV1CatalogEffectSpec({
    required this.kind,
    required this.authoritativeSource,
    required this.computableFromRemote,
    required this.idempotencyKey,
    required this.safeReexecution,
    required this.blocksSaleSync,
    required this.blocksOperationCompleted,
  });

  final PdvV1CatalogEffectKind kind;
  final String authoritativeSource;
  final bool computableFromRemote;
  final String idempotencyKey;
  final bool safeReexecution;
  final bool blocksSaleSync;
  final bool blocksOperationCompleted;
}

const pdvV1ProdutosWriteDecisionFase65 =
    PdvV1ProdutosWriteInTxDecision.remainInMainTransactionAsProjection;

const pdvV1CatalogEffectSpecs = <PdvV1CatalogEffectSpec>[
  PdvV1CatalogEffectSpec(
    kind: PdvV1CatalogEffectKind.productProjection,
    authoritativeSource: 'estoque_produtos (TX)',
    computableFromRemote: true,
    idempotencyKey: 'operationId:product_projection:productId',
    safeReexecution: true,
    blocksSaleSync: false,
    blocksOperationCompleted: false,
  ),
  PdvV1CatalogEffectSpec(
    kind: PdvV1CatalogEffectKind.productCacheRefresh,
    authoritativeSource: 'estoque_produtos + TX result',
    computableFromRemote: true,
    idempotencyKey: 'operationId:product_cache:productId',
    safeReexecution: true,
    blocksSaleSync: false,
    blocksOperationCompleted: true,
  ),
  PdvV1CatalogEffectSpec(
    kind: PdvV1CatalogEffectKind.catalogProjection,
    authoritativeSource: 'produtos/draft_produtos',
    computableFromRemote: true,
    idempotencyKey: 'operationId:catalog:productId',
    safeReexecution: true,
    blocksSaleSync: false,
    blocksOperationCompleted: false,
  ),
  PdvV1CatalogEffectSpec(
    kind: PdvV1CatalogEffectKind.removalOfZeroStockItem,
    authoritativeSource: 'quantidadeTotal==0 pós-TX',
    computableFromRemote: true,
    idempotencyKey: 'productId:zero_removal',
    safeReexecution: true,
    blocksSaleSync: false,
    blocksOperationCompleted: false,
  ),
];

bool pdvV1ProjectionNeverMutatesStock({
  required bool invokesMainBaixa,
  required bool invokesEstorno,
  required bool createsNewSale,
}) {
  return !invokesMainBaixa && !invokesEstorno && !createsNewSale;
}
