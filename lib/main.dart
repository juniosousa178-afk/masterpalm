// lib/main.dart
import 'dart:async';

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, defaultTargetPlatform, TargetPlatform;


import 'core/logger.dart';
import 'package:flutter/material.dart';
import 'url_strategy_stub.dart' if (dart.library.html) 'url_strategy_web.dart' as url_strategy;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';

// App Check config
import 'config/app_check_config.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

// Hive + paths
import 'package:hive_flutter/hive_flutter.dart';

// Provider
import 'package:provider/provider.dart';

// Paths util
import 'src/io_compat.dart' show File, getAppDocsDirPath;
import 'utils/theme_notifier.dart';

// Projeto
import 'firebase_options.dart';
import 'themes/app_colors.dart';
import 'app_routes.dart' as app_routes;
import 'utils/last_route_observer.dart';
import 'utils/store_screen_route_observer.dart';
import 'bootstrap/web_popstate_logger.dart';
import 'utils/web_nav_log_observer.dart';
import 'widgets/admin_web_route_shell.dart';

// Telas
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/fornecedor_screen.dart';
import 'screens/vendas_screen.dart';
import 'screens/clientes_screen.dart';
import 'screens/estoque_screen.dart';
import 'screens/historico_clientes_screen.dart';
import 'screens/backup_screen.dart';
import 'screens/relatorios_screen.dart';
import 'screens/precificacao_universal_screen.dart';
import 'screens/relatorio_vendedor_screen.dart';
import 'screens/cadastro_screen.dart';
import 'screens/permissoes_screen.dart';
import 'screens/app_start_router.dart';
import 'screens/plano_screen.dart';
import 'screens/config_pin_screen.dart';
// import 'screens/cadastro_usuario_screen.dart'; // Substituído por vendedores_screen.dart
import 'screens/visualizar_permissoes_screen.dart';
import 'screens/catalago_screen.dart';
import 'screens/cadastro_catalogo_screen.dart';
import 'screens/relatorio_financeiro_screen.dart';
import 'screens/relatorios_financeiros_screen.dart';
import 'screens/public_catalog_screen.dart';
import 'screens/loja_config_screen.dart';
import 'screens/configure_loja_placeholder_screen.dart';
import 'screens/onboarding_loja_screen.dart';
// order_review_screen usado em app_routes.dart
import 'debug/health_check_screen.dart';
import 'screens/diagnostico_app_screen.dart';
import 'screens/pre_pedidos_screen.dart';
import 'screens/planos_screen.dart';
import 'screens/campanhas_sorteio_screen.dart';
import 'screens/globo_sorteio_screen.dart';
// import 'screens/gerenciar_vendedores_screen.dart'; // Substituído por vendedores_screen.dart
import 'screens/vendedores_screen.dart';
import 'screens/fretes_cupons_screen.dart';
// pedido_publico_screen e pagamento_resultado_screen usados em app_routes.dart
import 'screens/admin_sync_screen.dart';
import 'screens/admin_usuarios_screen.dart';
import 'screens/master_login_screen.dart';
import 'screens/master_config_screen.dart';
import 'screens/site_config_screen.dart';
import 'screens/metas_comissoes_screen.dart';
import 'screens/notas_fiscais_screen.dart';
import 'screens/contas_receber_screen.dart';
import 'screens/relatorio_mais_vendidos_screen.dart';
import 'screens/relatorio_ranking_clientes_screen.dart';
import 'screens/relatorio_lucratividade_produto_screen.dart';
import 'screens/carrinhos_abandonados_screen.dart';

// Motor de Crescimento IA
import 'motor_crescimento/screens/motor_crescimento_screen.dart';
import 'motor_crescimento_automacoes/screens/campanhas_sugeridas_screen.dart';

// 🔹 Novas telas do fluxo Auth/Planos
import 'screens/register_screen.dart';
import 'screens/verify_email_screen.dart';
import 'screens/loja_preconfig_screen.dart';
import 'screens/config_pagamentos_screen.dart';
import 'screens/config_pagamentos_simples_screen.dart';
import 'screens/ajuda_screen.dart';

// Widgets
import 'widgets/notificacao_pedido_listener.dart';
import 'widgets/update_check_wrapper.dart';

// Serviços
import 'services/deep_link_handler.dart';
import 'services/fcm_pedido_service.dart';
import 'services/test_checkout.dart';
import 'services/permissoes_service.dart';
import 'services/backup_auto_service_io.dart' if (dart.library.html) 'services/backup_auto_service_web.dart' as backup_auto_service;
import 'services/produto_auto_sync_service.dart';
import 'services/notificacao_service.dart';
import 'services/auto_sync_service.dart';
import 'services/sync_queue_service.dart';
import 'services/soft_delete_service.dart';

// ✅ DEBUG + LOJA
import 'services/loja_id_service.dart';
import 'services/public_store_link_helper.dart';
import 'services/store_resolver_facade.dart';

// ✅ SANIDADE DE SESSÃO
import 'services/session_sanity.dart';
import 'services/remote_config_service.dart';

// Provider services
import 'services/auth_service.dart';

// Hive models
import 'models/cliente.dart';
import 'models/venda.dart';
import 'models/produto.dart';
import 'models/fornecedor.dart';
import 'models/usuario.dart';
import 'models/produto_catalogo.dart';
import 'models/catalogo_config.dart';
import 'models/fechamento_mensal.dart';
import 'models/venda_item.dart';
import 'models/cupom_premio.dart';
import 'models/subcategoria.dart';
import 'models/master_config.dart';
import 'models/meta.dart';
import 'models/comissao_config.dart';
import 'models/venda_tracking.dart';
import 'models/nota_fiscal.dart';
import 'models/conta_receber.dart';
import 'models/estoque_item.dart';
import 'models/categoria.dart';

// 🔍 Debug helpers
import 'debug/bootstrap_diagnostics.dart'; // boot, FirebaseGuard
import 'debug/global_error_hook.dart'; // runWithGlobalErrorHook

// ===========================================================================
// ✅ App Check (proteção contra abuso de API)
// Modo monitoramento: ativa verificação, NÃO aplica enforcement.
// Se falhar, app continua sem proteção (não quebra fluxos existentes).
//
// Providers:
//   - Android debug/profile: Debug provider (token no logcat)
//   - Android release: Play Integrity
//   - iOS debug/profile: Debug provider
//   - iOS release: App Attest
//   - Web: reCAPTCHA v3 (chave em Remote Config ou kRecaptchaSiteKeyOverride)
//   - Desktop (macOS/Windows): não ativa (plataforma não suportada)
// ===========================================================================

bool _appCheckActivatedOnce = false;
bool _appCheckWebOk = false; // true apenas quando ativação Web teve sucesso (ETAPA 20).
DateTime? _appCheckBackoffUntil;

Future<void> initFirebaseAppCheck() async {
  logD('🛡️ [AppCheck] Iniciando ativação...');

  if (!isAppCheckSupportedPlatform) {
    logD(
        'ℹ️ [AppCheck] Plataforma ${defaultTargetPlatform.name} não suporta App Check. Pulando.');
    return;
  }

  if (_appCheckActivatedOnce) {
    logD('ℹ️ [AppCheck] Já ativado nesta sessão (evitando throttle). Pulando nova ativação.');
    _debugPrintAppCheckDiagnostics();
    return;
  }

  if (_appCheckBackoffUntil != null && DateTime.now().isBefore(_appCheckBackoffUntil!)) {
    logD('ℹ️ [AppCheck] Em backoff (400/erro de rede). Aguardando ${_appCheckBackoffUntil!.difference(DateTime.now()).inSeconds}s.');
    return;
  }

  if (skipAppCheckOnWebInDebug) {
    logD('ℹ️ [AppCheck] Web em modo debug: pulando ativação (evita 400/throttle em localhost).');
    _appCheckActivatedOnce = true;
    _debugPrintAppCheckDiagnostics();
    return;
  }

  try {
    if (kDebugMode && !kIsWeb) {
      logD('[LOGIN-APPCHECK] Iniciando App Check para ${defaultTargetPlatform.name}');
    }
    if (kIsWeb) {
      // ETAPA 20: Web soft-fail — uma única tentativa; em erro não bloqueia Auth/login.
      try {
        final host = Uri.base.host.isEmpty ? 'unknown' : Uri.base.host;
        if (!isHostAllowed(host)) {
          logW('[AppCheck] host não permitido; não ativando. Login continua normalmente.', tag: 'APP-CHECK');
          _appCheckActivatedOnce = true;
          _debugPrintAppCheckDiagnostics();
          return;
        }
        logD('[AppCheck] host=$host activate.start');
        final ok = await _activateAppCheckWeb();
        if (!ok) {
          _appCheckBackoffUntil = DateTime.now().add(const Duration(seconds: 60));
          logW('[AppCheck] Ativação Web falhou (400/throttle/storage). App e login Google continuam.', tag: 'APP-CHECK');
          _appCheckActivatedOnce = true;
          _debugPrintAppCheckDiagnostics();
          return;
        }
        _appCheckWebOk = true;
        logD('[AppCheck] activate.ok');
      } catch (e, st) {
        _appCheckWebOk = false;
        _appCheckActivatedOnce = true;
        logW('[AppCheck] Web: falha na ativação (ignorado). Login continua normalmente.', tag: 'APP-CHECK');
        if (kDebugMode) logD('   (type=${e.runtimeType})');
        if (kDebugMode) logD('   $st');
        _debugPrintAppCheckDiagnostics();
        return;
      }
    } else {
      await _activateAppCheckNative();
      if (kDebugMode) logD('[LOGIN-APPCHECK] App Check ativado com sucesso.');
      logD('[AppCheck] ok');
    }

    _appCheckActivatedOnce = true;
    // Web: desabilitar auto-refresh para evitar 400/throttle em exchangeRecaptchaV3Token (evita loop de requests).
    const enableRefresh = !kIsWeb;
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(enableRefresh);
    if (kIsWeb && kDebugMode) logD('[AppCheck] Web: token auto-refresh desligado para evitar 400 em cascata.');

    if (useDebugProvider && !kIsWeb) {
      _appCheckSelfCheck();
    }
    _debugPrintAppCheckDiagnostics();
  } on FirebaseException catch (e) {
    final msg = (e.message ?? '').toLowerCase();
    final is400 = e.code.contains('400') || msg.contains('400') || msg.contains('bad request');
    final isConnectionError = msg.contains('connection_closed') || msg.contains('err_connection') || msg.contains('connection');
    final isAttestationFailed = msg.contains('attestation failed') || msg.contains('app attestation failed');
    if (!kIsWeb && kDebugMode && isAttestationFailed) {
      logD('[AppCheck] Detectado attestation failed (debug). Cadastre o Debug Token em Firebase Console → App Check → Tokens de depuração.');
      _logDebugTokenInstructions();
    }
    if (kIsWeb) {
      _appCheckWebOk = false;
      _appCheckActivatedOnce = true;
      if (is400 || isConnectionError) {
        _appCheckBackoffUntil = DateTime.now().add(const Duration(seconds: 60));
        logW('[AppCheck] 400/erro de rede no Web. App e login continuam.', tag: 'APP-CHECK');
      } else {
        logW('[AppCheck] activate.fail Web: ${e.code}. App continua sem proteção.', tag: 'APP-CHECK');
      }
    } else {
      if (is400 || isConnectionError) {
        _appCheckBackoffUntil = DateTime.now().add(const Duration(seconds: 60));
        logD('[AppCheck] 400 ou erro de rede detectado. Backoff 60s. App continua normalmente.');
      } else {
        logD('[AppCheck] activate.fail: ${e.code} ${e.message ?? ""}. App continua sem proteção.');
      }
      _appCheckActivatedOnce = true;
    }
    if (kIsWeb && kDebugMode) {
      logD('   [AppCheck] Web: recaptcha_site_key (Remote Config) ou kRecaptchaSiteKeyOverride.');
    }
    _debugPrintAppCheckDiagnostics();
  } catch (e, st) {
    if (kIsWeb) {
      _appCheckWebOk = false;
      _appCheckActivatedOnce = true;
      logW('[AppCheck] Web: falha na ativação (ignorado). Login continua normalmente.', tag: 'APP-CHECK');
      if (kDebugMode) logD('   (type=${e.runtimeType})');
      if (kDebugMode) logD('   $st');
    } else {
      final msg = e.toString().toLowerCase();
      final is400OrConnection = msg.contains('400') || msg.contains('connection_closed') || msg.contains('err_connection');
      final isAttestationFailed = msg.contains('attestation failed') || msg.contains('app attestation failed');
      if (is400OrConnection) {
        _appCheckBackoffUntil = DateTime.now().add(const Duration(seconds: 60));
        logD('[AppCheck] 400 ou erro de rede detectado. Backoff 60s. App continua normalmente.');
      } else if (kDebugMode && isAttestationFailed) {
        logD('[AppCheck] Attestation failed. Cadastre o Debug Token em Firebase Console → App Check → Tokens de depuração.');
        _logDebugTokenInstructions();
      } else {
        logD('[AppCheck] activate.fail (type=${e.runtimeType})');
      }
      if (kDebugMode) logD('   $st');
      _appCheckActivatedOnce = true;
    }
    _debugPrintAppCheckDiagnostics();
  }
}

