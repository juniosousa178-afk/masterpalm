import 'store_display_name_resolver.dart';

/// Nome da pill em "Preparando sua loja..." — nome comercial quando existir.
///
/// Hierarquia:
/// 1. nome comercial já resolvido (`nome` / `nomeLoja` / `name` / equivalentes)
/// 2. fallback de slug (mesmo algoritmo do `#initial-loader` em `web/index.html`)
/// 3. `Catálogo`
///
/// Não trata document ID / `lojaId` / slug como nome comercial editável.
abstract final class CatalogLoadingStoreName {
  static const fallbackCatalogLabel = 'Catálogo';

  /// Preferência única e genérica (sem hardcode de cliente).
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
