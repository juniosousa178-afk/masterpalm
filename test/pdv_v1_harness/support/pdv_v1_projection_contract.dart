// Contrato de projeção produtos/catálogo/Hive — Fase 6.4 (design only).

enum PdvV1ProjectionKind {
  estoqueProdutos,
  produtosFirestore,
  hiveProdutos,
  catalogoWeb,
  remocaoZerado,
}

enum PdvV1ProjectionRecoveryDecision {
  reprojectFromAuthoritative,
  skipAlreadyProjected,
  manualInterventionRequired,
  noOp,
}

class PdvV1ProjectionState {
  const PdvV1ProjectionState({
    required this.kind,
    required this.productId,
    required this.operationId,
    required this.substateCompleted,
    this.lastProjectedOperationId,
  });

  final PdvV1ProjectionKind kind;
  final String productId;
  final String operationId;
  final bool substateCompleted;
  final String? lastProjectedOperationId;
}

String pdvV1ProjectionIdempotencyKey({
  required PdvV1ProjectionKind kind,
  required String operationId,
  required String productId,
}) {
  return '$operationId:${kind.name}:$productId';
}

/// Fonte autoritativa do estoque: estoque_produtos (TX principal).
/// Documento produtos na TX atual é projeção de catálogo, não estoque autoritativo.
bool pdvV1ProjectionIsAuthoritative(PdvV1ProjectionKind kind) {
  return kind == PdvV1ProjectionKind.estoqueProdutos;
}

PdvV1ProjectionRecoveryDecision pdvV1DecidirProjectionRecovery({
  required PdvV1ProjectionState state,
  required bool baixaPrincipalConcluida,
  required bool journalIntegro,
}) {
  if (!baixaPrincipalConcluida || !journalIntegro) {
    return PdvV1ProjectionRecoveryDecision.manualInterventionRequired;
  }
  if (state.substateCompleted &&
      state.lastProjectedOperationId == state.operationId) {
    return PdvV1ProjectionRecoveryDecision.skipAlreadyProjected;
  }
  if (pdvV1ProjectionIsAuthoritative(state.kind)) {
    return PdvV1ProjectionRecoveryDecision.noOp;
  }
  return PdvV1ProjectionRecoveryDecision.reprojectFromAuthoritative;
}

/// Retry de projeção não cria nova venda nem novo débito de estoque principal.
bool pdvV1ProjectionRetrySeguro({
  required bool invocaBaixaPrincipal,
  required bool invocaNovaVenda,
}) {
  return !invocaBaixaPrincipal && !invocaNovaVenda;
}

/// sync_completed: catálogo pode atrasar; bloqueia apenas se política exigir projeção remota.
bool pdvV1CatalogProjectionBloqueiaSyncCompleted({
  required bool syncRemoteCompleted,
  required bool catalogProjectionCompleted,
  required bool policyRequiresCatalogBeforeSync,
}) {
  if (!syncRemoteCompleted) return true;
  if (policyRequiresCatalogBeforeSync && !catalogProjectionCompleted) {
    return true;
  }
  return false;
}
