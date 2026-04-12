/// URLs centralizadas do AppWeb MasterPalm.
///
/// **Canônico (produção real do SPA admin):** [appWebHostCanonical] → [appWebBase].
/// **Legado:** [appWebHostLegacyTypo] (grafia “maste…”); mantido em [appWebHostsAll] para
/// App Check / deep links / redirects até migração total. Ver `docs/DOMAIN_APP_WEB.md`.
///
/// Landing pública: [landingBase] (`mastepalm.com.br` — domínio de marketing, não o app).
class AppUrls {
  AppUrls._();

  /// Host canônico do App Web (evidência de uso em produção: `https://app.masterpalm.com.br`).
  static const String appWebHostCanonical = 'app.masterpalm.com.br';

  /// Host legado por typo/grafia antiga; compat até DNS e links antigos migrarem.
  static const String appWebHostLegacyTypo = 'app.mastepalm.com.br';

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
