// lib/services/catalog_public_url_service.dart
// URL canônica do catálogo público (hosted vs domínio próprio).

import 'package:cloud_firestore/cloud_firestore.dart';

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

  static const List<String> _domainKeysForDraftOverlay = [
    'dominioCatalogo',
    'dominio_catalogo',
    'dominioStatus',
    'dominio_status',
    'dominioUpdatedAt',
    'dominioProvider',
  ];

  static bool _mergedDeclaresDomainState(Map<String, dynamic> merged) {
    final host =
        (merged['dominioCatalogo'] ?? merged['dominio_catalogo'] ?? '')
            .toString()
            .trim();
    final st =
        (merged['dominioStatus'] ?? merged['dominio_status'] ?? '')
            .toString()
            .trim();
    return host.isNotEmpty || st.isNotEmpty;
  }

  /// Evita perder domínio vindo de [mergeDraftConfigDomainForCatalogUrls] quando
  /// o stream de `config` ainda não inclui essas chaves.
  static Map<String, dynamic> coalesceCatalogUrlConfig(
    Map<String, dynamic> rawCfgFromStream,
    Map<String, dynamic>? previousMerged,
  ) {
    final merged = mergeStoreConfigForCatalogUrls(rawCfgFromStream);
    if (tryCustomCatalogPublicRoot(merged) != null) return merged;
    if (previousMerged == null || previousMerged.isEmpty) return merged;
    if (_mergedDeclaresDomainState(merged)) return merged;
    if (tryCustomCatalogPublicRoot(previousMerged) == null) return merged;
    final out = Map<String, dynamic>.from(merged);
    for (final k in _domainKeysForDraftOverlay) {
      if (previousMerged.containsKey(k)) out[k] = previousMerged[k];
    }
    if (tryCustomCatalogPublicRoot(out) != null) return out;
    return merged;
  }

  /// Quando [lojas/{id}/config/config] ainda não reflete o domínio (ex.: só em
  /// `draft_config`), mescla só as chaves de domínio do rascunho se o resultado
  /// for URL própria **ativa** — não sobrescreve domínio já válido em [merged].
  static Future<Map<String, dynamic>> mergeDraftConfigDomainForCatalogUrls(
    String lojaId,
    Map<String, dynamic> merged,
  ) async {
    if (tryCustomCatalogPublicRoot(merged) != null) return merged;
    final id = lojaId.trim();
    if (id.isEmpty) return merged;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('lojas')
          .doc(id)
          .collection('draft_config')
          .doc('config')
          .get();
      if (!snap.exists) return merged;
      final flat = Map<String, dynamic>.from(snap.data() ?? {});
      final overlay = <String, dynamic>{};
      for (final k in _domainKeysForDraftOverlay) {
        if (!flat.containsKey(k) || flat[k] == null) continue;
        final asStr = flat[k].toString().trim();
        if (asStr.isEmpty) continue;
        overlay[k] = flat[k];
      }
      if (overlay.isEmpty) return merged;
      final combined = Map<String, dynamic>.from(merged)..addAll(overlay);
      if (tryCustomCatalogPublicRoot(combined) != null) return combined;
    } catch (_) {
      // Mantém [merged] (hosted).
    }
    return merged;
  }

  /// Só [kDominioStatusAtivo] habilita URL pública no domínio próprio; demais
  /// estados (incl. [kDominioStatusDnsOk]) usam o hosted padrão.
  static bool _catalogCustomDomainIsActive(Map<String, dynamic> cfg) {
    final st =
        (cfg['dominioStatus'] ?? cfg['dominio_status'] ?? '').toString().trim();
    return st.toLowerCase() == kDominioStatusAtivo;
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
      var merged = mergeStoreConfigForCatalogUrls(doc);
      merged = await mergeDraftConfigDomainForCatalogUrls(id, merged);
      return montarUrlCatalogoPublico(
        lojaConfig: merged,
        lojaId: id,
        slug: slug,
      );
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