/// Diagnóstico: host, status de ativação (sem vazar segredos).
void _debugPrintAppCheckDiagnostics() {
  if (!kDebugMode) return;
  try {
    final host = kIsWeb ? (Uri.base.host.isEmpty ? 'unknown' : Uri.base.host) : defaultTargetPlatform.name;
    logD('   [AppCheck] Diagnóstico: host=$host | ativadoUmaVez=$_appCheckActivatedOnce');
  } catch (_) {}
}

/// Para telas de diagnóstico: retorna host e confirmação de que activate rodou apenas uma vez.
Map<String, String> getAppCheckDiagnostics() {
  return {
    'host': kIsWeb ? (Uri.base.host.isEmpty ? 'unknown' : Uri.base.host) : defaultTargetPlatform.name,
    'appCheckActivatedOnce': _appCheckActivatedOnce.toString(),
    'appCheckWebOk': _appCheckWebOk.toString(),
  };
}

/// Ativa App Check para Web (reCAPTCHA v3).
/// Retorna true se ativação teve sucesso; false para fallback seguro (app continua).
/// NUNCA rethrow no Web: falhas são logadas e retornam false.
Future<bool> _activateAppCheckWeb() async {
  final host = kIsWeb ? Uri.base.host : 'n/a';

  String recaptchaKey = kRecaptchaSiteKeyOverride.trim();
  if (recaptchaKey.isEmpty) {
    recaptchaKey = RemoteConfigService.recaptchaSiteKey.trim();
  }
  if (recaptchaKey.isEmpty || recaptchaKey == kRecaptchaPlaceholder) {
    logW('[AppCheck] Web: recaptcha_site_key vazia; não ativar. Login continua.', tag: 'APP-CHECK');
    return false;
  }
  final keyPreview = recaptchaKey.length >= 6 ? '${recaptchaKey.substring(0, 6)}...' : '***';
  logD('[AppCheck] Provider: reCAPTCHA v3 (Web) | host=$host | key=$keyPreview');

  try {
    await FirebaseAppCheck.instance.activate(
      webProvider: ReCaptchaV3Provider(recaptchaKey),
    );
    return true;
  } on FirebaseException catch (e) {
    logW('[AppCheck] Web: ${e.code} ${e.message ?? "sem mensagem"}. Login continua.', tag: 'APP-CHECK');
    if (e.code == 'app-check/throttled' || (e.message?.toLowerCase().contains('throttl') ?? false)) {
      logD('[AppCheck] throttle detectado. Não ativar novamente nesta sessão.');
    }
    return false;
  } catch (e) {
    logW('[AppCheck] Web: falha na ativação. Login continua.', tag: 'APP-CHECK');
    return false;
  }
}

/// Ativa App Check para Android e iOS.
Future<void> _activateAppCheckNative() async {
  if (defaultTargetPlatform == TargetPlatform.android) {
    if (useDebugProvider) {
      logD('🛡️ [AppCheck] Provider: DEBUG (Android)');
      _logDebugTokenInstructions();
      await FirebaseAppCheck.instance.activate(
        androidProvider: AndroidProvider.debug,
      );
    } else {
      logD('🛡️ [AppCheck] Provider: Play Integrity (Android Release)');
      await FirebaseAppCheck.instance.activate(
        androidProvider: AndroidProvider.playIntegrity,
      );
    }
  } else if (defaultTargetPlatform == TargetPlatform.iOS) {
    if (useDebugProvider) {
      logD('🛡️ [AppCheck] Provider: DEBUG (iOS)');
      _logDebugTokenInstructions();
      await FirebaseAppCheck.instance.activate(
        appleProvider: AppleProvider.debug,
      );
    } else {
      logD('🛡️ [AppCheck] Provider: App Attest (iOS Release)');
      await FirebaseAppCheck.instance.activate(
        appleProvider: AppleProvider.appAttest,
      );
    }
  }
}

/// Instruções para obter e registrar o Debug Token.
void _logDebugTokenInstructions() {
  logD('   ┌─────────────────────────────────────────────────────────────');
  logD('   │ DEBUG TOKEN – cadastre no Firebase Console:');
  logD('   │ Firebase Console → App Check → Apps → [Android/iOS] → Tokens de depuração');
  logD('   │');
  logD('   │ Como obter o token:');
  if (defaultTargetPlatform == TargetPlatform.android) {
    logD('   │   adb logcat | grep -i DebugAppCheckProvider');
    logD('   │   ou no Android Studio Logcat, filtrar por "debug secret" ou "App Check"');
  } else {
    logD('   │   O token aparece no console do Xcode ao rodar o app.');
  }
  logD('   └─────────────────────────────────────────────────────────────');
}

/// Self-check (apenas debug/profile, mobile): verifica se token está sendo gerado.
void _appCheckSelfCheck() {
  Future<void>.delayed(const Duration(seconds: 2), () async {
    try {
      final token = await FirebaseAppCheck.instance.getToken(false);
      if (token != null && token.isNotEmpty) {
        logD(
            '✅ [AppCheck] Self-check OK: token gerado (${token.length} chars).');
      } else {
        logW('⚠️ [AppCheck] Self-check: token vazio.');
        logD('   Debug/Profile: cadastre o Debug Token no Firebase Console.');
      }
    } catch (e) {
      final err = e.toString().toLowerCase();
      final isKnownDebug = err.contains('403') ||
          err.contains('attestation') ||
          err.contains('app attestation') ||
          err.contains('too many attempts') ||
          err.contains('permission') ||
          err.contains('denied') ||
          e.runtimeType.toString() == 'FirebaseException';
      if (isKnownDebug) {
        logD('⚠️ [AppCheck] Self-check falhou (esperado em debug sem token cadastrado).');
        logD('   → Cadastre o Debug Token em: Firebase Console → App Check → Tokens de depuração');
        logD('   → O token aparece no Logcat (Android) ou Xcode (iOS) ao rodar o app.');
      } else {
        logW('⚠️ [AppCheck] Self-check falhou (type=${e.runtimeType})');
      }
    }
  });
}

