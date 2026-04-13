/// URLs centralizadas do AppWeb MasterPalm.
///
/// **Canônico (produção real do SPA admin):** [appWebHostCanonical] → [appWebBase].
/// **Compatibilidade temporária:** [appWebHostLegacyTypo] (`app.masterpalm.com.br` — grafia
/// com “master” + R extra); mantido em [appWebHostsAll] para App Check / deep links / CORS
/// até migração total de DNS e bookmarks. Ver `docs/DOMAIN_APP_WEB.md`.
///
/// Landing pública: [landingBase] (`mastepalm.com.br` — domínio de marketing, não o app).
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

  /// URL base da landing page (site de divulgação)
  static const String landingBase = 'https://mastepalm.com.br';
}
