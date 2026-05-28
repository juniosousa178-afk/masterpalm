/// URLs centralizadas do AppWeb MasterPalm.
///
/// **Canônico (produção real do SPA admin):** [appWebHostCanonical] → [appWebBase].
/// **Compatibilidade temporária:** [appWebHostLegacyTypo] (`app.masterpalm.com.br` — grafia
/// com “master” + R extra); mantido em [appWebHostsAll] para App Check / deep links / CORS
/// até migração total de DNS e bookmarks. Ver `docs/DOMAIN_APP_WEB.md`.
///
/// Landing / site público (hosting): [landingBase] (`gestao.mastepalm.com.br` — não o app admin).
class AppUrls {
  AppUrls._();

  /// Host canônico do App Web (produção: `https://app.mastepalm.com.br`).
  static const String appWebHostCanonical = 'app.mastepalm.com.br';

  /// Host de compatibilidade temporária (grafia alternativa); manter enquanto houver tráfego.
  static const String appWebHostLegacyTypo = 'app.masterpalm.com.br';

  /// Lista para checagens de host (ordem: canônico primeiro).
  static const List<String> appWebHostsAll = [
    appWebHostCanonical,
    appWebHostLegacyTypo,
  ];

  /// URL base do App Web admin (SPA).
  static const String appWebBase = 'https://$appWebHostCanonical';

  /// Host do site público (catálogo curto / landing no mesmo hosting do Firebase).
  static const String publicSiteHost = 'gestao.mastepalm.com.br';

  /// URL base do site público (antes: mastepalm.com.br).
  static const String landingBase = 'https://$publicSiteHost';

  /// Hosts HTTPS aceitos como “site público” (deep links + legado).
  static const List<String> publicSiteHostsAll = [
    publicSiteHost,
    'www.gestao.mastepalm.com.br',
    'mastepalm.com.br',
    'www.mastepalm.com.br',
  ];

  /// Site institucional (marketing) — **não** o SPA admin em [appWebHostsAll].
  static bool isPublicMarketingHost(String host) {
    final h = host.trim().toLowerCase();
    return publicSiteHostsAll.contains(h);
  }

  /// Hosting Firebase do catálogo (CNAME público) — mesmo app Web, fluxo padrão `/loja/`.
  static const String catalogFirebaseHostingHost = 'masterpalm-58c46.web.app';

  /// Preview channel do target admin (`masterpalm-58c46--{channel}-{hash}.web.app`).
  static final RegExp firebaseAdminAppPreviewHostPattern = RegExp(
    r'^masterpalm-58c46--[a-z0-9-]+\.web\.app$',
  );

  /// Preview do site `mastepalm` (catálogo/marketing) — não é admin.
  static final RegExp firebaseMastepalmSitePreviewHostPattern = RegExp(
    r'^mastepalm--[a-z0-9-]+\.web\.app$',
  );

  /// Channel preview do Hosting Firebase do **app admin** (não confundir com domínio de loja).
  static bool isFirebaseAdminAppPreviewHost(String host) {
    final h = normalizeHostForAppUrlCheck(host);
    if (h.isEmpty) return false;
    return firebaseAdminAppPreviewHostPattern.hasMatch(h);
  }

  /// App admin canônico + typo legado + hosting web do catálogo + preview admin Firebase.
  /// Não inclui `mastepalm--*.web.app` (target catálogo/site).
  static bool isDefaultMasterPalmCatalogHost(String host) {
    final h = normalizeHostForAppUrlCheck(host);
    if (h.isEmpty) return false;
    if (appWebHostsAll.contains(h)) return true;
    if (h == catalogFirebaseHostingHost) return true;
    if (isFirebaseAdminAppPreviewHost(host)) return true;
    return false;
  }

  static String normalizeHostForAppUrlCheck(String host) {
    var h = host.trim().toLowerCase();
    if (h.startsWith('www.')) {
      h = h.substring(4);
    }
    return h;
  }
}
