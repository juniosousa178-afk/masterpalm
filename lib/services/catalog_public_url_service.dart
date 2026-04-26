// lib/services/catalog_public_url_service.dart
// URL canônica do catálogo público (hosted vs domínio próprio).

import '../catalog/domain/catalog_custom_domain.dart';
import 'store_config_service.dart';

/// Links públicos do catálogo devem passar por este helper. Domínio próprio só
/// entra na URL quando [dominioStatus] é [kDominioStatusAtivo] (ex.: `dns_ok`
/// continua só na configuração, não no link público). Caso contrário, preservar
/// o link padrão atual para não quebrar lojas antigas.
class CatalogPublicUrlService {
  CatalogPublicUrlService._();

  /// Base do catálogo no App Web (sem slug): `https://app.mastepalm.com.br/loja`
  static const String kDefaultCatalogPublicBase =
      'https://app.mastepalm.com.br/loja';

  static const Set<String> _invalidSlugPlaceholders = {
    'minha-loja',
    'minha_loja',
    'masterpalm',
    'mastepalm',
  };

  /// Slug/id utilizável no path `/loja/{id}` no hosting padrão.
  static bool isValidStoreIdForHostedCatalogPath(String? storeIdOrSlug) {
    if (storeIdOrSlug == null) return false;
    final s = storeIdOrSlug.trim().toLowerCase();
    if (s.isEmpty) return false;
    if (_invalidSlugPlaceholders.contains(s)) return false;
    return true;
  }

  /// Mescla `draft` + `published` do doc [lojas/{id}/config/config] e chaves
  /// planas de domínio na raiz, para leitura de [dominioCatalogo] / [dominioStatus].
  static Map<String, dynamic> mergeStoreConfigForCatalogUrls(
    Map<String, dynamic> rawConfigDoc,
  ) {
    Map<String, dynamic> mapFrom(dynamic v) {
      if (v is Map) {
        return Map<String, dynamic>.from(
          v.map((k, val) => MapEntry(k.toString(), val)),
        );
      }
      return {};
    }

    final draft = mapFrom(rawConfigDoc['draft']);
    final published = mapFrom(rawConfigDoc['published']);
    final out = <String, dynamic>{...draft, ...published};
    for (final k in const [
      'dominioCatalogo',
      'dominioStatus',
      'dominio_catalogo',
      'dominio_status',
    ]) {
      if (rawConfigDoc.containsKey(k)) {
        out[k] = rawConfigDoc[k];
      }
    }
    return out;
  }

  /// Só [kDominioStatusAtivo] habilita URL pública no domínio próprio; demais
  /// estados (incl. [kDominioStatusDnsOk]) usam o hosted padrão.
  static bool _catalogCustomDomainIsActive(Map<String, dynamic> cfg) {
    final st =
        (cfg['dominioStatus'] ?? cfg['dominio_status'] ?? '').toString().trim();
    return st == kDominioStatusAtivo;
  }

  /// Retorna `https://host` sem barra final ou null se inválido / inativo.
  static String? tryCustomCatalogPublicRoot(Map<String, dynamic> lojaConfig) {
    if (!_catalogCustomDomainIsActive(lojaConfig)) return null;
    final raw =
        (lojaConfig['dominioCatalogo'] ?? lojaConfig['dominio_catalogo'] ?? '')
            .toString()
            .trim();
    final host = normalizeCatalogDomainInput(raw);
    if (host.isEmpty) return null;
    final lower = host.toLowerCase();
    if (lower == 'null' || lower == 'undefined') return null;
    if (!host.contains('.')) return null;
    return 'https://$host';
  }

  /// Monta a URL base do catálogo (hosted `/loja/slug` ou raiz do domínio próprio).
  static String montarUrlCatalogoPublico({
    required Map<String, dynamic> lojaConfig,
    required String lojaId,
    String? slug,
  }) {
    final custom = tryCustomCatalogPublicRoot(lojaConfig);
    if (custom != null) return custom;

    final id = (slug ?? lojaId).trim();
    if (id.isEmpty) {
      final fallback = lojaId.trim();
      if (fallback.isEmpty) return kDefaultCatalogPublicBase;
      return '$kDefaultCatalogPublicBase/${Uri.encodeComponent(fallback)}';
    }
    if (!isValidStoreIdForHostedCatalogPath(id)) {
      return '$kDefaultCatalogPublicBase/${Uri.encodeComponent(lojaId.trim())}';
    }
    return '$kDefaultCatalogPublicBase/${Uri.encodeComponent(id)}';
  }

  /// Lê Firestore `config/config` e aplica [montarUrlCatalogoPublico] (published sobrescreve draft).
  static Future<String> montarUrlCatalogoPublicoAsync(
    String lojaId, {
    String? slug,
  }) async {
    final id = lojaId.trim();
    if (id.isEmpty) {
      final s = slug?.trim();
      if (s == null || s.isEmpty) return kDefaultCatalogPublicBase;
      return montarUrlCatalogoPublico(lojaConfig: const {}, lojaId: s, slug: s);
    }
    try {
      final doc = await StoreConfigService.getConfigDoc(lojaId: id);
      final merged = mergeStoreConfigForCatalogUrls(doc);
      return montarUrlCatalogoPublico(
          lojaConfig: merged, lojaId: id, slug: slug);
    } catch (_) {
      final s = (slug ?? id).trim();
      if (isValidStoreIdForHostedCatalogPath(s)) {
        return '$kDefaultCatalogPublicBase/${Uri.encodeComponent(s)}';
      }
      return '$kDefaultCatalogPublicBase/${Uri.encodeComponent(id)}';
    }
  }

  static String withQueryParameters(
    String catalogUrl,
    Map<String, String> query,
  ) {
    if (query.isEmpty) return catalogUrl;
    final uri = Uri.parse(catalogUrl);
    final merged = Map<String, String>.from(uri.queryParameters);
    for (final e in query.entries) {
      if (e.value.isNotEmpty) merged[e.key] = e.value;
    }
    return uri.replace(queryParameters: merged).toString();
  }
}
