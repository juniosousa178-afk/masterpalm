// Combo cap: recálculo de teto ABSOLUTO idempotente — Fase 6.5 design.
// NÃO usa modelo de delta repetido.

enum PdvV1ComboCapAbsoluteConclusion {
  /// TX separada grava quantidade absoluta = maxKitsMontaveis.
  absoluteRecomputeInSeparateTx,
}

class PdvV1ComboCapAbsolutePlan {
  const PdvV1ComboCapAbsolutePlan({
    required this.comboId,
    required this.operationId,
    required this.componentStockRemote,
    required this.recipeQtyPerKit,
    required this.currentComboQtyRemote,
  });

  final String comboId;
  final String operationId;
  final List<int> componentStockRemote;
  final List<int> recipeQtyPerKit;
  final int currentComboQtyRemote;
}

int pdvV1MaxKitsFromRemoteComponents({
  required List<int> componentStock,
  required List<int> recipeQty,
}) {
  if (componentStock.isEmpty || recipeQty.isEmpty) return 0;
  var minKits = 999999;
  for (var i = 0; i < componentStock.length; i++) {
    final need = recipeQty[i].clamp(1, 9999);
    final kits = componentStock[i] ~/ need;
    if (kits < minKits) minKits = kits;
  }
  return minKits == 999999 ? 0 : minKits;
}

/// Teto absoluto esperado — idempotente: mesma entrada → mesmo valor.
int pdvV1ComboCapAbsoluteTarget(PdvV1ComboCapAbsolutePlan plan) {
  return pdvV1MaxKitsFromRemoteComponents(
    componentStock: plan.componentStockRemote,
    recipeQty: plan.recipeQtyPerKit,
  );
}

/// Gravação idempotente: set quantidade = target (não subtract delta).
int pdvV1ComboCapWriteValue({
  required int currentRemoteQty,
  required int absoluteTarget,
}) {
  if (currentRemoteQty <= absoluteTarget) return currentRemoteQty;
  return absoluteTarget;
}

String pdvV1ComboCapEffectKey({
  required String operationId,
  required String comboId,
}) =>
    '$operationId:combo_cap:$comboId';

/// Repetir após crash com mesmos componentes remotos → mesmo target, write no-op.
bool pdvV1ComboCapReexecucaoSegura({
  required int targetFirstRun,
  required int targetSecondRun,
  required int qtyAfterFirstWrite,
}) {
  if (targetFirstRun != targetSecondRun) return false;
  return qtyAfterFirstWrite <= targetFirstRun;
}

const pdvV1ComboCapConclusaoFase65 =
    PdvV1ComboCapAbsoluteConclusion.absoluteRecomputeInSeparateTx;
