// Decisão pura de roteamento web inicial (MyApp vs catálogo) — testável, sem I/O.
// O domínio oficial [AppUrls.isDefaultMasterPalmCatalogHost] **não** é domínio próprio
// de loja: a raiz `/` nunca deve ser classificada como "loja não configurada".

import 'package:master_palm/config/app_urls.dart';

/// Slug reservado / inválido — nunca tratar como loja real.
const String kInvalidPlaceholderLojaSlug = 'minha-loja';

/// Resultado lógico do primeiro frame (antes de `catalog_domains` assíncrono, quando aplicável).
enum CatalogInitialRouteKind {
  /// [_BootApp] / [MyApp] (admin, login, home).
  appRoot,

  /// Fast path: `/loja/{slug}` com slug utilizável.
  publicCatalogByLojaPath,

  /// Legado: `?loja=` / `?slug=` / `?store_id=` (e fragment) no host do app.
  publicCatalogByLegacyQuery,

  /// `/loja/...` sem slug válido ou `minha-loja` (não abrir catálogo com id vazio).
  lojaPathOrSlugInvalid,

  /// Query legada com slug vazio ou placeholder.
  legacyQueryInvalid,

  /// Host próprio: aguarda leitura Firestore `catalog_domains` no [main].
  customDomainAwaitingFirestore,

  /// Host próprio com mapeamento — catálogo na raiz.
  customDomainPublicCatalog,

  /// Host candidato a domínio loja, sem mapeamento.
  customDomainNotConfigured,
}

class CatalogRouteDecision {
  const CatalogRouteDecision._({
    required this.kind,
    this.extractedSlugOrId,
  });

  final CatalogInitialRouteKind kind;
  final String? extractedSlugOrId;

  static const _root = CatalogRouteDecision._(kind: CatalogInitialRouteKind.appRoot);

  static CatalogRouteDecision _legacyQuery(String? slug) {
    final t = (slug ?? '').trim();
    if (t.isEmpty) {
      return const CatalogRouteDecision._(
        kind: CatalogInitialRouteKind.legacyQueryInvalid,
      );
    }
    if (t.toLowerCase() == kInvalidPlaceholderLojaSlug) {
      return const CatalogRouteDecision._(
        kind: CatalogInitialRouteKind.legacyQueryInvalid,
      );
    }
    return CatalogRouteDecision._(
      kind: CatalogInitialRouteKind.publicCatalogByLegacyQuery,
      extractedSlugOrId: t,
    );
  }

  static CatalogRouteDecision fromUri(
    Uri uri, {
    required bool Function(String host) isDefaultAppOrCatalogHostingHost,
    bool Function(String host)? isPublicMarketingHost,
    /// Só usado fora do host default, quando a resolução **já** veio (ex. testes).
    bool? customDomainMappingResolved,
  }) {
    if (_uriIsPagamentoPublicPath(uri)) {
      return _root;
    }

    final host = AppUrls.normalizeHostForAppUrlCheck(uri.host);
    if (isDefaultAppOrCatalogHostingHost(host)) {
      return _decideForDefaultAppOrHostingHost(uri);
    }

    final isMarketing = isPublicMarketingHost != null && isPublicMarketingHost(host);
    if (isMarketing) {
      return const CatalogRouteDecision._(kind: CatalogInitialRouteKind.appRoot);
    }

    if (_uriHasLojaPathPriority(uri)) {
      final s = _extractLojaSlugFromPathQueryFragment(uri);
      if (s.isEmpty || s.toLowerCase() == kInvalidPlaceholderLojaSlug) {
        return const CatalogRouteDecision._(
          kind: CatalogInitialRouteKind.lojaPathOrSlugInvalid,
        );
      }
      return CatalogRouteDecision._(
        kind: CatalogInitialRouteKind.publicCatalogByLojaPath,
        extractedSlugOrId: s,
      );
    }
    if (_uriHasExplicitCatalogQueryOrFragment(uri)) {
      return _legacyQuery(_readLegacySlugFromQueryOrFragment(uri));
    }

    if (customDomainMappingResolved == null) {
      return const CatalogRouteDecision._(
        kind: CatalogInitialRouteKind.customDomainAwaitingFirestore,
      );
    }
    if (customDomainMappingResolved) {
      return const CatalogRouteDecision._(
        kind: CatalogInitialRouteKind.customDomainPublicCatalog,
      );
    }
    return const CatalogRouteDecision._(
      kind: CatalogInitialRouteKind.customDomainNotConfigured,
    );
  }

