import 'package:flutter/foundation.dart';

/// Estado explícito da resolução do nome comercial da pill de loading.
///
/// `null` em [String?] não basta: distingue “ainda não tentou”, “a carregar”,
/// “terminou com nome”, “terminou sem nome” e “erro”.
enum CatalogLoaderNamePhase {
  unresolved,
  loading,
  resolvedWithName,
  resolvedWithoutName,
  errorFallback,
}

/// Snapshot sticky da resolução para um [lojaId].
@immutable
class CatalogLoaderNameResolution {
  const CatalogLoaderNameResolution({
    required this.lojaId,
    required this.phase,
    this.commercialName,
  });

  final String lojaId;
  final CatalogLoaderNamePhase phase;

  /// Só preenchido em [CatalogLoaderNamePhase.resolvedWithName].
  final String? commercialName;

  bool get isTerminal =>
      phase == CatalogLoaderNamePhase.resolvedWithName ||
      phase == CatalogLoaderNamePhase.resolvedWithoutName ||
      phase == CatalogLoaderNamePhase.errorFallback;

  /// Handoff HTML só após estado terminal (nome, sem nome, ou erro).
  bool get allowsHtmlHandoff => isTerminal;

  CatalogLoaderNameResolution copyWith({
    String? lojaId,
    CatalogLoaderNamePhase? phase,
    String? commercialName,
    bool clearCommercialName = false,
  }) {
    return CatalogLoaderNameResolution(
      lojaId: lojaId ?? this.lojaId,
      phase: phase ?? this.phase,
      commercialName:
          clearCommercialName ? null : (commercialName ?? this.commercialName),
    );
  }
}

/// Resolve slug da URL → lojaId canónico (injectável nos testes).
///
/// Produção: para a maioria das lojas públicas o slug da rota já é o doc id
/// (ex.: `crisdealbuquerque094`). O resolver pode atrasar/mapear se necessário.
typedef CatalogEarlySlugToLojaIdResolver = Future<String> Function(String slug);

/// Gate de lifetime: o catálogo final só pode substituir o early shell quando
/// o config já tem data **e** a resolução early-name está em fase **terminal**.
///
/// Não usar `commercialName != null` — lojas sem nome / erro também terminam.
bool catalogEarlyShellMayYieldToFinal({
  required bool configHasData,
  required CatalogLoaderNameResolution? nameResolution,
}) {
  if (!configHasData) return false;
  return nameResolution?.isTerminal ?? false;
}

/// Fallback visual de slug só após provar ausência de nome ou erro terminal.
bool catalogLoaderNamePhaseAllowsSlugFallback(CatalogLoaderNamePhase phase) {
  return phase == CatalogLoaderNamePhase.resolvedWithoutName ||
      phase == CatalogLoaderNamePhase.errorFallback;
}
