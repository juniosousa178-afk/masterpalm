// lib/services/public_store_link_helper.dart
// Helper para montar links públicos do catálogo por loja.
// Garante que nenhum placeholder (minha-loja, store genérico) seja usado em links.

import 'catalog_public_url_service.dart';

/// URL base do catálogo público (App Web), sem slug.
const String kPublicCatalogBaseUrl =
    CatalogPublicUrlService.kDefaultCatalogPublicBase;

/// Verifica se [storeIdOrSlug] é válido para usar em link público hosted.
/// Retorna false para null, vazio ou placeholder.
bool isValidForPublicLink(String? storeIdOrSlug) {
  return CatalogPublicUrlService.isValidStoreIdForHostedCatalogPath(
    storeIdOrSlug,
  );
}

/// Monta a URL do catálogo público da loja.
/// Retorna null se [storeIdOrSlug] for inválido (placeholder ou vazio) e não for possível montar path hosted.
///
/// [catalogConfig]: mapa mesclado (ex.: [CatalogPublicUrlService.mergeStoreConfigForCatalogUrls])
/// para respeitar domínio próprio quando ativo.
String? buildPublicCatalogUrl(
  String? storeIdOrSlug, {
  Map<String, dynamic>? catalogConfig,
}) {
  if (storeIdOrSlug == null) return null;
  final trimmed = storeIdOrSlug.trim();
  if (trimmed.isEmpty) return null;

  if (catalogConfig != null && catalogConfig.isNotEmpty) {
    return CatalogPublicUrlService.montarUrlCatalogoPublico(
      lojaConfig: catalogConfig,
      lojaId: trimmed,
    );
  }

  if (!isValidForPublicLink(trimmed)) return null;
  return CatalogPublicUrlService.montarUrlCatalogoPublico(
    lojaConfig: const {},
    lojaId: trimmed,
  );
}

/// Monta a URL de recuperação de carrinho: base do catálogo + `?cart=`.
/// Retorna null se [storeIdOrSlug] for inválido para o modo hosted e não houver [catalogConfig].
String? buildRecuperacaoCarrinhoUrl(
  String? storeIdOrSlug,
  String cartId, {
  Map<String, dynamic>? catalogConfig,
}) {
  if (cartId.trim().isEmpty) return null;
  final base = buildPublicCatalogUrl(
    storeIdOrSlug,
    catalogConfig: catalogConfig,
  );
  if (base == null) return null;
  final sep = base.contains('?') ? '&' : '?';
  return '$base${sep}cart=${Uri.encodeComponent(cartId.trim())}';
}

/// Mesmo que [buildRecuperacaoCarrinhoUrl], lendo domínio próprio em Firestore quando aplicável.
Future<String?> buildRecuperacaoCarrinhoUrlAsync(
  String storeIdOrSlug,
  String cartId,
) async {
  if (cartId.trim().isEmpty) return null;
  final base = await CatalogPublicUrlService.montarUrlCatalogoPublicoAsync(
    storeIdOrSlug.trim(),
  );
  final sep = base.contains('?') ? '&' : '?';
  return '$base${sep}cart=${Uri.encodeComponent(cartId.trim())}';
}