// ===========================================================================
// ✅ Crashlytics + Analytics
// Crashlytics não é suportado no Flutter Web (MissingPluginException); só ativa em mobile.
// ===========================================================================
Future<void> initFirebaseMonitoring() async {
  // Se Firebase não estiver inicializado (ex.: modo OFFLINE / timeout), não tentar
  // acessar Crashlytics para evitar core/no-app durante o próprio handler.
  if (Firebase.apps.isEmpty) {
    logD('ℹ️ Crashlytics omitido: Firebase.apps.isEmpty (modo OFFLINE ou init falhou).');
    return;
  }

  if (!kIsWeb) {
    FirebaseCrashlytics? crash;
    try {
      crash = FirebaseCrashlytics.instance;
      await crash.setCrashlyticsCollectionEnabled(true);

      FlutterError.onError = (details) {
        logE('🔴 [FlutterError] ${details.exception}', error: details.exception, st: details.stack);
        if (details.exception.toString().contains('overflowed')) {
          logW('🔴 [OVERFLOW DETECTADO] ${details.exception}');
        }
        FlutterError.presentError(details);
        // Protege contra falhas do próprio Crashlytics (ex.: plugin indisponível)
        final c = crash;
        if (c != null) {
          try {
            c.recordFlutterFatalError(details);
          } catch (e, st) {
            logE('⚠️ Crashlytics.recordFlutterFatalError falhou (ignorado).',
                error: e, st: st);
          }
        }
      };

      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        Object unwrapped = error;
        StackTrace unwrappedStack = stack;
        if (error is AsyncError) {
          unwrapped = error.error;
          unwrappedStack = error.stackTrace;
        }
        logE('💥 [PlatformDispatcher] $unwrapped', error: unwrapped, st: unwrappedStack);
        final c = crash;
        if (c != null) {
          try {
            c.recordError(unwrapped, unwrappedStack, fatal: true);
          } catch (e, st) {
            logE('⚠️ Crashlytics.recordError falhou (ignorado).',
                error: e, st: st);
          }
        }
        return true;
      };

      logD('✅ Crashlytics ativado');
    } catch (e) {
      logW('⚠️ Crashlytics não disponível (type=${e.runtimeType})');
    }
  } else {
    logD('ℹ️ Crashlytics omitido no Web (não suportado).');
    // Web: handlers para logar erro + stack (facilita debug de minified:iD/jI)
    FlutterError.onError = (FlutterErrorDetails details) {
      logE('🔴 [FlutterError/Web] ${details.exception}', error: details.exception, st: details.stack);
      FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      Object unwrapped = error;
      StackTrace unwrappedStack = stack;
      if (error is AsyncError) {
        unwrapped = error.error;
        unwrappedStack = error.stackTrace;
      }
      logE('💥 [PlatformDispatcher/Web] $unwrapped', error: unwrapped, st: unwrappedStack);
      return true;
    };
  }

  try {
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
    logD('✅ Analytics ativado');
  } catch (e) {
    logW('⚠️ Analytics não disponível (type=${e.runtimeType})');
  }
}

// ===========================================================================
// 🔒 Helpers seguros para leitura Hive/JSON (evita TypeError de cast em release/minified)
// ===========================================================================
String? _safeStringFromDynamic(dynamic v) {
  if (v == null) return null;
  if (v is String) return v.trim().isEmpty ? null : v.trim();
  return v.toString().trim();
}

String _safeString(dynamic v, [String fallback = '']) {
  final s = _safeStringFromDynamic(v);
  return s ?? fallback;
}

// ===========================================================================
// 🔧 Corrige domínios antigos (mastepalm.com.br → app.mastepalm.com.br)
// ===========================================================================
Future<void> _fixPedidoLinkBase() async {
  final cfg = Hive.box('config');

  final atual = _safeString(cfg.get('pedido_link_base'));
  final novo = (atual.isEmpty
      ? 'https://app.mastepalm.com.br/pedido'
      : atual.replaceAll('mastepalm.com.br', 'app.mastepalm.com.br'));
  await cfg.put('pedido_link_base', novo);

  final pub = _safeString(cfg.get('public_link_base_url'));
  if (pub.isNotEmpty &&
      pub.contains('mastepalm.com.br') &&
      !pub.contains('app.')) {
    await cfg.put('public_link_base_url',
        pub.replaceAll('mastepalm.com.br', 'app.mastepalm.com.br'));
  }
}

// ===========================================================================
// ✅ Helpers de slug/store_id
// ===========================================================================
String _safeSlug(String s) {
  final x = s.trim().toLowerCase();
  final replaced = x
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'[^a-z0-9_@.\-]'), '');
  return replaced.isEmpty ? 'anon' : replaced;
}

bool _looksLikeStoreId(String v) {
  final s = v.trim();
  if (s.isEmpty) return false;
  return s.startsWith('loja_uid_') || s.startsWith('loja_email_');
}

String _normalizeSlug(String v) => v.trim().toLowerCase();

/// Rota que exige lojaId; quando vazio mostra erro em vez de fallback 'padrao'.
Widget _lojaIdRoute(Widget Function(String lojaId) builder) {
  return FutureBuilder<String?>(
    future: LojaIdService.get(),
    builder: (context, snap) {
      final lojaId = (snap.data ?? '').trim();
      if (lojaId.isEmpty) {
        return Scaffold(
          appBar: AppBar(title: const Text('Relatório')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.store_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'Não foi possível carregar a loja.\nConfigure nas Configurações ou tente novamente.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pushReplacementNamed('/home'),
                    icon: const Icon(Icons.home),
                    label: const Text('Ir para Início'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return builder(lojaId);
    },
  );
}

/// Rota de pedidos (pré-pedidos + pendentes unificados) - resolve lojaId
Widget _pedidosRoute() {
  return FutureBuilder<String?>(
    future: LojaIdService.get(),
    builder: (context, snap) {
      final lojaId = (snap.data ?? '').trim();
      if (lojaId.isEmpty) {
        return Scaffold(
          appBar: AppBar(title: const Text('Pedidos')),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.store_outlined, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  'Nenhuma loja ativa. Configure a loja nas Configurações.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () =>
                      Navigator.of(context).pushReplacementNamed('/home'),
                  child: const Text('Ir para Início'),
                ),
              ],
            ),
          ),
        );
      }
      return PrePedidosScreen(lojaId: lojaId);
    },
  );
}

/// ✅ Resolver slug → store_id com suporte a case-sensitivity e redirects
/// - Se já vier loja_uid_... / loja_email_...: verifica existência e redirect
/// - Se vier "slug bonito", tenta achar a loja no Firestore por campo 'slug'
Future<String> _resolveSlugToStoreIdIfNeeded(String slugOrId) async {
  final raw = slugOrId.trim();
  if (raw.isEmpty) return 'minha-loja';

  // Se Firebase não estiver OK, só devolve como está (fallback)
  if (Firebase.apps.isEmpty) return raw;

  final db = FirebaseFirestore.instance;

  // ✅ Se parece store_id (loja_uid_XXX), verificar existência e redirect
  if (_looksLikeStoreId(raw)) {
    logD(
        '🔍 [RESOLVER] "$raw" parece store_id, verificando existência...');

    try {
      // 1. Verificar se o doc exato existe
      final exactDoc = await db
          .collection('lojas')
          .doc(raw)
          .get()
          .timeout(const Duration(seconds: 3));

      if (exactDoc.exists) {
        final data = exactDoc.data() ?? {};
        final redirectTo = (data['redirectTo'] ?? '').toString().trim();

        if (redirectTo.isNotEmpty && redirectTo != raw) {
          logD('🔀 [RESOLVER] "$raw" → redirect para "$redirectTo"');
          return redirectTo;
        }

        logD('✅ [RESOLVER] "$raw" existe, retornando');
        return raw;
      }

      // 2. Doc não existe - tentar versão lowercase
      final lowercaseId = raw.toLowerCase();
      if (lowercaseId != raw) {
        logD(
            '🔍 [RESOLVER] "$raw" não existe, tentando lowercase "$lowercaseId"...');

        final lowercaseDoc = await db
            .collection('lojas')
            .doc(lowercaseId)
            .get()
            .timeout(const Duration(seconds: 3));

        if (lowercaseDoc.exists) {
          logD('✅ [RESOLVER] Encontrado lowercase "$lowercaseId"');
          return lowercaseId;
        }
      }

      // 3. Nenhuma versão encontrada - retornar o original (vai dar erro no catálogo)
      logW('⚠️ [RESOLVER] "$raw" não encontrado em nenhuma forma');
      return raw;
    } catch (e) {
      logW('⚠️ [RESOLVER] Erro ao verificar store_id (type=${e.runtimeType})');
      return raw;
    }
  }

  // slug bonito (só normaliza se NÃO for store_id)
  final slug = _normalizeSlug(raw);

  try {
    final q = await db
        .collection('lojas')
        .where('slug', isEqualTo: slug)
        .limit(1)
        .get()
        .timeout(const Duration(seconds: 3));

    if (q.docs.isNotEmpty) {
      return q.docs.first.id; // ✅ store_id real (docId)
    }
  } catch (e) {
    logW('⚠️ [RESOLVER] falha ao resolver slug (type=${e.runtimeType})');
  }

  return slug; // fallback
}

