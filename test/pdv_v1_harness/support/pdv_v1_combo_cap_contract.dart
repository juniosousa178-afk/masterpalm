// Contrato de recovery combo cap — Fase 6.4 (design only).
// Espelha ComboKitStockService.maxKitsMontaveis + aplicarTetoEstoqueComboAposBaixa.
// Recovery NÃO pode chamar baixa principal novamente.

enum PdvV1ComboCapClass {
  /// Teto derivado dos componentes atuais — recomputável.
  derivedRecomputable,

  /// Exige subestado journal combo_cap_*.
  postProcessWithSubstate,

  /// Entra na TX principal (não adotado nesta fase).
  criticalInTransaction,

  /// Sem recovery seguro.
  blocksV1,
}

enum PdvV1ComboCapRecoveryDecision {
  skipAlreadyApplied,
  reapplyCapWithoutMainBaixa,
  manualInterventionRequired,
  noComboAffected,
}

class PdvV1ComboCapState {
  const PdvV1ComboCapState({
    required this.comboSkuQty,
    required this.maxKitsMontaveis,
    required this.substateCompleted,
    required this.operationId,
    this.lastCapOperationId,
  });

  final int comboSkuQty;
  final int maxKitsMontaveis;
  final bool substateCompleted;
  final String operationId;
  final String? lastCapOperationId;
}

/// Teto esperado = min(estoque componentes / qtd receita) — determinístico.
int pdvV1ComboCapTetoEsperado(int maxKitsMontaveis) => maxKitsMontaveis;

int pdvV1ComboCapDelta(int comboSkuQty, int teto) {
  if (comboSkuQty <= teto) return 0;
  return comboSkuQty - teto;
}

PdvV1ComboCapRecoveryDecision pdvV1DecidirComboCapRecovery({
  required PdvV1ComboCapState state,
  required bool baixaPrincipalConcluida,
  required bool journalIntegro,
}) {
  if (!baixaPrincipalConcluida || !journalIntegro) {
    return PdvV1ComboCapRecoveryDecision.manualInterventionRequired;
  }
  if (state.maxKitsMontaveis >= 999999) {
    return PdvV1ComboCapRecoveryDecision.noComboAffected;
  }
  if (state.substateCompleted &&
      state.lastCapOperationId == state.operationId) {
    return PdvV1ComboCapRecoveryDecision.skipAlreadyApplied;
  }
  final delta = pdvV1ComboCapDelta(state.comboSkuQty, state.maxKitsMontaveis);
  if (delta <= 0) {
    return PdvV1ComboCapRecoveryDecision.skipAlreadyApplied;
  }
  return PdvV1ComboCapRecoveryDecision.reapplyCapWithoutMainBaixa;
}

/// Aplicar teto duas vezes com mesmo estado pós-cap não deve debitar de novo.
bool pdvV1ComboCapDuplaAplicacaoSegura({
  required int comboQtyAfterFirstCap,
  required int maxKits,
}) {
  return pdvV1ComboCapDelta(comboQtyAfterFirstCap, maxKits) == 0;
}

const pdvV1ComboCapConclusaoFase64 = PdvV1ComboCapClass.postProcessWithSubstate;
