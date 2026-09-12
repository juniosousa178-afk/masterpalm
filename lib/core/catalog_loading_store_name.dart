import 'store_display_name_resolver.dart';

/// Nome da pill em "Preparando sua loja..." — nome comercial quando existir.
///
/// Hierarquia:
/// 1. nome comercial já resolvido (`nome` / `nomeLoja` / `name` / equivalentes)
/// 2. fallback de slug **só** quando [allowSlugFallback] (fase terminal sem nome/erro)
/// 3. `Catálogo`
///
/// Não trata document ID / `lojaId` / slug como nome comercial editável.
/// Em unresolved/loading a UI passa `allowSlugFallback: false` → pill ocultável.
abstract final class CatalogLoadingStoreName {
  static const fallbackCatalogLabel = 'Catálogo';

  /// Preferência única e genérica (sem hardcode de cliente).
  ///
  /// Usa fallback de slug quando não há nome comercial. Preferir
  /// [resolveVisiblePillLabel] na UI de loading (gate por fase).
  static String resolvePillLabel({
    String? commercialName,
    String? slug,
  }) {
    final commercial = StoreDisplayNameResolver.normalizeCandidate(commercialName);
    if (commercial != null &&
        !StoreDisplayNameResolver.isWeakPlaceholder(commercial)) {
      return commercial;
    }
    return slugToStoreNameFallback(slug);
  }

  /// Label **visível** da pill durante early shell / HTML loader.
  ///
  /// - Comercial válido → sempre mostra (inclui cache HTML durante loading).
  /// - Sem comercial e `allowSlugFallback == false` → `null` (não expor slug).
  /// - Sem comercial e `allowSlugFallback == true` → fallback de slug.
  static String? resolveVisiblePillLabel({
    required bool allowSlugFallback,
    String? commercialName,
    String? slug,
  }) {
    final commercial = StoreDisplayNameResolver.normalizeCandidate(commercialName);
    if (commercial != null &&
        !StoreDisplayNameResolver.isWeakPlaceholder(commercial)) {
      return commercial;
    }
    if (!allowSlugFallback) return null;
    return slugToStoreNameFallback(slug);
  }

  /// Espelha `slugToStoreName` de `web/index.html` (só fallback visual).
  static String slugToStoreNameFallback(String? slug) {
    final s = (slug ?? '').trim();
    if (s.isEmpty) return fallbackCatalogLabel;
    final parts = s.split('-').where((w) => w.isNotEmpty);
    if (parts.isEmpty) return fallbackCatalogLabel;
    return parts.map((w) {
      if (w.isEmpty) return w;
      return '${w[0].toUpperCase()}${w.substring(1)}';
    }).join(' ');
  }

  /// Extrai nome comercial de mapas de loja/config (nunca id/slug).
  static String? pickCommercialName(Map<dynamic, dynamic>? data) {
    return StoreDisplayNameResolver.pickFromLojaMap(data);
  }
}