// ✅ DIAGNÓSTICO
void mpStoreDiag(String tag) {
  final sessao = Hive.isBoxOpen('sessao') ? Hive.box('sessao') : null;
  final cfg = Hive.isBoxOpen('config') ? Hive.box('config') : null;

  final sidSessao = sessao?.get('store_id');
  final sidCfg = cfg?.get('store_id');

  final slugCfg = cfg?.get('store_slug');
  final lojaSlugCfg = cfg?.get('loja_slug');

  logD('━━━━━━━━━━━━ STORE-DIAG ($tag) ━━━━━━━━━━━━');
  logD('sessao.store_id   = $sidSessao');
  logD('config.store_id   = $sidCfg');
  logD('config.store_slug = $slugCfg');
  logD('config.loja_slug  = $lojaSlugCfg');
  logD(
      'Uri.base          = ${kIsWeb ? Uri.base.toString() : "(not web)"}');
  logD('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

Future<void> _ensureStoreIdOnBootstrap({required bool firebaseOk}) async {
  logD(
    '[STORE_BOOTSTRAP] _ensureStoreIdOnBootstrap firebaseOk=$firebaseOk uri=${kIsWeb ? Uri.base : "(not web)"}',
  );
  final sessao = Hive.box('sessao');
  final cfg = Hive.box('config');

  String? existing = _safeStringFromDynamic(sessao.get('store_id'));
  existing ??= _safeStringFromDynamic(cfg.get('store_id'));

  final String? existingSlug = _safeStringFromDynamic(cfg.get('store_slug'))?.toLowerCase();
  final String? existingLojaSlug = _safeStringFromDynamic(cfg.get('loja_slug'))?.toLowerCase();

  if (existing != null && existing.isNotEmpty) {
    try {
      await LojaIdService.set(existing);
    } catch (_) {}

    await sessao.put('store_id', existing);
    await cfg.put('store_id', existing);

    logD(
      '✅ [WEB_BOOTSTRAP] store_id já existia → $existing (slug preservado: store_slug=$existingSlug | loja_slug=$existingLojaSlug)',
    );
    return;
  }

  // FASE 3: Tentar StoreResolver (Firestore users/usuarios) antes de fallback loja_uid_$uid
  String? lojaId;
  if (firebaseOk) {
    try {
      lojaId = await StoreResolverFacade.resolveForAdminApp()
          .timeout(const Duration(seconds: 5), onTimeout: () => null);
      lojaId = lojaId?.trim();
      if (lojaId != null && lojaId.isNotEmpty) {
        if (kDebugMode) {
          logD('✅ [WEB_BOOTSTRAP] store_id resolvido via StoreResolver → $lojaId');
        }
      } else {
        lojaId = null;
      }
    } catch (_) {
      lojaId = null;
    }
  }

  // Fallback: loja_uid_$uid ou loja_email_ (último recurso; registrar quando usado)
  if (lojaId == null || lojaId.isEmpty) {
    if (firebaseOk) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        final uid = user?.uid;
        if (uid != null && uid.isNotEmpty) {
          lojaId = 'loja_uid_$uid';
          logD('🔄 [WEB_BOOTSTRAP] Fallback loja_uid_$uid (StoreResolver não retornou)');
        }
      } catch (_) {}
    }
    lojaId ??= (() {
      final u = _safeString(sessao.get('usuario_logado'), '');
      if (u.isNotEmpty) {
        final fallback = 'loja_email_${_safeSlug(u)}';
        logD('🔄 [WEB_BOOTSTRAP] Fallback loja_email_ (StoreResolver não retornou)');
        return fallback;
      }
      return null;
    })();
  }

  if (lojaId == null || lojaId.isEmpty) {
    logW('⚠️ [WEB_BOOTSTRAP] Não foi possível definir store_id automaticamente.');
    return;
  }

  try {
    await LojaIdService.set(lojaId);
  } catch (_) {}

  await sessao.put('store_id', lojaId);
  await cfg.put('store_id', lojaId);

  if (kDebugMode) {
    logD('📌 [STORE_SESSION] store_id gravado no bootstrap → $lojaId');
  }
}

// ===========================================================================
// 🔑 navigatorKey e scaffoldMessengerKey globais (SnackBar Desfazer usa o root)
// ===========================================================================
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

// ===========================================================================
// 📱 ScrollBehavior responsivo – toque mais sensível no APK
// ===========================================================================
class _SnappyScrollBehavior extends MaterialScrollBehavior {
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    );
  }
}

// ===========================================================================
// 🌐 Catálogo Web? (path ou fragment/hash)
// Usa URL inicial capturada no main() para não ser afetado por redirects durante o bootstrap.
// ===========================================================================
Uri? _initialWebUri;

bool _isPublicCatalogUrl() {
  if (!kIsWeb) return false;
  final uri = _initialWebUri ?? Uri.base;
  final path = uri.path;

  // Path direto: /loja/slug (garante que abra o catálogo e não o app web)
  if (path.startsWith('/loja/') || path.contains('/loja/')) return true;
  if (uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'loja') return true;

  if (uri.queryParameters.containsKey('loja') ||
      uri.queryParameters.containsKey('slug') ||
      uri.queryParameters.containsKey('store_id')) {
    return true;
  }
  // Hash strategy: #/loja/xxx ou #loja/xxx
  final frag = uri.fragment.trim();
  if (frag.contains('loja/') || frag.startsWith('/loja/')) return true;
  return false;
}

/// Extrai slug da URL a partir do fragment (#/loja/xxx).
String? _lojaSlugFromFragment(String fragment) {
  final s = fragment.trim();
  if (s.isEmpty) return null;
  // #/loja/nathy-pratas-e-folheados ou #loja/nathy-pratas-e-folheados
  final withoutHash = s.startsWith('#') ? s.substring(1) : s;
  final parts = withoutHash.split('/').where((e) => e.isNotEmpty).toList();
  if (parts.length >= 2 && parts[0] == 'loja') {
    final slug = parts[1].trim();
    if (slug.isNotEmpty) return slug;
  }
  if (parts.isNotEmpty && parts[0] == 'loja' && parts.length == 1) return null;
  return null;
}

/// Lê o identificador bruto vindo da URL (path, query ou fragment). Nunca retorna 'minha-loja' se a URL tiver loja.
String _lojaSlugOrIdFromUrl() {
  if (!kIsWeb) return 'minha-loja';
  final uri = _initialWebUri ?? Uri.base;

  // 1) Path: /loja/{slugOuId} (prioridade para garantir catálogo web)
  final path = uri.path;
  if (path.startsWith('/loja/')) {
    final after = path.substring('/loja/'.length).trim();
    final slug = after.split('/').first.trim();
    if (slug.isNotEmpty) return slug;
  }
  if (uri.pathSegments.length >= 2 && uri.pathSegments.first == 'loja') {
    final raw = uri.pathSegments[1].trim();
    if (raw.isNotEmpty) return raw;
  }

  // 2) Query: ?loja= / ?slug= / ?store_id=
  final rawQuery = (uri.queryParameters['loja'] ??
          uri.queryParameters['slug'] ??
          uri.queryParameters['store_id'] ??
          '')
      .trim();
  if (rawQuery.isNotEmpty) return rawQuery;

  // 3) Fragment (hash): #/loja/xxx
  final fromFrag = _lojaSlugFromFragment(uri.fragment);
  if (fromFrag != null && fromFrag.isNotEmpty) return fromFrag;

  return 'minha-loja';
}

/// ✅ Lê o ID do vendedor para tracking de comissão
/// URL: /loja/{id}?ref={vendedorId} ou ?vendedor={id}
String? _vendedorRefFromUrl() {
  if (!kIsWeb) return null;
  final uri = _initialWebUri ?? Uri.base;

  // ?ref= ou ?vendedor= ou ?seller=
  final ref = (uri.queryParameters['ref'] ??
          uri.queryParameters['vendedor'] ??
          uri.queryParameters['seller'] ??
          '')
      .trim();

  if (ref.isNotEmpty) {
    logD('📍 [URL] Vendedor ref detectado: $ref');
    return ref;
  }

  return null;
}

/// ✅ Lê o ID do cliente que indicou (programa indicar amigo)
/// URL: /loja/{id}?indicacao={clienteId}
String? _indicacaoRefFromUrl() {
  if (!kIsWeb) return null;
  final uri = _initialWebUri ?? Uri.base;
  final v = (uri.queryParameters['indicacao'] ?? '').trim();
  if (v.isNotEmpty) {
    logD('📍 [URL] Indicação detectada: $v');
    return v;
  }
  return null;
}

/// ✅ Lê ID/slug de produto para deep link no catálogo público
/// URL: /loja/{id}?produto={produtoIdOuSlug}
String? _produtoRefFromUrl() {
  if (!kIsWeb) return null;
  final uri = _initialWebUri ?? Uri.base;
  final v = (uri.queryParameters['produto'] ?? '').trim();
  if (v.isNotEmpty) {
    logD('📍 [URL] Produto deep link detectado: $v');
    return v;
  }
  return null;
}

// ===========================================================================
// 🧭 Raiz do Catálogo Web
// ===========================================================================
class CatalogWebRoot extends StatelessWidget {
  final String lojaId;
  final String? vendedorRef; // ✅ Tracking de vendedor para comissão
  final String? indicacaoRef; // ✅ ID do cliente que indicou (link ?indicacao=)
  final String? produtoRef; // ✅ Produto para abrir direto no detalhe
  const CatalogWebRoot({
    super.key,
    required this.lojaId,
    this.vendedorRef,
    this.indicacaoRef,
    this.produtoRef,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      scrollBehavior: _SnappyScrollBehavior(),
      title: 'Catálogo MasterPalm',
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('pt', 'BR'), Locale('en', 'US')],
      theme: ThemeData(
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        // Fundo visível no catálogo web (evita tela branca antes do primeiro frame)
        scaffoldBackgroundColor: const Color(0xFFE8E8E8),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        colorScheme: const ColorScheme.light(
          primary: AppColors.primary,
          secondary: AppColors.accent,
          surface: AppColors.background,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: AppColors.textPrimary,
        ),
        inputDecorationTheme:
            const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      home: PublicCatalogScreen(
        lojaId: lojaId,
        vendedorRef: vendedorRef,
        indicacaoClienteRef: indicacaoRef,
        initialProdutoId: produtoRef,
      ),
    );
  }
}

// ===========================================================================
// ✅ Página de resultado OAuth Mercado Pago (redirect após autorizar)
// ===========================================================================
class MpOAuthResultPage extends StatelessWidget {
  final bool success;
  final String? lojaId;
  final String? errorMsg;

  const MpOAuthResultPage({
    super.key,
    required this.success,
    this.lojaId,
    this.errorMsg,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    success ? Icons.check_circle : Icons.error,
                    size: 72,
                    color: success ? Colors.green : Colors.red,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    success ? 'Mercado Pago conectado!' : 'Falha na conexão',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    success
                        ? 'Você pode fechar esta janela e voltar ao app.'
                        : (errorMsg ?? 'Tente novamente mais tarde.'),
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// ⏳ Boot UI
// ===========================================================================
class _BootApp extends StatelessWidget {
  const _BootApp();
  @override
  Widget build(BuildContext context) {
    final isCatalog =
        kIsWeb && (Uri.base.pathSegments.isNotEmpty && Uri.base.pathSegments.first == 'loja');
    final splash = Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 16),
            Text(
              isCatalog
                  ? 'Carregando catálogo...'
                  : 'Iniciando o sistema MasterPalm...',
            ),
          ],
        ),
      ),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      // Web path URL: o framework usa a URL como rota inicial; onGenerateInitialRoutes
      // garante que /login, /router ou qualquer path mostre o splash (evita "Could not navigate to initial route")
      onGenerateInitialRoutes: (String initialRoute) {
        return [
          MaterialPageRoute<void>(
            builder: (_) => splash,
            settings: RouteSettings(name: initialRoute),
          ),
        ];
      },
      routes: {
        '/': (_) => splash,
        '/login': (_) => splash,
        '/router': (_) => splash,
      },
    );
  }
}

