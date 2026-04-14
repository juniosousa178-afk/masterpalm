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
}
