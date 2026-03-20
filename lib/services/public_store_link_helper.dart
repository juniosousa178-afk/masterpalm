// lib/services/public_store_link_helper.dart
// Helper para montar links públicos do catálogo por loja.
// Garante que nenhum placeholder (minha-loja, store genérico) seja usado em links.

/// Valores que NUNCA devem aparecer em links públicos da loja.
const Set<String> _placeholdersInvalidos = {
  'minha-loja',
  'minha_loja',
  'masterpalm', // default antigo; nunca é loja do usuário
  'mastepalm', // typo
};

/// URL base do catálogo público (App Web).
const String kPublicCatalogBaseUrl = 'https://app.mastepalm.com.br/loja';

/// Verifica se [storeIdOrSlug] é válido para usar em link público.
/// Retorna false para null, vazio ou placeholder.
bool isValidForPublicLink(String? storeIdOrSlug) {
  if (storeIdOrSlug == null) return false;
  final s = storeIdOrSlug.trim().toLowerCase();
  if (s.isEmpty) return false;
  if (_placeholdersInvalidos.contains(s)) return false;
  return true;
}

/// Monta a URL do catálogo público da loja.
/// Retorna null se [storeIdOrSlug] for inválido (placeholder ou vazio).
String? buildPublicCatalogUrl(String? storeIdOrSlug) {
  if (!isValidForPublicLink(storeIdOrSlug)) return null;
  return '$kPublicCatalogBaseUrl/${Uri.encodeComponent(storeIdOrSlug!.trim())}';
}

/// Monta a URL de recuperação de carrinho: /loja/{id}?cart={cartId}.
/// Retorna null se [storeIdOrSlug] for inválido.
String? buildRecuperacaoCarrinhoUrl(String? storeIdOrSlug, String cartId) {
  if (!isValidForPublicLink(storeIdOrSlug) || cartId.trim().isEmpty) return null;
  final base = buildPublicCatalogUrl(storeIdOrSlug);
  if (base == null) return null;
  final sep = base.contains('?') ? '&' : '?';
  return '$base${sep}cart=${Uri.encodeComponent(cartId.trim())}';
}