// ===========================================================================
// ❌ Boot Error
// ===========================================================================
class _BootError extends StatelessWidget {
  final String message;
  const _BootError({required this.message});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('❌ Ocorreu um erro ao iniciar:\n$message'),
            ),
          ),
        ),
      );
}

// ===========================================================================
// 🔥 Inicialização do Firebase com fallback OFFLINE
// ===========================================================================
Future<bool> _initFirebaseCore() async {
  logD('➡️ Firebase.initializeApp...');
  boot.mark('firebase.init.begin');
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 15));

    // Web: manter usuário logado até clicar em Sair, fechar aba/navegador ou limpar dados
    if (kIsWeb) {
      try {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
        logD('🔐 [BOOT] Auth persistência LOCAL (permanece logado até Sair)');
      } catch (e) {
        logD('⚠️ [BOOT] setPersistence: $e');
      }
    }

    boot.mark('firebase.init.ok');
    logD('✅ Firebase inicializado');
    return true;
  } on TimeoutException catch (e) {
    logD('! Firebase.initializeApp demorou demais (type=${e.runtimeType})');
    boot.mark('firebase.init.timeout', e);
    logD(
        '! Não foi possível inicializar o Firebase. Continuando em modo OFFLINE.');
    boot.mark('firebase.init.offline', e);
    return false;
  } on FirebaseException catch (e) {
    if (e.code == 'duplicate-app') {
      logD(
          'ℹ️ Firebase já estava inicializado (duplicate-app). Usando instância existente.');
      Firebase.app();
      boot.mark('firebase.init.duplicate');
      return true;
    } else {
      boot.mark('firebase.init.fail', e);
      rethrow;
    }
  }
}

