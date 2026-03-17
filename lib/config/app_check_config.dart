// lib/config/app_check_config.dart
//
// Configuração centralizada do Firebase App Check.
// Modo monitoramento: não aplica enforcement; apenas habilita verificação.
//
// IMPORTANTE: Aplique "App Check enforcement" no Console apenas quando
// a % de solicitações verificadas estiver alta (ex.: > 95%).

import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, kReleaseMode, defaultTargetPlatform, TargetPlatform;

import '../core/remote_config_keys.dart';
import '../services/remote_config_safe_service.dart';

/// Chave reCAPTCHA v3 para Web (fallback quando Remote Config falha ou não está disponível).
/// Obtenha em: https://www.google.com/recaptcha/admin/create
/// Tipo: reCAPTCHA v3
/// Domínios: seus domínios web (ex: app.mastepalm.com.br, localhost)
///
/// Deixe vazio para usar o Remote Config (recaptcha_site_key).
/// Preencha aqui se quiser override direto no código.
const String kRecaptchaSiteKeyOverride = '';

/// Para uso quando não há chave configurada - substitua pela sua chave e registre no Console.
const String kRecaptchaPlaceholder = 'SUA_CHAVE_RECAPTCHA_AQUI';

/// Indica se a plataforma atual suporta App Check (Web, Android, iOS).
bool get isAppCheckSupportedPlatform {
  if (kIsWeb) return true;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return true;
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
    case TargetPlatform.linux:
      return false;
    default:
      return false;
  }
}

/// Indica se devemos usar provider de DEBUG (token para cadastrar no Console).
/// true = debug ou profile mode em mobile
bool get useDebugProvider {
  // kReleaseMode = false em debug E em profile
  return !kReleaseMode;
}

/// No Web, em modo debug (localhost/dev), pode pular App Check para evitar 400/throttle.
/// Produção (kReleaseMode) nunca pula.
bool get skipAppCheckOnWebInDebug {
  return kIsWeb && kDebugMode;
}

/// Hosts onde App Check Web deve ser ATIVADO (mesma Site Key para todos).
/// Use UMA única Site Key (reCAPTCHA v3) para esses domínios no Firebase/Remote Config.
const List<String> kAppCheckWebAllowedHosts = [
  'mastepalm.web.app',
  'masterpalm-58c46.web.app',
  'app.mastepalm.com.br',
  'localhost',
];

/// Retorna true se [host] está na lista de hosts permitidos para App Check Web.
/// Com flag OFF usa lista hardcoded; com flag ON usa RC com fallback na lista hardcoded.
bool isHostAllowed(String host) {
  final h = host.trim().toLowerCase();
  List<String> allowed = kAppCheckWebAllowedHosts;
  if (RemoteConfigSafeService.isFlagOn(rcEnableDynamicAppcheckHosts, fallback: false)) {
    final fromRc = RemoteConfigSafeService.getStringListFromJson(
      rcAppcheckAllowedHostsJson,
      fallback: List.from(kAppCheckWebAllowedHosts),
    );
    if (fromRc.isNotEmpty) allowed = fromRc;
  }
  final normalized = allowed.map((e) => e.trim().toLowerCase()).toList();
  return normalized.contains(h);
}