  static CatalogRouteDecision _decideForDefaultAppOrHostingHost(Uri uri) {
    if (_uriHasLojaPathPriority(uri)) {
      final s = _extractLojaSlugFromPathQueryFragment(uri);
      if (s.isEmpty || s.toLowerCase() == kInvalidPlaceholderLojaSlug) {
        return const CatalogRouteDecision._(
          kind: CatalogInitialRouteKind.lojaPathOrSlugInvalid,
        );
      }
      return CatalogRouteDecision._(
        kind: CatalogInitialRouteKind.publicCatalogByLojaPath,
        extractedSlugOrId: s,
      );
    }
    if (_uriHasExplicitCatalogQueryOrFragment(uri)) {
      return _legacyQuery(_readLegacySlugFromQueryOrFragment(uri));
    }
    return _root;
  }
}

String _readLegacySlugFromQueryOrFragment(Uri uri) {
  var raw = (uri.queryParameters['loja'] ??
          uri.queryParameters['slug'] ??
          uri.queryParameters['store_id'] ??
          '')
      .trim();
  if (raw.isNotEmpty) return raw;
  final f = _lojaSlugFromFragmentStatic(uri.fragment);
  return f ?? '';
}

String _extractLojaSlugFromPathQueryFragment(Uri uri) {
  final path = uri.path;
  if (path.startsWith('/loja/')) {
    final after = path.substring('/loja/'.length).trim();
    final slug = after.split('/').first.trim();
    if (slug.isNotEmpty) return slug;
  }
  if (uri.pathSegments.length >= 2 && uri.pathSegments.first == 'loja') {
    return uri.pathSegments[1].trim();
  }
  if (path == '/loja' || (uri.pathSegments.length == 1 && uri.pathSegments.first == 'loja')) {
    // Sem segmento de loja após "loja"
    return '';
  }
  return _readLegacySlugFromQueryOrFragment(uri);
}

bool _uriIsPagamentoPublicPath(Uri uri) {
  final p = uri.path;
  return p.startsWith('/pagamento') || p.contains('/pagamento/');
}

/// Espelha [ _uriHasLojaPathPriority ] de main.dart
bool _uriHasLojaPathPriority(Uri uri) {
  final path = uri.path;
  if (path.startsWith('/loja/') || path.contains('/loja/')) return true;
  if (uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'loja') {
    return true;
  }
  return false;
}

bool _uriHasExplicitCatalogQueryOrFragment(Uri uri) {
  if (uri.queryParameters.containsKey('loja') ||
      uri.queryParameters.containsKey('slug') ||
      uri.queryParameters.containsKey('store_id')) {
    return true;
  }
  final frag = uri.fragment.trim();
  return frag.contains('loja/') || frag.startsWith('/loja/');
}

String? _lojaSlugFromFragmentStatic(String fragment) {
  final s = fragment.trim();
  if (s.isEmpty) return null;
  final withoutHash = s.startsWith('#') ? s.substring(1) : s;
  final parts = withoutHash.split('/').where((e) => e.isNotEmpty).toList();
  if (parts.length >= 2 && parts[0] == 'loja') {
    final slug = parts[1].trim();
    if (slug.isNotEmpty) return slug;
  }
  return null;
}