// ===========================================================================
// ▶️ MAIN
// ===========================================================================
Future<void> main() async {
  await runWithGlobalErrorHook(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Web: usar path na URL (/loja/slug) em vez de hash (#/loja/slug) para o lojaId ser lido corretamente
    if (kIsWeb) {
      url_strategy.usePathUrlStrategy();
      // Captura URL inicial para decisão catálogo vs app (evita redirect durante bootstrap)
      _initialWebUri = Uri.base;
      logD('🌐 [MAIN] URL inicial (para catálogo): ${_initialWebUri?.path}');
      // Não inicializar Google Sign-In aqui: evita redirecionar para Google antes
      // de exibir a tela de login. O init é feito na LoginScreen quando o usuário vê as opções.
    }

    logD('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    logD('🚀 [MAIN] Iniciando MasterPalm');
    logD('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    runApp(const _BootApp());

    try {
      logD('🟦 [MAIN] Chamando _bootstrapSafe()...');
      await _bootstrapSafe();
      logD('🟩 [MAIN] _bootstrapSafe() concluído com sucesso');

      try {
        final lojaViaLojaService = await LojaIdService.get();
        logD(
            '🟪 [MAIN] Loja via LojaIdService.get() → $lojaViaLojaService');
      } catch (e) {
        logD('🟥 [MAIN] Erro ao obter loja via LojaIdService.get() (type=${e.runtimeType})');
      }

      if (kIsWeb) {
        final uri = Uri.base;
        final mpOAuth = uri.queryParameters['mp_oauth'];
        if (mpOAuth == 'ok' || mpOAuth == 'error') {
          logD('🌐 [MAIN] Redirect OAuth MP detectado: $mpOAuth');
          runApp(MpOAuthResultPage(
            success: mpOAuth == 'ok',
            lojaId: uri.queryParameters['loja'],
            errorMsg: uri.queryParameters['msg'],
          ));
          return;
        }

        logD(
            '🌐 [MAIN] Rodando em Web. Verificando URL para catálogo público...');
        // Em produção a path pode estar disponível só após load; usar Uri.base como fallback
        if (Uri.base.path.contains('/loja')) {
          _initialWebUri = Uri.base;
          logD('🌐 [MAIN] URL para catálogo (atual): ${_initialWebUri?.path}');
        }
        final isCat = _isPublicCatalogUrl();
        logD('🌐 [MAIN] _isPublicCatalogUrl() → $isCat');

        if (isCat) {
          final slugOuId = _lojaSlugOrIdFromUrl();
          String lojaIdResolvido = slugOuId;
          try {
            lojaIdResolvido = await _resolveSlugToStoreIdIfNeeded(slugOuId);
          } catch (e) {
            logW('⚠️ [MAIN] Resolver slug falhou, usando slug da URL (type=${e.runtimeType})');
          }
          final vendedorRef = _vendedorRefFromUrl();
          final indicacaoRef = _indicacaoRefFromUrl();
          final produtoRef = _produtoRefFromUrl();

          logD('🌐 [MAIN] Public Catalog slug/id resolvido');
          runApp(CatalogWebRoot(
            lojaId: lojaIdResolvido,
            vendedorRef: vendedorRef,
            indicacaoRef: indicacaoRef,
            produtoRef: produtoRef,
          ));
        } else {
          logD('🌐 [MAIN] Web padrão → iniciando MyApp()');
          runApp(const MyApp());
          registerWebPopStateLogger();
        }
      } else {
        logD('📱 [MAIN] Rodando em Mobile/Desktop → iniciando MyApp()');
        runApp(const MyApp());
      }
    } catch (e, st) {
      logE('❌ Bootstrap ERROR (type=${e.runtimeType})', error: e, st: st);
      runApp(_BootError(message: e.toString()));
    }
  });
}

// ===========================================================================
// 🧰 RESET HIVE SCHEMA (evita crash por typeIds antigos no IndexedDB)
// ===========================================================================
Future<void> resetHiveIfSchemaChanged() async {
  try {
    final config = await Hive.openBox('config');
    const schemaVersion = 2;
    final saved = config.get('schema_version') as int?;
    if (saved == schemaVersion) return;

    for (final name in ['estoque', 'catalogo', 'config_catalogo', 'categorias']) {
      try {
        if (Hive.isBoxOpen(name)) await Hive.box(name).close();
        await Hive.deleteBoxFromDisk(name);
        logD('🧹 [BOOT] Box $name deletada (schema v$schemaVersion)');
      } catch (_) {}
    }
    await config.put('schema_version', schemaVersion);
    logD('🟢 [BOOT] Schema Hive atualizado para v$schemaVersion');
  } catch (e) {
    logW('⚠️ [BOOT] resetHiveIfSchemaChanged (type=${e.runtimeType})');
  }
}

// ===========================================================================
// 🧰 BOOTSTRAP
// ===========================================================================
Future<void> _bootstrapSafe() async {
  logD('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  logD('[BOOT-ROUTER] Iniciando _bootstrapSafe()');
  logD('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  boot.mark('intl.start');
  Intl.defaultLocale = 'pt_BR';
  await initializeDateFormatting('pt_BR');
  boot.mark('intl.ok');
  logD('🟢 [BOOT] Intl / Locale configurados (pt_BR)');

  final firebaseOk = await _initFirebaseCore();
  logD('[BOOT-AUTH] firebaseOk=$firebaseOk');

  if (firebaseOk && kIsWeb && kDebugMode) {
    logD('ℹ️ [WEB] OAuth: adicione app.mastepalm.com.br em Firebase Console → Authentication → Settings → Authorized domains (ver docs/SETUP_FIREBASE_WEB.md)');
  }

  // ⚡ FAST PATH (web + mobile): sem usuário → bootstrap mínimo para login
  // Web: aguardar auth restaurar (currentUser pode ser null temporariamente)
  bool hasUser = false;
  if (firebaseOk) {
    var u = FirebaseAuth.instance.currentUser;
    if (u == null && kIsWeb) {
      logD('🟡 [BOOT] Web: currentUser null, aguardando auth (até 3s)...');
      try {
        await FirebaseAuth.instance.authStateChanges()
            .where((x) => x != null && !x.isAnonymous)
            .first
            .timeout(const Duration(seconds: 3), onTimeout: () => null);
        u = FirebaseAuth.instance.currentUser;
      } catch (_) {}
    }
    hasUser = u != null && !u.isAnonymous;
    logD('[BOOT-AUTH] currentUser → hasUser=$hasUser');
  }
  final isNoUser = !hasUser;
  if (isNoUser) {
    logD('[BOOT-OFFLINE] Fast path: sem usuário → bootstrap mínimo para login');
    boot.mark('auth.no_user');
    boot.mark('appcheck.skip_fastpath');
    boot.mark('remoteconfig.defer');
    FirebaseGuard.markReady();
    boot.mark('hive.init.begin');
    if (kIsWeb) {
      await Hive.initFlutter();
    } else {
      final dirPath = await getAppDocsDirPath();
      await Hive.initFlutter(dirPath);
    }
    boot.mark('hive.init.ok');
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ClienteAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(FornecedorAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(UsuarioAdapter());
    if (!Hive.isAdapterRegistered(5)) Hive.registerAdapter(ProdutoCatalogoAdapter());
    if (!Hive.isAdapterRegistered(6)) Hive.registerAdapter(CatalogoConfigAdapter());
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(VendaItemAdapter());
    if (!Hive.isAdapterRegistered(8)) Hive.registerAdapter(FechamentoMensalAdapter());
    if (!Hive.isAdapterRegistered(13)) Hive.registerAdapter(SubcategoriaAdapter());
    if (!Hive.isAdapterRegistered(14)) Hive.registerAdapter(CupomPremioAdapter());
    if (!Hive.isAdapterRegistered(15)) Hive.registerAdapter(MasterConfigAdapter());
    if (!Hive.isAdapterRegistered(16)) Hive.registerAdapter(MetaAdapter());
    if (!Hive.isAdapterRegistered(17)) Hive.registerAdapter(CategoriaAdapter());
    if (!Hive.isAdapterRegistered(18)) Hive.registerAdapter(EstoqueItemAdapter());
    if (!Hive.isAdapterRegistered(25)) Hive.registerAdapter(ComissaoConfigAdapter());
    if (!Hive.isAdapterRegistered(26)) Hive.registerAdapter(ComissaoVendedorAdapter());
    if (!Hive.isAdapterRegistered(27)) Hive.registerAdapter(VendaTrackingAdapter());
    if (!Hive.isAdapterRegistered(28)) Hive.registerAdapter(ComissaoVendaAdapter());
    if (!Hive.isAdapterRegistered(10)) Hive.registerAdapter(NotaFiscalAdapter());
    if (!Hive.isAdapterRegistered(11)) Hive.registerAdapter(NotaFiscalItemAdapter());
    if (!Hive.isAdapterRegistered(29)) Hive.registerAdapter(ContaReceberAdapter());
    boot.mark('hive.adapters.ok');
    await Hive.openBox('sessao');
    await Hive.openBox('config');
    boot.mark('hive.boxes.ok');
    await SessionSanity.fixIfNoFirebaseUser();
    initDarkModeFromHive();
    boot.mark('local.fix.ok');
    boot.mark('backup.auto.ok');
    boot.mark('autosync.ok');
    unawaited(_bootstrapDeferredFull(firebaseOk: firebaseOk));
    logD('✅ [BOOT] Bootstrap fast path concluído – mostrando login');
    logD(boot.dump());
    return;
  }

  // Fluxo completo (mobile ou web com usuário já logado)
  if (firebaseOk) {
    logD('➡️ RemoteConfig...');
    try {
      await RemoteConfigService.init()
          .timeout(const Duration(seconds: 8), onTimeout: () {
        logD('[BOOT-OFFLINE] RemoteConfig timeout – usando defaults');
      });
    } catch (e) {
      logW('[BOOT-OFFLINE] RemoteConfig falhou (type=${e.runtimeType}) – usando defaults');
    }
    boot.mark('remoteconfig.ok');
    logD('➡️ FirebaseAppCheck...');
    try {
      await initFirebaseAppCheck()
          .timeout(const Duration(seconds: 5), onTimeout: () {
        logD('[BOOT-OFFLINE] AppCheck timeout – continuando sem proteção');
      });
    } catch (e, st) {
      logW('[AppCheck] (ignorado) Falha não bloqueia render do catálogo. Login Google continua.', tag: 'APP-CHECK');
      if (kDebugMode) logD('   (type=${e.runtimeType})');
      if (kDebugMode) logD('   $st');
    }
    boot.mark('appcheck.ok');
    logD('➡️ Crashlytics + Analytics...');
    try {
      await initFirebaseMonitoring()
          .timeout(const Duration(seconds: 3), onTimeout: () {
        logD('[BOOT-OFFLINE] Monitoring timeout – ignorado');
      });
    } catch (_) {}
    boot.mark('monitoring.ok');
  } else {
    boot.mark('appcheck.skip_offline');
    logD('ℹ️ Pulando App Check (Firebase OFFLINE).');
  }

  boot.mark('auth.begin');
  if (firebaseOk) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || currentUser.isAnonymous) {
      logD('ℹ️ Nenhum usuário logado. Fluxo seguirá para tela de login.');
      boot.mark('auth.no_user');
      logD('🟡 [BOOT] Nenhum usuário autenticado no Firebase');
    } else {
      logD('✅ Usuário previamente logado: ${currentUser.email}');
      boot.mark('auth.pre_logged');
      logD('🟢 [BOOT] Usuário já logado: ${currentUser.email}');
    }
  } else {
    logD('ℹ️ Firebase OFFLINE – pulando verificação de usuário logado.');
    boot.mark('auth.offline_skip');
    logD('🟠 [BOOT] Firebase OFFLINE – verificação de auth pulada');
  }
  boot.mark('auth.end');

  if (firebaseOk && !kIsWeb) {
    try {
      FcmPedidoService.setNavigatorKey(navigatorKey);
      await FcmPedidoService.init();
    } catch (e) {
      logW('⚠️ [BOOT] FCM pedido (type=${e.runtimeType})');
    }
  }

  FirebaseGuard.markReady();

  boot.mark('hive.init.begin');
  if (!kIsWeb) {
    final dirPath = await getAppDocsDirPath();
    await Hive.initFlutter(dirPath);
    logD('🟦 [BOOT] Hive.initFlutter() em: $dirPath');
  } else {
    await Hive.initFlutter();
    logD('🟦 [BOOT] Hive.initFlutter() (Web)');
  }
  boot.mark('hive.init.ok');

  if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ClienteAdapter());
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
  if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
  if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(FornecedorAdapter());
  if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(UsuarioAdapter());
  if (!Hive.isAdapterRegistered(5)) {
    Hive.registerAdapter(ProdutoCatalogoAdapter());
  }
  if (!Hive.isAdapterRegistered(6)) {
    Hive.registerAdapter(CatalogoConfigAdapter());
  }
  if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(VendaItemAdapter());
  if (!Hive.isAdapterRegistered(8)) {
    Hive.registerAdapter(FechamentoMensalAdapter());
  }
  if (!Hive.isAdapterRegistered(13)) {
    Hive.registerAdapter(SubcategoriaAdapter());
  }
  if (!Hive.isAdapterRegistered(14)) Hive.registerAdapter(CupomPremioAdapter());
  if (!Hive.isAdapterRegistered(15)) {
    Hive.registerAdapter(MasterConfigAdapter());
  }
  if (!Hive.isAdapterRegistered(16)) Hive.registerAdapter(MetaAdapter());
  if (!Hive.isAdapterRegistered(17)) Hive.registerAdapter(CategoriaAdapter());
  if (!Hive.isAdapterRegistered(18)) Hive.registerAdapter(EstoqueItemAdapter());
  // ✅ NOVO: Adapters do sistema de comissões
  if (!Hive.isAdapterRegistered(25)) {
    Hive.registerAdapter(ComissaoConfigAdapter());
  }
  if (!Hive.isAdapterRegistered(26)) {
    Hive.registerAdapter(ComissaoVendedorAdapter());
  }
  if (!Hive.isAdapterRegistered(27)) {
    Hive.registerAdapter(VendaTrackingAdapter());
  }
  if (!Hive.isAdapterRegistered(28)) {
    Hive.registerAdapter(ComissaoVendaAdapter());
  }
  if (!Hive.isAdapterRegistered(10)) Hive.registerAdapter(NotaFiscalAdapter());
  if (!Hive.isAdapterRegistered(11)) {
    Hive.registerAdapter(NotaFiscalItemAdapter());
  }
  if (!Hive.isAdapterRegistered(29)) Hive.registerAdapter(ContaReceberAdapter());
  boot.mark('hive.adapters.ok');
  logD('🟢 [BOOT] Adapters Hive registrados');

  // ✅ Reset controlado de boxes com schema antigo (evita crash por typeId inválido)
  await resetHiveIfSchemaChanged();

  // ✅ Inicializar serviço de notificações (web: plugin não suportado, pula)
  if (!kIsWeb) {
    try {
      await NotificacaoService.init();
      logD('🔔 [BOOT] NotificacaoService inicializado');
    } catch (e) {
      logW('⚠️ [BOOT] Erro ao inicializar NotificacaoService (type=${e.runtimeType})');
    }
  } else {
    logD('🔔 [BOOT] NotificacaoService omitido (web)');
  }

  // ✅ Fila de sincronização offline-first (Hive ↔ Firestore)
  try {
    await SyncQueueService.init();
    SyncQueueService.setOnReconnect(AutoSyncService.syncEmBackground);
    SyncQueueService.startConnectivityListener();
    // Processa pendentes ao iniciar (ex.: app fechou offline e reabriu)
    unawaited(SyncQueueService.processPending().then((r) {
      if (r.processed > 0) {
        logD('📋 [BOOT] SyncQueue: ${r.processed} itens processados');
      }
    }));
    logD('📋 [BOOT] SyncQueueService inicializado');
  } catch (e) {
    logW('⚠️ [BOOT] Erro ao inicializar SyncQueueService (type=${e.runtimeType})');
  }

  Future<void> openTyped<T>(String name) async {
    if (Hive.isBoxOpen(name)) return;
    try {
      await Hive.openBox<T>(name);
      logD('📦 [BOOT] Box tipada aberta: $name (T=$T)');
    } catch (e) {
      logD('🟥 [BOOT] Erro ao abrir box tipada $name (type=${e.runtimeType})');
      if (kIsWeb) {
        // Web: fallback para box dinâmica (evita TypeError em release quando dados não batem com o tipo)
        try {
          await Hive.openBox(name);
          logW(
            '[WEB_BOX_FALLBACK] [HIVE_BOX] box=$name plataforma=Web motivo=tipagem_falhou_abertura_dinamica contexto=bootstrap',
            tag: 'WEB_BOX_FALLBACK',
          );
        } catch (e2) {
          logD('🟥 [BOOT] Falha ao abrir box $name (web) (type=${e2.runtimeType})');
        }
      } else {
        try {
          final dirPath = await getAppDocsDirPath();
          final file = File('$dirPath/$name.hive');
          if (await file.exists()) {
            logD('🧹 [BOOT] Deletando arquivo corrompido: $name.hive');
            await file.delete();
          }
          await Hive.openBox<T>(name);
          logD(
              '📦 [BOOT] Box tipada reaberta após limpar arquivo: $name');
        } catch (e2) {
          logD('🟥 [BOOT] Falha ao recuperar box $name (type=${e2.runtimeType})');
        }
      }
    }
  }

  Future<void> openDynamic(String name) async {
    if (Hive.isBoxOpen(name)) return;
    try {
      await Hive.openBox(name);
      logD('📦 [BOOT] Box dinâmica aberta: $name');
    } catch (e) {
      logD('🟥 [BOOT] Erro ao abrir box dinâmica $name (type=${e.runtimeType})');
      if (!kIsWeb) {
        try {
          final dirPath = await getAppDocsDirPath();
          final file = File('$dirPath/$name.hive');
          if (await file.exists()) {
            logD('🧹 [BOOT] Deletando arquivo corrompido: $name.hive');
            await file.delete();
          }
          await Hive.openBox(name);
          logD(
              '📦 [BOOT] Box dinâmica reaberta após limpar arquivo: $name');
        } catch (e2) {
          logD('🟥 [BOOT] Falha ao recuperar box $name (type=${e2.runtimeType})');
        }
      }
    }
  }

  await openDynamic('sessao');
  await openDynamic('config');
  await openDynamic('licenca');
  await openDynamic('temp_orders');
  await openDynamic('notificacoes_centro');

  // ⚠️ [LEGADO] As boxes tipadas abaixo usam nomes genéricos (sem lojaId).
  // Elas são mantidas apenas para compat/migração; o fluxo multi-tenant atual
  // deve usar sempre HiveBoxNames.*(lojaId) para leitura/gravação.
  await openTyped<Cliente>('clientes');
  logW('[LEGADO_BOX] Box genérica aberta no bootstrap: clientes | uso apenas compat/migração', tag: 'LEGADO_BOX');
  await openTyped<Venda>('vendas');
  logW('[LEGADO_BOX] Box genérica aberta no bootstrap: vendas | uso apenas compat/migração', tag: 'LEGADO_BOX');
  await openTyped<Produto>('produtos');
  logW('[LEGADO_BOX] Box genérica aberta no bootstrap: produtos | uso apenas compat/migração', tag: 'LEGADO_BOX');
  await openTyped<EstoqueItem>('estoque');
  logW('[LEGADO_BOX] Box genérica aberta no bootstrap: estoque | uso apenas compat/migração', tag: 'LEGADO_BOX');
  await openTyped<Fornecedor>('fornecedores');
  await openTyped<ProdutoCatalogo>('catalogo');
  await openTyped<CatalogoConfig>('config_catalogo');
  await openTyped<Usuario>('usuarios');
  await openTyped<FechamentoMensal>('fechamentos_mensais');
  boot.mark('hive.boxes.ok');

  await SessionSanity.fixIfNoFirebaseUser();

  // Web com usuário: aguardar Auth restaurar sessão antes de resolver store_id
  if (firebaseOk && kIsWeb && FirebaseAuth.instance.currentUser == null) {
    logD('🟡 [WEB_BOOT] Aguardando Auth restaurar sessão (até 2s)...');
    try {
      await FirebaseAuth.instance.authStateChanges()
          .where((u) => u != null)
          .first
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
      logD('🟢 [WEB_BOOT] Auth restaurado');
    } catch (_) {}
  }

  await _ensureStoreIdOnBootstrap(firebaseOk: firebaseOk);
  mpStoreDiag('BOOT.afterEnsureStoreId');

  final sessao = Hive.box('sessao');
  final config = Hive.box('config');

  logD('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  logD('🔎 [BOOT] ESTADO DAS BOXES HIVE (sessao/config)');
  logD('   sessao.keys → ${sessao.keys.toList()}');
  logD('   config.keys → ${config.keys.toList()}');
  logD('   sessao["store_id"]      → ${sessao.get("store_id")}');
  logD('   sessao["usuario_logado"]→ ${sessao.get("usuario_logado")}');
  logD('   config["store_id"]      → ${config.get("store_id")}');
  logD('   config["store_slug"]    → ${config.get("store_slug")}');
  logD('   config["loja_slug"]     → ${config.get("loja_slug")}');
  logD('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  initDarkModeFromHive();

  String? lojaSoft;
  try {
    lojaSoft = await LojaIdService.get();
    logD('🟪 [BOOT] LojaIdService.get() durante bootstrap → $lojaSoft');
  } catch (e) {
    logD(
        '🟥 [BOOT] Erro ao chamar LojaIdService.get() durante bootstrap (type=${e.runtimeType})');
  }

  await _fixPedidoLinkBase();

  if (Firebase.apps.isNotEmpty) {
    await refreshPermissoesLocais();
  } else {
    logD('ℹ️ Firebase OFFLINE – pulando refreshPermissoesLocais.');
  }
  boot.mark('local.fix.ok');

  await backup_auto_service.BackupAutoService.iniciarAgendamento();
  boot.mark('backup.auto.ok');

  // Inicia auto-sincronização de produtos
  try {
    final autoSync = ProdutoAutoSyncService();
    await autoSync.start();
    boot.mark('autosync.ok');
    logD('✅ [BOOT] Auto-sincronização de produtos iniciada');
  } catch (e) {
    logW('⚠️ [BOOT] Erro ao iniciar auto-sync (type=${e.runtimeType})');
    boot.mark('autosync.fail', e);
  }

  logD('✅ Bootstrap concluído com sucesso (lojaSoft=$lojaSoft)');
  logD(boot.dump());

  // Processar exclusões pendentes (30 s) que expiraram com app fechado
  try {
    await SoftDeleteService.processOnStartup();
    logD('🟢 [BOOT] SoftDeleteService.processOnStartup() OK');
  } catch (e) {
    logW('⚠️ [BOOT] SoftDeleteService.processOnStartup() falhou (type=${e.runtimeType})');
  }

  logD('🟢 [BOOT] _bootstrapSafe() finalizado com sucesso');
}

/// Executa etapas do bootstrap em background (usado no fast path web sem usuário).
Future<void> _bootstrapDeferred({required bool firebaseOk}) async {
  try {
    await _ensureStoreIdOnBootstrap(firebaseOk: firebaseOk);
    await _fixPedidoLinkBase();
    if (Firebase.apps.isNotEmpty) {
      await refreshPermissoesLocais();
    }
    await backup_auto_service.BackupAutoService.iniciarAgendamento();
    try {
      final autoSync = ProdutoAutoSyncService();
      await autoSync.start();
      logD('✅ [BOOT] Auto-sincronização de produtos iniciada (deferred)');
    } catch (e) {
      logW('⚠️ [BOOT] Erro ao iniciar auto-sync deferred (type=${e.runtimeType})');
    }
    await SoftDeleteService.processOnStartup();
    logD('🟢 [BOOT] _bootstrapDeferred() concluído');
  } catch (e, st) {
    logW('⚠️ [BOOT] _bootstrapDeferred falhou (type=${e.runtimeType})');
    if (kDebugMode) logD('   $st');
  }
}

/// Bootstrap completo em background (fast path web + mobile): RemoteConfig, App Check, boxes Hive, SyncQueue, etc.
Future<void> _bootstrapDeferredFull({required bool firebaseOk}) async {
  try {
    if (firebaseOk) {
      await RemoteConfigService.init();
      try {
        await initFirebaseAppCheck();
      } catch (_) {}
      await initFirebaseMonitoring();
      if (!kIsWeb) {
        try {
          FcmPedidoService.setNavigatorKey(navigatorKey);
          await FcmPedidoService.init();
        } catch (_) {}
        try {
          await NotificacaoService.init();
        } catch (_) {}
      }
    }
    await resetHiveIfSchemaChanged();
    try {
      await SyncQueueService.init();
      SyncQueueService.setOnReconnect(AutoSyncService.syncEmBackground);
      SyncQueueService.startConnectivityListener();
      unawaited(SyncQueueService.processPending());
    } catch (_) {}
    await _openRemainingHiveBoxes();
    await _bootstrapDeferred(firebaseOk: firebaseOk);
    logD('🟢 [BOOT] _bootstrapDeferredFull() concluído');
  } catch (e, st) {
    logW('⚠️ [BOOT] _bootstrapDeferredFull falhou (type=${e.runtimeType})');
    if (kDebugMode) logD('   $st');
  }
}

Future<void> _openRemainingHiveBoxes() async {
  Future<void> openDynamic(String name) async {
    if (Hive.isBoxOpen(name)) return;
    try {
      await Hive.openBox(name);
    } catch (_) {}
  }

  Future<void> openTyped<T>(String name) async {
    if (Hive.isBoxOpen(name)) return;
    try {
      await Hive.openBox<T>(name);
    } catch (_) {
      if (kIsWeb) {
        try {
          await Hive.openBox(name);
        } catch (_) {}
      }
    }
  }

  await openDynamic('licenca');
  await openDynamic('temp_orders');
  await openDynamic('notificacoes_centro');
  await openTyped<Cliente>('clientes');
  await openTyped<Venda>('vendas');
  await openTyped<Produto>('produtos');
  await openTyped<EstoqueItem>('estoque');
  await openTyped<Fornecedor>('fornecedores');
  await openTyped<ProdutoCatalogo>('catalogo');
  await openTyped<CatalogoConfig>('config_catalogo');
  await openTyped<Usuario>('usuarios');
  await openTyped<FechamentoMensal>('fechamentos_mensais');
}

// Observer para restaurar última tela ao voltar do segundo plano (ex: vendas).
final LastRouteObserver _lastRouteObserver = LastRouteObserver();

/// Web: correlaciona push/pop do Navigator com o histórico do browser.
final WebNavLogObserver _webNavLogObserver = WebNavLogObserver();

// ===========================================================================
// 📱 APP PRINCIPAL (com Provider no topo)
// ===========================================================================
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>(
          create: (_) {
            try {
              Firebase.app();
              logD('[AUTH] Firebase OK – usando AuthService ONLINE');
              return AuthService();
            } catch (_) {
              logD(
                  '[AUTH] Firebase OFFLINE – usando AuthService.offline()');
              return AuthService.offline();
            }
          },
        ),
      ],
      child: ListenableBuilder(
        listenable: darkModeNotifier,
        builder: (context, child) {
          final darkMode = darkModeNotifier.value;
          return MaterialApp(
            navigatorKey: navigatorKey,
            scaffoldMessengerKey: scaffoldMessengerKey,
            navigatorObservers: [
              _lastRouteObserver,
              storeScreenRouteObserver,
              _webNavLogObserver,
            ],
            debugShowCheckedModeBanner: false,
            scrollBehavior: _SnappyScrollBehavior(),
            title: 'MasterPalm',
            theme: ThemeData(
              brightness: Brightness.light,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              scaffoldBackgroundColor: AppColors.background,
              appBarTheme: const AppBarTheme(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              colorScheme: const ColorScheme.light(
                primary: AppColors.primary,
                secondary: AppColors.accent,
                surface: AppColors.background,
                onPrimary: Colors.white,
                onSecondary: Colors.white,
                onSurface: Color(0xFF1A1A1A),
                onSurfaceVariant: Color(0xFF555555),
              ),
              textTheme: const TextTheme(
                bodyLarge: TextStyle(color: Color(0xFF1A1A1A), fontSize: 16),
                bodyMedium: TextStyle(color: Color(0xFF1A1A1A), fontSize: 14),
                titleLarge: TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 22,
                    fontWeight: FontWeight.w600),
                titleMedium: TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
                titleSmall: TextStyle(color: Color(0xFF1A1A1A), fontSize: 14),
                labelLarge: TextStyle(color: Color(0xFF1A1A1A), fontSize: 14),
              ),
              inputDecorationTheme: const InputDecorationTheme(
                border: OutlineInputBorder(),
              ),
            ),
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              scaffoldBackgroundColor: const Color(0xFF121212),
              appBarTheme: const AppBarTheme(
                backgroundColor: Color(0xFF1E1E1E),
                foregroundColor: Colors.white,
              ),
              colorScheme: const ColorScheme.dark(
                primary: Color(0xFF6366F1),
                secondary: Color(0xFF8B5CF6),
                surface: Color(0xFF1E1E1E),
                onPrimary: Colors.white,
                onSecondary: Colors.white,
                onSurface: Colors.white,
                onSurfaceVariant: Color(0xFFB0B0B0),
              ),
              textTheme: const TextTheme(
                bodyLarge: TextStyle(color: Colors.white, fontSize: 16),
                bodyMedium: TextStyle(color: Colors.white, fontSize: 14),
                titleLarge: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600),
                titleMedium: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
                titleSmall: TextStyle(color: Colors.white, fontSize: 14),
                labelLarge: TextStyle(color: Colors.white, fontSize: 14),
              ),
              inputDecorationTheme: const InputDecorationTheme(
                border: OutlineInputBorder(),
              ),
            ),
            themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('pt', 'BR')],
            initialRoute: '/',
            builder: (context, child) {
              try {
                DeepLinkHandler.instance.init();
              } catch (_) {}
              // Abrir tela de pedidos se o app foi aberto pelo toque na notificação FCM
              WidgetsBinding.instance.addPostFrameCallback((_) {
                FcmPedidoService.processPendingInitialMessage();
              });
              return UpdateCheckWrapper(
                child: NotificacaoPedidoListener(
                  child: child ?? const SizedBox.shrink(),
                ),
              );
            },
            routes: {
              '/': (_) => const AppStartRouter(),
              '/router': (_) => const AppStartRouter(),
              '/splash': (_) => const SplashScreen(),
              '/login': (_) => const LoginScreen(),
              '/register': (_) => const RegisterScreen(),
              '/verify_email': (ctx) {
                final raw = ModalRoute.of(ctx)?.settings.arguments;
                final args = raw is Map ? Map<String, dynamic>.from(raw.map((k, v) => MapEntry(k.toString(), v))) : null;
                return VerifyEmailScreen(
                  email: args?['email']?.toString(),
                  nextRoute: args?['nextRoute']?.toString() ?? '/',
                );
              },
              '/preconfig': (_) => const LojaPreconfigScreen(),
              '/fornecedores': (_) => const FornecedoresScreen(),
              '/vendas': (_) => kIsWeb
                  ? const AdminWebRouteShell(child: VendasScreen())
                  : const VendasScreen(),
              '/clientes': (_) => kIsWeb
                  ? const AdminWebRouteShell(child: ClientesScreen())
                  : const ClientesScreen(),
              '/estoque': (_) => const EstoqueScreen(),
              '/historico_cliente': (_) => const HistoricoClientesScreen(),
              '/backup': (_) => const BackupScreen(),
              '/relatorios': (_) => const RelatoriosScreen(),
              '/precificacao': (_) => const PrecificacaoUniversalScreen(),
              '/relatorio_vendedor': (_) => const RelatorioVendedorScreen(),
              '/cadastro': (_) => const CadastroScreen(),
              '/permissao': (_) => const PermissoesScreen(),
              '/permissoes': (_) => const PermissoesScreen(),
              '/plano': (_) => const PlanoScreen(),
              '/planos': (_) => const PlanosScreen(),
              '/admin_usuarios': (_) => const AdminUsuariosScreen(),
              '/master_login': (_) => const MasterLoginScreen(),
              '/master_config': (_) => const MasterConfigScreen(),
              '/site_config': (_) => const SiteConfigScreen(),
              '/cadastro_usuarios': (_) =>
                  const VendedoresScreen(), // Redireciona para tela unificada
              '/cadastro_usuario': (_) => const VendedoresScreen(), // Alias
              '/gerenciar_vendedores': (_) =>
                  const VendedoresScreen(), // Redireciona para tela unificada
              '/vendedores': (_) =>
                  const VendedoresScreen(), // Nova rota principal
              '/visualizar_permissoes': (_) =>
                  const VisualizarPermissoesScreen(),
              '/catalogo': (_) => const CatalogoScreen(),
              '/cadastro_catalogo': (_) => const CadastroCatalogoScreen(),
              '/relatorio_financeiro': (_) => const RelatorioFinanceiroScreen(),
              '/relatorios_financeiros': (_) =>
                  const RelatoriosFinanceirosScreen(),
              '/relatorio_mais_vendidos': (ctx) => _lojaIdRoute(
                (lojaId) => RelatorioMaisVendidosScreen(lojaId: lojaId),
              ),
              '/relatorio_ranking_clientes': (ctx) => _lojaIdRoute(
                (lojaId) => RelatorioRankingClientesScreen(lojaId: lojaId),
              ),
              '/relatorio_lucratividade_produto': (ctx) => _lojaIdRoute(
                (lojaId) => RelatorioLucratividadeProdutoScreen(lojaId: lojaId),
              ),
              '/carrinhos_abandonados': (ctx) => _lojaIdRoute(
                (lojaId) => CarrinhosAbandonadosScreen(lojaId: lojaId),
              ),
              '/config/pagamentos': (_) =>
                  const ConfigPagamentosSimplesScreen(),
              '/config-pagamentos': (_) =>
                  const ConfigPagamentosScreen(), // Avançado
              '/admin_sync': (_) => const AdminSyncScreen(),
              '/configuracoes_catalogo': (_) => const LojaConfigScreen(),
              '/health': (_) => const HealthCheckScreen(),
              '/diagnostico': (_) => const DiagnosticoAppScreen(),
              '/ajuda': (_) => const AjudaScreen(),
              '/config_pin': (_) => const ConfigPinScreen(),
              '/test_checkout': (_) => const TestCheckout(),
              '/pedidos_pendentes': (_) => _pedidosRoute(),
              '/pedidos': (ctx) {
                final raw = ModalRoute.of(ctx)?.settings.arguments;
                final map = raw is Map ? Map<String, dynamic>.from(raw.map((k, v) => MapEntry(k.toString(), v))) : null;
                final lojaIdArg = map?['lojaId']?.toString();
                final pedidoIdArg = map?['pedidoId']?.toString();
                if (lojaIdArg != null && lojaIdArg.isNotEmpty) {
                  return PrePedidosScreen(
                    lojaId: lojaIdArg,
                    initialPedidoId: pedidoIdArg?.isNotEmpty == true ? pedidoIdArg : null,
                  );
                }
                return _pedidosRoute();
              },
              '/onboarding_loja': (_) => const OnboardingLojaScreen(),
              '/campanhas_sorteio': (_) => const CampanhasSorteioScreen(),
              '/fretes_cupons': (_) => const FretesCuponsScreen(),
              '/metas_comissoes': (_) => const MetasComissoesScreen(),
              '/motor_crescimento': (ctx) => _lojaIdRoute(
                (lojaId) => MotorCrescimentoScreen(lojaId: lojaId),
              ),
              '/campanhas_sugeridas': (ctx) => _lojaIdRoute(
                (lojaId) => CampanhasSugeridasScreen(lojaId: lojaId),
              ),
              '/notas_fiscais': (_) => const NotasFiscaisScreen(),
              '/contas_receber': (_) => const ContasReceberScreen(),
              '/globo_sorteio': (_) => const GloboSorteioScreenWrapper(),
              '/home': (_) => const HomeScreen(),

              // ✅ ROTA /loja: na Web usa SEMPRE o lojaId da URL (path ou fragment); no app usa LojaIdService
              '/loja': (_) {
                if (kIsWeb) {
                  final fromUrl = _lojaSlugOrIdFromUrl();
                  if (fromUrl.isNotEmpty && fromUrl != 'minha-loja') {
                    final page = Uri.base.queryParameters['page']?.trim();
                    final cartId = Uri.base.queryParameters['cart']?.trim();
                    final produtoId = Uri.base.queryParameters['produto']?.trim();
                    logD('🛒 [ROUTE /loja] Web: lojaId da URL → $fromUrl, page=$page, cart=$cartId, produto=$produtoId');
                    return PublicCatalogScreen(
                        lojaId: fromUrl,
                        vendedorRef: _vendedorRefFromUrl(),
                        indicacaoClienteRef: _indicacaoRefFromUrl(),
                        initialPage: page?.isNotEmpty == true ? page : null,
                        initialCartId: cartId?.isNotEmpty == true ? cartId : null,
                        initialProdutoId: produtoId?.isNotEmpty == true ? produtoId : null);
                  }
                }
                return FutureBuilder<String?>(
                  future: LojaIdService.get(),
                  builder: (_, snap) {
                    final lojaId = (snap.data ?? '').trim();
                    // Sem loja ou placeholder: mostra "Configure sua loja online". Nunca abre outra loja.
                    if (lojaId.isEmpty || !isValidForPublicLink(lojaId)) {
                      logD('🛒 [ROUTE /loja] Sem loja válida → ConfigureLojaPlaceholderScreen');
                      return const ConfigureLojaPlaceholderScreen();
                    }
                    final vendedorRef = _vendedorRefFromUrl();
                    final indicacaoRef = _indicacaoRefFromUrl();
                    final cartId = kIsWeb ? (Uri.base.queryParameters['cart']?.trim()) : null;
                    final produtoId = kIsWeb ? (Uri.base.queryParameters['produto']?.trim()) : null;
                    return PublicCatalogScreen(
                        lojaId: lojaId,
                        vendedorRef: vendedorRef,
                        indicacaoClienteRef: indicacaoRef,
                        initialCartId: cartId?.isNotEmpty == true ? cartId : null,
                        initialProdutoId: produtoId?.isNotEmpty == true ? produtoId : null);
                  },
                );
              },
            },
            onGenerateRoute: app_routes.onGenerateRoute,
          );
        },
      ),
    );
  }
}
