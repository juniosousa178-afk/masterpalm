// Chaves persistidas em layoutCatalogo (Firestore). Não renomear valores.

abstract final class CatalogLayoutConfig {
  static const String classic = 'padrao';
  static const String minimal = 'minimalista_nuvemshop';

  /// Catálogo público quando o campo não existe: preserva lojas antigas.
  static const String publicFallbackWhenUnset = classic;

  /// Valor gravado em lojas novas (draft_config + config na criação).
  static const String defaultForNewStoreDocuments = minimal;

  static String normalize(dynamic raw) {
    final v = (raw ?? '').toString().trim().toLowerCase();
    if (v == minimal) return minimal;
    if (v.isEmpty) return publicFallbackWhenUnset;
    return classic;
  }

  static bool isMinimal(String layout) => layout == minimal;
}
