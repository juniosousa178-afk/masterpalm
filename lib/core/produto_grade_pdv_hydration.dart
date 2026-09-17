// Contratos de readiness do seletor de grade/variação no PDV.
// Separação semântica: dados incompletos ≠ authoritative NO_VARIATION.

import '../models/produto.dart';

/// Estados de prontidão do seletor de grade/variação (PDV).
enum GradePdvReadiness {
  /// Snapshot local incompleto / ainda não decidido.
  unknown,

  /// Hidratação pontual em andamento — nunca tratar como NO_VARIATION.
  hydrating,

  /// Estado autoritativo com variação ou grade.
  readyWithVariation,

  /// Estado autoritativo sem variação (fluxo SIMPLE permitido).
  readyWithoutVariation,

  /// Offline/falha com snapshot parcial — bloquear fallback SIMPLE.
  offlinePartial,
}

/// Chave estável loja+produto para hidratação / dedupe / isolamento cross-store.
String gradePdvHydrationKey(String lojaId, String productId) {
  return '${lojaId.trim()}|${productId.trim()}';
}

/// ID canónico do produto para binding (idFirebase, senão slug).
String? gradePdvProductId(Produto produto) {
  final id = produto.idFirebase.trim();
  if (id.isNotEmpty) return id;
  final slug = produto.slug.trim();
  if (slug.isNotEmpty) return slug;
  return null;
}

/// Sinal positivo local de grade/variação (suficiente para EXIBIR seletor).
bool gradePdvHasLocalVariationSignal(Produto produto) {
  return produto.usaVariacoes ||
      produto.estoquePorTamanho.isNotEmpty ||
      produto.temVariacaoSoloCor;
}

/// Política central: campos de grade estão autoritativos o bastante para decidir
/// visibilidade do seletor / fallback SIMPLE.
///
/// Invariante: `usaVariacoes=false` + `estoquePorTamanho={}` NÃO são
/// autoritativos para NO_VARIATION enquanto [sessionHydratedAuthoritative]
/// for false.
bool isGradeProductHydrationComplete(
  Produto produto, {
  required bool sessionHydratedAuthoritative,
}) {
  if (gradePdvHasLocalVariationSignal(produto)) return true;
  return sessionHydratedAuthoritative;
}

/// Avalia readiness a partir do snapshot + fase de hidratação.
GradePdvReadiness evaluateGradePdvReadiness({
  required Produto? produto,
  required bool sessionHydratedAuthoritative,
  required bool hydrating,
  required bool hydrationFailedOrOfflinePartial,
}) {
  if (hydrating) return GradePdvReadiness.hydrating;

  if (produto != null && gradePdvHasLocalVariationSignal(produto)) {
    return GradePdvReadiness.readyWithVariation;
  }

  if (produto != null &&
      isGradeProductHydrationComplete(
        produto,
        sessionHydratedAuthoritative: sessionHydratedAuthoritative,
      )) {
    return GradePdvReadiness.readyWithoutVariation;
  }

  if (hydrationFailedOrOfflinePartial) {
    return GradePdvReadiness.offlinePartial;
  }

  return GradePdvReadiness.unknown;
}

/// Resultado de uma hidratação pontual (testável / UI).
class GradePdvHydrationResult {
  const GradePdvHydrationResult({
    required this.lojaId,
    required this.productId,
    required this.readiness,
    this.produto,
    this.errorMessage,
  });

  final String lojaId;
  final String productId;
  final GradePdvReadiness readiness;
  final Produto? produto;
  final String? errorMessage;

  bool get isReadyWithVariation =>
      readiness == GradePdvReadiness.readyWithVariation;
  bool get isReadyWithoutVariation =>
      readiness == GradePdvReadiness.readyWithoutVariation;
  bool get isBlockingOfflinePartial =>
      readiness == GradePdvReadiness.offlinePartial;
}
