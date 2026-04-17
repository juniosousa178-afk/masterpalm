// Resolução de produto para deep link (?prod / initialProdutoId) no catálogo público.
// Extraído de PublicCatalogScreen para teste sem montar a tela inteira.

import '../../utils/safe_parse.dart';

String _normalizeCatalogProdutoDeepLinkKey(String raw) {
  return raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}

/// Mesma regra que [PublicCatalogScreen] usava em `_matchesProdutoDeepLink`.
bool catalogProdutoMatchesDeepLinkTarget(
  Map<String, dynamic> produto,
  String target,
) {
  final id = safeStr(produto['id']).trim();
  final slug = safeStr(produto['slug']).trim();
  if (id.isNotEmpty && id == target) return true;
  if (slug.isNotEmpty && slug == target) return true;
  final normalizedTarget = _normalizeCatalogProdutoDeepLinkKey(target);
  return (id.isNotEmpty &&
          _normalizeCatalogProdutoDeepLinkKey(id) == normalizedTarget) ||
      (slug.isNotEmpty &&
          _normalizeCatalogProdutoDeepLinkKey(slug) == normalizedTarget);
}

/// Primeiro produto da lista que casa com o alvo, ou null (inexistente / alvo vazio).
Map<String, dynamic>? resolveCatalogDeepLinkProduct({
  required List<Map<String, dynamic>> produtos,
  required String? targetRaw,
}) {
  final target = targetRaw?.trim();
  if (target == null || target.isEmpty) return null;
  if (produtos.isEmpty) return null;
  for (final p in produtos) {
    if (catalogProdutoMatchesDeepLinkTarget(p, target)) return p;
  }
  return null;
}
