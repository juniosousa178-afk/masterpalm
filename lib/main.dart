// lib/main.dart
import 'dart:async';
import 'dart:convert';

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, defaultTargetPlatform, TargetPlatform;

import 'core/logger.dart';
import 'package:flutter/material.dart';
import 'url_strategy_stub.dart' if (dart.library.html) 'url_strategy_web.dart'
    as url_strategy;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';

// App Check config
import 'config/app_check_config.dart';
import 'config/app_urls.dart';
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
import 'firebase_bootstrap_options.dart';
import 'firebase_options.dart';
import 'themes/app_colors.dart';
import 'app_routes.dart' as app_routes;
import 'utils/last_route_observer.dart';
import 'utils/store_screen_route_observer.dart';
import 'bootstrap/web_popstate_logger.dart';
import 'web/platform_stub.dart' if (dart.library.html) 'web/platform_web.dart'
    as web_plat;
import 'utils/web_nav_log_observer.dart';
import 'widgets/admin_web_route_shell.dart';

// Telas
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/fornecedor_screen.dart';
import 'screens/vendas_screen.dart';
import 'screens/clientes_screen.dart';
import 'screens/vendas_canceladas_vendedor_screen.dart';
import 'screens/estoque_screen.dart';
import 'screens/catalogo_interno_screen.dart';
import 'screens/historico_clientes_screen.dart';
import 'screens/backup_screen.dart';
import 'screens/relatorios_screen.dart';
import 'screens/precificacao_universal_screen.dart';
import 'screens/relatorio_vendedor_screen.dart';
import 'screens/cadastro_screen.dart';
import 'screens/permissoes_screen.dart';
import 'screens/app_start_router.dart';
import 'screens/web_public_marketing_app.dart';
import 'screens/plano_screen.dart';
import 'screens/config_pin_screen.dart';
// import 'screens/cadastro_usuario_screen.dart'; // Substituído por vendedores_screen.dart
import 'screens/visualizar_permissoes_screen.dart';
import 'screens/catalago_screen.dart';
import 'screens/cadastro_catalogo_screen.dart';
import 'screens/relatorio_financeiro_screen.dart';
import 'screens/relatorios_financeiros_screen.dart';
import 'screens/public_catalog_screen.dart';
import 'screens/public_catalog/catalog_url_query_codec.dart';
import 'catalog/catalog_bootstrap_loading.dart';
import 'catalog/catalog_initial_web_route.dart';
import 'debug/web_root_boot_trace_app.dart';
import 'debug/invalid_public_loja_path_app.dart';
import 'debug/app_start_trace_collector.dart';
import 'debug/boot_perf_log.dart';
import 'services/catalog_domain_resolver.dart';
import 'services/catalog_domain_browser_cache.dart';
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
import 'screens/marketing/marketing_hub_screen.dart';
import 'screens/marketing/campanhas_dashboard_screen.dart';
import 'screens/marketing/roleta_dashboard_screen.dart';
import 'screens/marketing/roleta_historico_screen.dart';
import 'screens/marketing/marketing_estatisticas_screen.dart';
import 'screens/carrinho_abandonado_config_screen.dart';
// import 'screens/gerenciar_vendedores_screen.dart'; // Substituído por vendedores_screen.dart
import 'screens/vendedores_screen.dart';
import 'screens/fretes_cupons_screen.dart';
// pedido_publico_screen e pagamento_resultado_screen usados em app_routes.dart
import 'screens/admin_sync_screen.dart';
import 'screens/admin_usuarios_screen.dart';
import 'screens/master_login_screen.dart';
import 'screens/mestre/master_plan_access_screen.dart';
import 'screens/mp_oauth_callback_screen.dart';
import 'screens/master_config_screen.dart';
import 'screens/catalog_payment_support_screen.dart';
import 'screens/site_config_screen.dart';
import 'widgets/scope_route_gate.dart';
import 'core/access_scope_service.dart';
import 'screens/notas_fiscais_screen.dart';
import 'screens/contas_receber_screen.dart';
import 'screens/contas_pagar_screen.dart';
import 'screens/financeiro/financeiro_screen.dart';
import 'screens/relatorio_mais_vendidos_screen.dart';
import 'screens/relatorio_ranking_clientes_screen.dart';
import 'screens/relatorio_lucratividade_produto_screen.dart';
import 'screens/carrinhos_abandonados_screen.dart';
import 'screens/catalog_avaliacoes_moderacao_screen.dart';

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
import 'screens/modelos_importacao_screen.dart';
import 'screens/dicas_ia_screen.dart';
import 'screens/textos_whatsapp_ia_screen.dart';
import 'screens/gerar_postagem_screen.dart';
import 'screens/compartilhar_whatsapp_screen.dart';
import 'screens/analise_vendas_ia_screen.dart';
import 'screens/dashboard_insights_screen.dart';
import 'screens/loja_preview_shell_screen.dart';

// Widgets
import 'widgets/notificacao_pedido_listener.dart';
import 'widgets/update_check_wrapper.dart';
import 'widgets/plan_gated_screen.dart';

import 'core/plan_matrix.dart';
import 'screens/marketplaces_screen.dart';
import 'screens/configuracoes/canais_meta_screen.dart';

// Serviços
import 'services/deep_link_handler.dart';
import 'services/fcm_pedido_service.dart';
import 'services/test_checkout.dart';
import 'services/permissoes_service.dart';
import 'services/backup_auto_service_io.dart'
    if (dart.library.html) 'services/backup_auto_service_web.dart'
    as backup_auto_service;
import 'services/produto_auto_sync_service.dart';
import 'services/notificacao_service.dart';
import 'services/auto_sync_service.dart';
import 'services/sync_queue_service.dart';
import 'services/soft_delete_service.dart';
import 'services/financeiro_soft_delete_service.dart';

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
import 'models/conta_pagar.dart';
import 'models/lancamento_financeiro.dart';
import 'models/gasto_fixo_mensal.dart';
import 'models/compra_fornecedor.dart';
import 'models/compra_fornecedor_item.dart';
import 'models/compra_item_pipeline.dart';
import 'models/estoque_item.dart';
import 'models/categoria.dart';

// 🔍 Debug helpers
import 'debug/bootstrap_diagnostics.dart'; // boot, FirebaseGuard
import 'debug/global_error_hook.dart'; // runWithGlobalErrorHook
import 'debug/catalog_startup_trace.dart';

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
bool _appCheckWebOk =
    false; // true apenas quando ativação Web teve sucesso (ETAPA 20).
DateTime? _appCheckBackoffUntil;

Future<void> initFirebaseAppCheck() async {
  logD('🛡️ [AppCheck] Iniciando ativação...');

  if (!isAppCheckSupportedPlatform) {
    logD(
        'ℹ️ [AppCheck] Plataforma ${defaultTargetPlatform.name} não suporta App Check. Pulando.');
    return;
  }

  if (_appCheckActivatedOnce) {
    logD(
        'ℹ️ [AppCheck] Já ativado nesta sessão (evitando throttle). Pulando nova ativação.');
    _debugPrintAppCheckDiagnostics();
    return;
  }

  final backoffUntil = _appCheckBackoffUntil;
  if (backoffUntil != null && DateTime.now().isBefore(backoffUntil)) {
    logD(
        'ℹ️ [AppCheck] Em backoff (400/erro de rede). Aguardando ${backoffUntil.difference(DateTime.now()).inSeconds}s.');
    return;
  }

  if (skipAppCheckOnWebInDebug) {
    logD(
        'ℹ️ [AppCheck] Web em modo debug: pulando ativação (evita 400/throttle em localhost).');
    _appCheckActivatedOnce = true;
    _debugPrintAppCheckDiagnostics();
    return;
  }

  try {
    if (kDebugMode && !kIsWeb) {
      logD(
          '[LOGIN-APPCHECK] Iniciando App Check para ${defaultTargetPlatform.name}');
    }
    if (kIsWeb) {
      // ETAPA 20: Web soft-fail — uma única tentativa; em erro não bloqueia Auth/login.
      try {
        final host = Uri.base.host.isEmpty ? 'unknown' : Uri.base.host;
        if (!isHostAllowed(host)) {
          logW(
              '[AppCheck] host não permitido; não ativando. Login continua normalmente.',
              tag: 'APP-CHECK');
          _appCheckActivatedOnce = true;
          _debugPrintAppCheckDiagnostics();
          return;
        }
        logD('[AppCheck] host=$host activate.start');
        final ok = await _activateAppCheckWeb();
        if (!ok) {
          _appCheckBackoffUntil =
              DateTime.now().add(const Duration(seconds: 60));
          logW(
              '[AppCheck] Ativação Web falhou (400/throttle/storage). App e login Google continuam.',
              tag: 'APP-CHECK');
          _appCheckActivatedOnce = true;
          _debugPrintAppCheckDiagnostics();
          return;
        }
        _appCheckWebOk = true;
        logD('[AppCheck] activate.ok');
      } catch (e, st) {
        _appCheckWebOk = false;
        _appCheckActivatedOnce = true;
        logW(
            '[AppCheck] Web: falha na ativação (ignorado). Login continua normalmente.',
            tag: 'APP-CHECK');
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
    if (kIsWeb && kDebugMode)
      logD(
          '[AppCheck] Web: token auto-refresh desligado para evitar 400 em cascata.');

    if (useDebugProvider && !kIsWeb) {
      _appCheckSelfCheck();
    }
    _debugPrintAppCheckDiagnostics();
  } on FirebaseException catch (e) {
    final msg = (e.message ?? '').toLowerCase();
    final is400 = e.code.contains('400') ||
        msg.contains('400') ||
        msg.contains('bad request');
    final isConnectionError = msg.contains('connection_closed') ||
        msg.contains('err_connection') ||
        msg.contains('connection');
    final isAttestationFailed = msg.contains('attestation failed') ||
        msg.contains('app attestation failed');
    if (!kIsWeb && kDebugMode && isAttestationFailed) {
      logD(
          '[AppCheck] Detectado attestation failed (debug). Cadastre o Debug Token em Firebase Console → App Check → Tokens de depuração.');
      _logDebugTokenInstructions();
    }
    if (kIsWeb) {
      _appCheckWebOk = false;
      _appCheckActivatedOnce = true;
      if (is400 || isConnectionError) {
        _appCheckBackoffUntil = DateTime.now().add(const Duration(seconds: 60));
        logW('[AppCheck] 400/erro de rede no Web. App e login continuam.',
            tag: 'APP-CHECK');
      } else {
        logW(
            '[AppCheck] activate.fail Web: ${e.code}. App continua sem proteção.',
            tag: 'APP-CHECK');
      }
    } else {
      if (is400 || isConnectionError) {
        _appCheckBackoffUntil = DateTime.now().add(const Duration(seconds: 60));
        logD(
            '[AppCheck] 400 ou erro de rede detectado. Backoff 60s. App continua normalmente.');
      } else {
        logD(
            '[AppCheck] activate.fail: ${e.code} ${e.message ?? ""}. App continua sem proteção.');
      }
      _appCheckActivatedOnce = true;
    }
    if (kIsWeb && kDebugMode) {
      logD(
          '   [AppCheck] Web: recaptcha_site_key (Remote Config) ou kRecaptchaSiteKeyOverride.');
    }
    _debugPrintAppCheckDiagnostics();
  } catch (e, st) {
    if (kIsWeb) {
      _appCheckWebOk = false;
      _appCheckActivatedOnce = true;
      logW(
          '[AppCheck] Web: falha na ativação (ignorado). Login continua normalmente.',
          tag: 'APP-CHECK');
      if (kDebugMode) logD('   (type=${e.runtimeType})');
      if (kDebugMode) logD('   $st');
    } else {
      final msg = e.toString().toLowerCase();
      final is400OrConnection = msg.contains('400') ||
          msg.contains('connection_closed') ||
          msg.contains('err_connection');
      final isAttestationFailed = msg.contains('attestation failed') ||
          msg.contains('app attestation failed');
      if (is400OrConnection) {
        _appCheckBackoffUntil = DateTime.now().add(const Duration(seconds: 60));
        logD(
            '[AppCheck] 400 ou erro de rede detectado. Backoff 60s. App continua normalmente.');
      } else if (kDebugMode && isAttestationFailed) {
        logD(
            '[AppCheck] Attestation failed. Cadastre o Debug Token em Firebase Console → App Check → Tokens de depuração.');
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
    final host = kIsWeb
        ? (Uri.base.host.isEmpty ? 'unknown' : Uri.base.host)
        : defaultTargetPlatform.name;
    logD(
        '   [AppCheck] Diagnóstico: host=$host | ativadoUmaVez=$_appCheckActivatedOnce');
  } catch (_) {}
}

/// Para telas de diagnóstico: retorna host e confirmação de que activate rodou apenas uma vez.
Map<String, String> getAppCheckDiagnostics() {
  return {
    'host': kIsWeb
        ? (Uri.base.host.isEmpty ? 'unknown' : Uri.base.host)
        : defaultTargetPlatform.name,
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
    logW(
        '[AppCheck] Web: recaptcha_site_key vazia; não ativar. Login continua.',
        tag: 'APP-CHECK');
    return false;
  }
  final keyPreview =
      recaptchaKey.length >= 6 ? '${recaptchaKey.substring(0, 6)}...' : '***';
  logD(
      '[AppCheck] Provider: reCAPTCHA v3 (Web) | host=$host | key=$keyPreview');

  try {
    await FirebaseAppCheck.instance.activate(
      webProvider: ReCaptchaV3Provider(recaptchaKey),
    );
    return true;
  } on FirebaseException catch (e) {
    logW(
        '[AppCheck] Web: ${e.code} ${e.message ?? "sem mensagem"}. Login continua.',
        tag: 'APP-CHECK');
    if (e.code == 'app-check/throttled' ||
        (e.message?.toLowerCase().contains('throttl') ?? false)) {
      logD('[AppCheck] throttle detectado. Não ativar novamente nesta sessão.');
    }
    return false;
  } catch (e) {
    logW('[AppCheck] Web: falha na ativação. Login continua.',
        tag: 'APP-CHECK');
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
  logD(
      '   │ Firebase Console → App Check → Apps → [Android/iOS] → Tokens de depuração');
  logD('   │');
  logD('   │ Como obter o token:');
  if (defaultTargetPlatform == TargetPlatform.android) {
    logD('   │   adb logcat | grep -i DebugAppCheckProvider');
    logD(
        '   │   ou no Android Studio Logcat, filtrar por "debug secret" ou "App Check"');
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
        logD(
            '⚠️ [AppCheck] Self-check falhou (esperado em debug sem token cadastrado).');
        logD(
            '   → Cadastre o Debug Token em: Firebase Console → App Check → Tokens de depuração');
        logD(
            '   → O token aparece no Logcat (Android) ou Xcode (iOS) ao rodar o app.');
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

/// Overflow visual de [RenderFlex] não é falha de runtime: evita ruído como fatal no Crashlytics.
bool _isRenderFlexLayoutOverflowDetails(FlutterErrorDetails details) {
  final s = details.exceptionAsString();
  return s.contains('A RenderFlex overflowed');
}

bool _isRenderFlexLayoutOverflowMessage(Object error) {
  return error.toString().contains('A RenderFlex overflowed');
}

Future<void> initFirebaseMonitoring() async {
  // Se Firebase não estiver inicializado (ex.: modo OFFLINE / timeout), não tentar
  // acessar Crashlytics para evitar core/no-app durante o próprio handler.
  if (Firebase.apps.isEmpty) {
    logD(
        'ℹ️ Crashlytics omitido: Firebase.apps.isEmpty (modo OFFLINE ou init falhou).');
    return;
  }

  if (!kIsWeb) {
    FirebaseCrashlytics? crash;
    try {
      crash = FirebaseCrashlytics.instance;
      await crash.setCrashlyticsCollectionEnabled(true);

      FlutterError.onError = (details) {
        logE('🔴 [FlutterError] ${details.exception}',
            error: details.exception, st: details.stack);
        if (details.exception.toString().contains('overflowed')) {
          logW('🔴 [OVERFLOW DETECTADO] ${details.exception}');
        }
        FlutterError.presentError(details);
        // Protege contra falhas do próprio Crashlytics (ex.: plugin indisponível)
        final c = crash;
        if (c != null) {
          try {
            if (_isRenderFlexLayoutOverflowDetails(details)) {
              c.recordFlutterError(details);
            } else {
              c.recordFlutterFatalError(details);
            }
          } catch (e, st) {
            logE('⚠️ Crashlytics recordFlutter* falhou (ignorado).',
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
        logE('💥 [PlatformDispatcher] $unwrapped',
            error: unwrapped, st: unwrappedStack);
        final c = crash;
        if (c != null) {
          try {
            final fatal = !_isRenderFlexLayoutOverflowMessage(unwrapped);
            c.recordError(unwrapped, unwrappedStack, fatal: fatal);
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
      logE('🔴 [FlutterError/Web] ${details.exception}',
          error: details.exception, st: details.stack);
      FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      Object unwrapped = error;
      StackTrace unwrappedStack = stack;
      if (error is AsyncError) {
        unwrapped = error.error;
        unwrappedStack = error.stackTrace;
      }
      logE('💥 [PlatformDispatcher/Web] $unwrapped',
          error: unwrapped, st: unwrappedStack);
      return true;
    };
  }

  if (kIsWeb) {
    logD(
      'ℹ️ Analytics omitido no Web para evitar FirebaseAnalyticsWeb indisponível.',
    );
    return;
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
// 🔧 Normaliza links salvos para o App Web canônico (ver AppUrls / docs/DOMAIN_APP_WEB.md)
// ===========================================================================
Future<void> _fixPedidoLinkBase() async {
  final cfg = Hive.box('config');

  String migrateAppWebHosts(String s) {
    var t = s;
    // Legado temporário app.masterpalm.com.br → canônico app.mastepalm.com.br
    t = t.replaceAll('https://app.masterpalm.com.br', AppUrls.appWebBase);
    t = t.replaceAll('http://app.masterpalm.com.br', AppUrls.appWebBase);
    t = t.replaceAll('app.masterpalm.com.br', AppUrls.appWebHostCanonical);
    return t;
  }

  /// mastepalm.com.br (apex) → gestao.mastepalm.com.br; não altera app.* nem subdomínios.
  String migratePublicSiteApex(String s) {
    var t = s.trim();
    if (t.isEmpty) return t;
    final re = RegExp(r'^https?://(www\.)?mastepalm\.com\.br(?=/|$)',
        caseSensitive: false);
    if (re.hasMatch(t) && !t.toLowerCase().contains('app.mastepalm')) {
      t = t.replaceFirst(re, AppUrls.landingBase);
    }
    return t;
  }

  final atual = _safeString(cfg.get('pedido_link_base'));
  final novo = atual.isEmpty
      ? '${AppUrls.appWebBase}/pedido'
      : migrateAppWebHosts(atual);
  await cfg.put('pedido_link_base', novo);

  final pub = _safeString(cfg.get('public_link_base_url'));
  if (pub.isNotEmpty &&
      pub.contains('mastepalm.com.br') &&
      !pub.contains('app.')) {
    final migrated = migratePublicSiteApex(migrateAppWebHosts(pub));
    if (migrated != pub) {
      await cfg.put('public_link_base_url', migrated);
    }
  }
}

// ===========================================================================
// ⚡ BOOT: trabalho pesado após o 1º frame (reduz skipped frames na subida)
// ===========================================================================
bool _loggedInHeavyWorkScheduled = false;

/// Agenda [work] após o próximo frame; [delay] extra evita competir com transição runApp.
void scheduleBootstrapDeferredWork({
  Duration delay = Duration.zero,
  required Future<void> Function() work,
  required String logTag,
}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    logD('[BOOT_DEFERRED] $logTag (pós-frame + ${delay.inMilliseconds}ms)');
    if (delay == Duration.zero) {
      unawaited(work());
    } else {
      Future<void>.delayed(delay, () => unawaited(work()));
    }
  });
}

/// Boxes legadas, fila de sync, push, auto-sync, backup — fora do caminho crítico até a UI respirar.
Future<void> _bootstrapLoggedInHeavy({required bool firebaseOk}) async {
  logD('[BOOT_CRITICAL] → [BOOT_DEFERRED] início _bootstrapLoggedInHeavy');
  try {
    await _openRemainingHiveBoxes();
    boot.mark('hive.boxes.ok');

    try {
      await SyncQueueService.init();
      SyncQueueService.setOnReconnect(AutoSyncService.syncEmBackground);
      SyncQueueService.startConnectivityListener();
      unawaited(SyncQueueService.processPending().then((r) {
        if (r.processed > 0) {
          logD(
              '📋 [BOOT_DEFERRED] SyncQueue: ${r.processed} itens processados');
        }
      }));
    } catch (e) {
      logW('⚠️ [BOOT_DEFERRED] SyncQueueService (type=${e.runtimeType})');
    }

    if (firebaseOk && !kIsWeb) {
      try {
        FcmPedidoService.setNavigatorKey(navigatorKey);
        await FcmPedidoService.init();
      } catch (e) {
        logW('⚠️ [BOOT_DEFERRED] FCM pedido (type=${e.runtimeType})');
      }
    }

    if (!kIsWeb) {
      try {
        await NotificacaoService.init();
        logD('🔔 [BOOT_DEFERRED] NotificacaoService OK');
      } catch (e) {
        logW('⚠️ [BOOT_DEFERRED] NotificacaoService (type=${e.runtimeType})');
      }
    }

    try {
      final lojaDiag = await LojaIdService.get();
      logD('🟪 [BOOT_DEFERRED] LojaIdService.get() → $lojaDiag');
    } catch (e) {
      logD('🟥 [BOOT_DEFERRED] LojaIdService.get() (type=${e.runtimeType})');
    }

    if (Firebase.apps.isNotEmpty) {
      try {
        await refreshPermissoesLocais();
      } catch (e) {
        logW(
            '⚠️ [BOOT_DEFERRED] refreshPermissoesLocais (type=${e.runtimeType})');
      }
    }

    try {
      await backup_auto_service.BackupAutoService.iniciarAgendamento();
      boot.mark('backup.auto.ok');
    } catch (e) {
      logW('⚠️ [BOOT_DEFERRED] BackupAuto (type=${e.runtimeType})');
      boot.mark('backup.auto.fail', e);
    }

    try {
      await ProdutoAutoSyncService().start();
      boot.mark('autosync.ok');
      logD('✅ [BOOT_DEFERRED] Auto-sincronização de produtos iniciada');
    } catch (e) {
      logW('⚠️ [BOOT_DEFERRED] auto-sync (type=${e.runtimeType})');
      boot.mark('autosync.fail', e);
    }

    try {
      await SoftDeleteService.processOnStartup();
      await FinanceiroSoftDeleteService.processOnStartup();
      logD('🟢 [BOOT_DEFERRED] SoftDeleteService.processOnStartup OK');
    } catch (e) {
      logW('⚠️ [BOOT_DEFERRED] SoftDelete (type=${e.runtimeType})');
    }

    logD('🟢 [BOOT_DEFERRED] _bootstrapLoggedInHeavy concluído');
    logD(boot.dump());
  } catch (e, st) {
    logW(
        '⚠️ [BOOT_DEFERRED] _bootstrapLoggedInHeavy falhou (type=${e.runtimeType})');
    if (kDebugMode) logD('$st');
  }
}

void _scheduleLoggedInHeavyOnce({required bool firebaseOk}) {
  if (_loggedInHeavyWorkScheduled) return;
  _loggedInHeavyWorkScheduled = true;
  scheduleBootstrapDeferredWork(
    delay: const Duration(milliseconds: 80),
    logTag: 'logged_in_heavy',
    work: () => _bootstrapLoggedInHeavy(firebaseOk: firebaseOk),
  );
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

/// Guard de plano em rotas nomeadas (deep link / push direto).
Widget _planGate(PlanGateFeature f, Widget child) =>
    PlanGatedScreen(feature: f, child: child);

/// Guard de autenticação para rotas acessadas direto por URL no Web
/// (ex.: /planos em janela anônima).
Widget _authRoute(Widget child) {
  return StreamBuilder<User?>(
    stream: FirebaseAuth.instance.authStateChanges(),
    initialData: FirebaseAuth.instance.currentUser,
    builder: (context, snap) {
      final u = snap.data;
      if (u != null && !u.isAnonymous) return child;
      return const LoginScreen();
    },
  );
}

Widget _lojaIdRouteGated(
  PlanGateFeature f,
  Widget Function(String lojaId) builder,
) {
  return _lojaIdRoute((lojaId) => _planGate(f, builder(lojaId)));
}

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
                  const Icon(Icons.store_outlined,
                      size: 64, color: Colors.grey),
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
    logD('🔍 [RESOLVER] "$raw" parece store_id, verificando existência...');

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

/// Após [catalog_domains] devolver [lojaId] canônico: 1 leitura direta `lojas/{id}` (rápida), só depois slug.
Future<String> _fastResolveStoreIdFromDomainIndex(
    String lojaIdFromIndex) async {
  final raw = lojaIdFromIndex.trim();
  if (raw.isEmpty) return raw;
  if (Firebase.apps.isEmpty) return raw;
  try {
    final doc = await FirebaseFirestore.instance
        .collection('lojas')
        .doc(raw)
        .get()
        .timeout(const Duration(seconds: 2));
    if (doc.exists) {
      final redirectTo = (doc.data()?['redirectTo'] ?? '').toString().trim();
      if (redirectTo.isNotEmpty && redirectTo != raw) {
        return redirectTo;
      }
      return raw;
    }
  } on TimeoutException catch (_) {
    return raw;
  } catch (_) {
    return raw;
  }
  try {
    return await _resolveSlugToStoreIdIfNeeded(raw)
        .timeout(const Duration(seconds: 3));
  } catch (_) {
    return raw;
  }
}

bool _isLocalWebDevHost(String normalizedHost) {
  return normalizedHost == 'localhost' ||
      normalizedHost == '127.0.0.1' ||
      normalizedHost.endsWith('.localhost');
}

bool _shouldOfferCustomDomainCatalogFastPath(Uri uri) {
  if (!kIsWeb) return false;
  if (_uriIsPagamentoPublicPath(uri)) return false;
  if (isAdminWebAppPath(uri)) return false;
  if (AppUrls.isFirebaseAdminAppPreviewHost(uri.host)) return false;
  if (_uriHasLojaPathPriority(uri)) return false;
  if (_uriHasExplicitCatalogQueryOrFragment(uri)) return false;
  final hostNorm =
      normalizeCatalogDomainHost(AppUrls.normalizeHostForAppUrlCheck(uri.host));
  if (hostNorm.isEmpty) return false;
  if (_isLocalWebDevHost(hostNorm)) return false;
  if (AppUrls.isDefaultMasterPalmCatalogHost(uri.host)) return false;
  if (AppUrls.isPublicMarketingHost(uri.host)) return false;
  return true;
}

void _logWebCatalogDiag({
  required String source,
  String? slugOrId,
  String? resolvedLojaId,
}) {
  if (!kIsWeb) return;
  try {
    final uri = _initialWebUri ?? Uri.base;
    final ua = web_plat.Web.userAgent();
    logD(
      '[CAT_DIAG][$source] host=${uri.host} path=${uri.path} query=${uri.query} '
      'slug=$slugOrId lojaId=$resolvedLojaId ua=$ua',
    );
  } catch (_) {}
}

Future<void> _logCatalogRuntimeError({
  required String fase,
  required Object error,
  StackTrace? stack,
  String? slug,
  String? lojaId,
  String? source,
  int? lineno,
  int? colno,
  String? library,
  String? context,
}) async {
  if (!kIsWeb) return;
  try {
    final uri = _initialWebUri ?? Uri.base;
    final payload = <String, dynamic>{
      'buildId': kCatalogDiagBuildId,
      'timestamp': DateTime.now().toIso8601String(),
      'host': uri.host,
      'path': uri.path,
      'query': uri.query,
      'userAgent': web_plat.Web.userAgent(),
      'slug': slug ?? _lojaSlugOrIdFromUrl(),
      'lojaId': lojaId ?? '',
      'error': error.toString(),
      'stack': (stack ?? StackTrace.current).toString(),
      'fase': fase,
      'phase': web_plat.Web.localStorageGet('mp_catalog_phase') ?? fase,
      'source': source ?? '',
      'lineno': lineno ?? 0,
      'colno': colno ?? 0,
      'library': library ?? '',
      'context': context ?? '',
      'appVersion': 'web',
    };
    web_plat.Web.localStorageSet('mp_last_runtime_error', jsonEncode(payload));
    if (_safeFirebaseAppsIsNotEmpty()) {
      try {
        await FirebaseFirestore.instance
            .collection('catalog_runtime_errors')
            .add(payload);
      } on Object catch (_) {}
    }
  } catch (_) {}
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
  logD('Uri.base          = ${kIsWeb ? Uri.base.toString() : "(not web)"}');
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

  final String? existingSlug =
      _safeStringFromDynamic(cfg.get('store_slug'))?.toLowerCase();
  final String? existingLojaSlug =
      _safeStringFromDynamic(cfg.get('loja_slug'))?.toLowerCase();

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
          logD(
              '✅ [WEB_BOOTSTRAP] store_id resolvido via StoreResolver → $lojaId');
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
          logD(
              '🔄 [WEB_BOOTSTRAP] Fallback loja_uid_$uid (StoreResolver não retornou)');
        }
      } catch (_) {}
    }
    lojaId ??= (() {
      final u = _safeString(sessao.get('usuario_logado'), '');
      if (u.isNotEmpty) {
        final fallback = 'loja_email_${_safeSlug(u)}';
        logD(
            '🔄 [WEB_BOOTSTRAP] Fallback loja_email_ (StoreResolver não retornou)');
        return fallback;
      }
      return null;
    })();
  }

  if (lojaId == null || lojaId.isEmpty) {
    logW(
        '⚠️ [WEB_BOOTSTRAP] Não foi possível definir store_id automaticamente.');
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
const String kCatalogDiagBuildId = String.fromEnvironment(
  'CATALOG_BUILD_ID',
  defaultValue: 'dev',
);
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void _setCatalogPhase(String phase) {
  if (!kIsWeb) return;
  web_plat.Web.localStorageSet('mp_catalog_phase', phase);
}

Widget _buildEarlyCatalogErrorFallback({
  required Object error,
  required StackTrace stack,
}) {
  final uri = _initialWebUri ?? Uri.base;
  final diag = uri.queryParameters['diag'] == '1';
  if (!diag) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Não foi possível carregar a loja agora. Tente novamente em instantes.',
              textAlign: TextAlign.center,
              style: ThemeData.light().textTheme.titleMedium,
            ),
          ),
        ),
      ),
    );
  }
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      appBar: AppBar(title: const Text('Diagnóstico Catálogo')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          'buildId=$kCatalogDiagBuildId\n'
          'host=${uri.host}\n'
          'path=${uri.path}\n'
          'query=${uri.query}\n'
          'userAgent=${web_plat.Web.userAgent()}\n'
          'slug=${_lojaSlugOrIdFromUrl()}\n'
          'fase=${web_plat.Web.localStorageGet('mp_catalog_phase') ?? 'early.error_widget'}\n'
          'error=${error.toString()}\n'
          'stack=${stack.toString()}',
        ),
      ),
    ),
  );
}

void _installUltraEarlyCatalogErrorCapture() {
  if (!kIsWeb) return;
  ErrorWidget.builder = (FlutterErrorDetails details) {
    final st = details.stack ?? StackTrace.current;
    final contextDesc = details.context?.toDescription() ?? '';
    final payload = <String, dynamic>{
      'buildId': kCatalogDiagBuildId,
      'timestamp': DateTime.now().toIso8601String(),
      'host': (_initialWebUri ?? Uri.base).host,
      'path': (_initialWebUri ?? Uri.base).path,
      'query': (_initialWebUri ?? Uri.base).query,
      'userAgent': web_plat.Web.userAgent(),
      'slug': _lojaSlugOrIdFromUrl(),
      'lojaId': '',
      'fase': 'error_widget.ultra_early',
      'phase': web_plat.Web.localStorageGet('mp_catalog_phase') ?? 'main.start',
      'error': details.exceptionAsString(),
      'stack': st.toString(),
      'library': details.library ?? '',
      'context': contextDesc,
      'appVersion': 'web',
    };
    try {
      web_plat.Web.localStorageSet(
          'mp_last_runtime_error', jsonEncode(payload));
    } catch (_) {}
    unawaited(_logCatalogRuntimeError(
      fase: 'error_widget.ultra_early',
      error: details.exception,
      stack: st,
      source: details.library,
      context: contextDesc,
    ));
    return _buildEarlyCatalogErrorFallback(error: details.exception, stack: st);
  };
}

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

const Duration _kHiveOpenBudget = Duration(seconds: 12);
const Duration _kHiveInitFlutterBudget = Duration(seconds: 10);

/// `?diag=1&appStartTrace=1` — instrumentação do arranque (raiz web; tela "Preparando tudo" = [_BootApp]).
bool _isAppStartTraceQuery() {
  if (!kIsWeb) return false;
  final u = _initialWebUri ?? Uri.base;
  return u.queryParameters['diag'] == '1' &&
      u.queryParameters['appStartTrace'] == '1';
}

void _appStartMark(
  String phase, {
  String? detail,
  String? finalDecision,
}) {
  if (!_isAppStartTraceQuery()) return;
  AppStartTraceCollector.mark(phase, detail: detail, finalDecision: finalDecision);
}

/// Decisão de rota inicial (web) — pura, testada em [test/catalog_initial_web_route_test.dart].
CatalogRouteDecision _catalogRouteDecisionForInitialWebUri() {
  final u = _initialWebUri ?? Uri.base;
  return CatalogRouteDecision.fromUri(
    u,
    isDefaultAppOrCatalogHostingHost: AppUrls.isDefaultMasterPalmCatalogHost,
    isPublicMarketingHost: AppUrls.isPublicMarketingHost,
    customDomainMappingResolved: null,
  );
}

/// Web: abertura só como visitante do catálogo (sem precisar do bootstrap pesado do app).
/// Usa o mesmo critério do roteamento pós-bootstrap: path `/loja` ou host em [catalog_domains].
Future<bool> _webShouldMinimalBootstrapForPublicCatalogViewer() async {
  if (!kIsWeb) return false;
  if (Firebase.apps.isEmpty) return false;
  final uri = _initialWebUri ?? Uri.base;
  if (_uriIsPagamentoPublicPath(uri)) return false;
  if (isAdminWebAppPath(uri)) return false;
  if (AppUrls.isFirebaseAdminAppPreviewHost(uri.host)) return false;
  if (_isPublicCatalogUrl()) return true;
  if (_uriHasLojaPathPriority(uri) ||
      _uriHasExplicitCatalogQueryOrFragment(uri)) {
    return true;
  }
  try {
    final hostNorm = normalizeCatalogDomainHost(uri.host);
    if (hostNorm.isEmpty) return false;
    final lojaId = await resolveLojaIdForPublicCatalogHost(
      uri.host,
      useBrowserCache: true,
    ).timeout(kCatalogDomainResolveBudget, onTimeout: () => null);
    return lojaId != null && lojaId.isNotEmpty;
  } catch (_) {
    return false;
  }
}

bool _isPublicCatalogUrl() {
  if (!kIsWeb) return false;
  final uri = _initialWebUri ?? Uri.base;
  final path = uri.path;

  // Path direto: /loja/slug (garante que abra o catálogo e não o app web)
  if (path.startsWith('/loja/') || path.contains('/loja/')) return true;
  if (uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'loja')
    return true;

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

/// Path `/loja/...` tem prioridade sobre resolução por host customizado.
bool _uriHasLojaPathPriority(Uri uri) {
  final path = uri.path;
  if (path.startsWith('/loja/') || path.contains('/loja/')) return true;
  if (uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'loja') {
    return true;
  }
  return false;
}

/// Query / fragment explícitos de catálogo (legado) — prioridade sobre host mapeado.
bool _uriHasExplicitCatalogQueryOrFragment(Uri uri) {
  if (uri.queryParameters.containsKey('loja') ||
      uri.queryParameters.containsKey('slug') ||
      uri.queryParameters.containsKey('store_id')) {
    return true;
  }
  final frag = uri.fragment.trim();
  return frag.contains('loja/') || frag.startsWith('/loja/');
}

/// Retorno/checkout Mercado Pago no app web (`/pagamento/sucesso`, etc.) — não é catálogo root.
bool _uriIsPagamentoPublicPath(Uri uri) {
  final p = uri.path;
  return p.startsWith('/pagamento') || p.contains('/pagamento/');
}

/// Site institucional (gestao / mastepalm apex): raiz sem admin; catálogo e fluxos MP ficam no build completo.
bool _isPublicMarketingSite() {
  if (!kIsWeb) return false;
  if (_isPublicCatalogUrl()) return false;
  final uri = _initialWebUri ?? Uri.base;
  if (!AppUrls.isPublicMarketingHost(uri.host)) return false;
  final p = uri.path;
  if (p.startsWith('/pedido') || p.startsWith('/pagamento')) return false;
  if (p.startsWith('/c/')) return false;
  final atRoot = p.isEmpty || p == '/';
  if (!atRoot) return false;
  return true;
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

/// Lê o identificador bruto vindo da URL (path, query ou fragment).
/// Quando não há loja explícita, retorna vazio (não usar placeholder como loja real).
String _lojaSlugOrIdFromUrl() {
  if (!kIsWeb) return '';
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

  return '';
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

/// ✅ Lê ID/slug de produto para deep link no catálogo público (`prod`, depois `produto` legado).
String? _produtoRefFromUrl() {
  if (!kIsWeb) return null;
  final uri = _initialWebUri ?? Uri.base;
  final p = (uri.queryParameters['prod'] ?? '').trim();
  if (p.isNotEmpty) {
    logD('📍 [URL] Produto deep link (prod) detectado: $p');
    return p;
  }
  final v = (uri.queryParameters['produto'] ?? '').trim();
  if (v.isNotEmpty) {
    logD('📍 [URL] Produto deep link (produto legado) detectado: $v');
    return v;
  }
  return null;
}

// ===========================================================================
// Catálogo: falha rápida ao resolver domínio próprio (sem MyApp nem ~1min de bootstrap)
// ===========================================================================
class CatalogDomainBootstrapErrorApp extends StatelessWidget {
  final String message;
  const CatalogDomainBootstrapErrorApp({
    super.key,
    this.message =
        'Não foi possível carregar a loja agora. Tente novamente em instantes.',
  });

  @override
  Widget build(BuildContext context) {
    final uri = kIsWeb ? (_initialWebUri ?? Uri.base) : Uri();
    final diag = kIsWeb && uri.queryParameters['diag'] == '1';
    final showLast = diag && uri.queryParameters['showLastError'] == '1';
    final lastErrorRaw =
        showLast ? web_plat.Web.localStorageGet('mp_last_runtime_error') : null;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.store_mall_directory_outlined,
                      size: 64, color: Colors.grey.shade600),
                  const SizedBox(height: 20),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          height: 1.35,
                        ),
                  ),
                  if (diag) ...[
                    const SizedBox(height: 16),
                    SelectableText(
                      'buildId=$kCatalogDiagBuildId\n'
                      'host=${uri.host}\n'
                      'path=${uri.path}\n'
                      'query=${uri.query}\n'
                      'userAgent=${web_plat.Web.userAgent()}\n'
                      'slug=${_lojaSlugOrIdFromUrl()}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (showLast && (lastErrorRaw ?? '').isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SelectableText(
                        'lastError=$lastErrorRaw',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool _shouldForceDiagScreen(Uri uri) {
  if (!kIsWeb) return false;
  if (uri.queryParameters['diag'] != '1') return false;
  return uri.queryParameters['showLastError'] == '1';
}

bool _shouldForceResolveTest(Uri uri) {
  if (!kIsWeb) return false;
  if (uri.queryParameters['diag'] != '1') return false;
  return uri.queryParameters['resolveTest'] == '1';
}

bool _shouldForceNetTest(Uri uri) {
  if (!kIsWeb) return false;
  bool isTruthy(String? value) {
    final v = (value ?? '').trim().toLowerCase();
    return v == '1' || v == 'true' || v == 'yes' || v == 'on';
  }

  return isTruthy(uri.queryParameters['diag']) &&
      isTruthy(uri.queryParameters['netTest']);
}

/// `diag+netTest` / `diag+bootTrace` / `diag+appStartTrace` no Web (evita `setPersistence` e leituras pós-init que quebram o WebKit).
bool _isWebNetTestDiagnosticsQuery(Uri? uri) {
  if (uri == null) return false;
  bool isTruthy(String? value) {
    final v = (value ?? '').trim().toLowerCase();
    return v == '1' || v == 'true' || v == 'yes' || v == 'on';
  }
  if (!isTruthy(uri.queryParameters['diag'])) return false;
  return isTruthy(uri.queryParameters['netTest']) ||
      isTruthy(uri.queryParameters['bootTrace']) ||
      isTruthy(uri.queryParameters['appStartTrace']);
}

Map<String, dynamic> _diagErrorDetails(Object error, StackTrace stack) {
  final out = <String, dynamic>{
    'error.runtimeType': error.runtimeType.toString(),
    'error.toString': error.toString(),
    'stack': stack.toString(),
  };
  if (error is FirebaseException) {
    out['firebaseException.code'] = error.code;
    out['firebaseException.message'] = error.message ?? '';
    out['firebaseException.plugin'] = error.plugin;
  }
  return out;
}

Map<String, dynamic> _netTestFirebaseOptionsRow(FirebaseOptions o) {
  return <String, dynamic>{
    'optionsRuntimeType': o.runtimeType.toString(),
    'hasApiKey': o.apiKey.isNotEmpty,
    'hasAppId': o.appId.isNotEmpty,
    'hasProjectId': o.projectId.isNotEmpty,
    'hasMessagingSenderId': o.messagingSenderId.isNotEmpty,
    'hasAuthDomain': (o.authDomain?.isNotEmpty ?? false),
    'hasStorageBucket': (o.storageBucket?.isNotEmpty ?? false),
    'apiKeyPrefix': o.apiKey.length > 8
        ? '${o.apiKey.substring(0, 8)}…'
        : (o.apiKey.isEmpty ? '(empty)' : '…'),
    'projectId': o.projectId,
    'appIdPrefix': o.appId.length > 12
        ? '${o.appId.substring(0, 12)}…'
        : o.appId,
  };
}

class _CatalogNetTestApp extends StatefulWidget {
  const _CatalogNetTestApp();

  @override
  State<_CatalogNetTestApp> createState() => _CatalogNetTestAppState();
}

class _CatalogNetTestAppState extends State<_CatalogNetTestApp> {
  static const _firebaseInitTimeout = Duration(seconds: 20);

  final List<Map<String, dynamic>> _steps = <Map<String, dynamic>>[];
  bool _running = false;
  bool _netTestComplete = false;
  Object? _runFatal;
  StackTrace? _runFatalStack;
  /// Metadados carregados antes dos passos (fetch /version.json + SW/cache + script).
  Map<String, dynamic> _buildProvenance = <String, dynamic>{};

  String get _slug => _lojaSlugOrIdFromUrl();

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _append(Map<String, dynamic> row) async {
    if (!mounted) return;
    setState(() => _steps.add(row));
    if (!kIsWeb) return;
    try {
      final uri = _initialWebUri ?? Uri.base;
      final payload = <String, dynamic>{
        'buildId': kCatalogDiagBuildId,
        'timestamp': DateTime.now().toIso8601String(),
        'host': uri.host,
        'path': uri.path,
        'query': uri.query,
        'slug': _slug,
        'netTest': _steps,
      };
      web_plat.Web.localStorageSet('mp_catalog_nettest_result', jsonEncode(payload));
      web_plat.Web.localStorageSet('mp_last_runtime_error', jsonEncode(payload));
    } catch (_) {}
  }

  /// Net test: nenhum passo pode interromper os seguintes; timeout no init Firebase
  /// (WebKit pode deixar o `Future` pendente) para sempre chegar aos passos 5–11.
  Future<void> _run() async {
    if (_running) return;
    _running = true;
    final uri = _initialWebUri ?? Uri.base;
    final prov = <String, dynamic>{};

    try {
      // Prova de qual bundle está em memória (Dart define) vs. /version.json na rede
      if (kIsWeb) {
        prov['buildIdFromDartDefine'] = kCatalogDiagBuildId;
        prov['host'] = uri.host;
        prov['path'] = uri.path;
        prov['query'] = uri.query;
        prov['cacheResetDone'] =
            uri.queryParameters['cacheResetDone'] ?? '';
        final origin = uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https')
            ? uri.origin
            : '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
        try {
          final u = Uri.parse('$origin/version.json').replace(
            queryParameters: <String, String>{
              'v': DateTime.now().millisecondsSinceEpoch.toString(),
            },
          );
          prov['versionJsonRequestUrl'] = u.toString();
          final r = await http.get(u).timeout(const Duration(seconds: 20));
          prov['versionJsonHttpStatus'] = r.statusCode;
          if (r.statusCode == 200) {
            final j = jsonDecode(r.body);
            if (j is Map) {
              prov['versionJsonFetchedBuildId'] = j['buildId']?.toString() ?? '';
              prov['versionJsonTimestamp'] = j['timestamp']?.toString();
            } else {
              prov['versionJsonParseNote'] = 'not a map';
            }
          } else {
            prov['versionJsonError'] = 'http_status_${r.statusCode}';
            prov['versionJsonBodyPreview'] = r.body.length > 200
                ? '${r.body.substring(0, 200)}…'
                : r.body;
          }
        } on Object catch (e, st) {
          prov['versionJsonError'] = e.toString();
          prov['versionJsonErrorStack'] = st.toString();
        }
        try {
          prov.addAll(await web_plat.Web.netTestBuildProvenance());
        } on Object catch (e) {
          prov['buildProvenanceNativeError'] = e.toString();
        }
        prov['buildIdMatch'] = (prov['versionJsonFetchedBuildId'] as String? ?? '') ==
            kCatalogDiagBuildId;
      } else {
        prov['buildIdFromDartDefine'] = kCatalogDiagBuildId;
        prov['host'] = uri.host;
        prov['path'] = uri.path;
        prov['query'] = uri.query;
        prov['buildProvenanceNote'] = 'not_web';
        prov['buildIdMatch'] = true;
      }

      // —— 1.build
      try {
        await _append(<String, dynamic>{
          'step': '1.build',
          'buildId': kCatalogDiagBuildId,
        });
      } on Object catch (e, st) {
        await _append(<String, dynamic>{
          'step': '1.build',
          'buildId': kCatalogDiagBuildId,
          'success': false,
          ..._diagErrorDetails(e, st),
        });
      }
      // —— 2.context
      try {
        await _append(<String, dynamic>{
          'step': '2.context',
          'host': uri.host,
          'path': uri.path,
          'query': uri.query,
          'userAgent': web_plat.Web.userAgent(),
        });
      } on Object catch (e, st) {
        await _append(<String, dynamic>{
          'step': '2.context',
          'success': false,
          'host': uri.host,
          'path': uri.path,
          'query': uri.query,
          ..._diagErrorDetails(e, st),
        });
      }
      // —— 3.navigator
      var online = 'unknown';
      try {
        online = web_plat.Web
                .callJs('eval', ['navigator.onLine'])?.toString() ??
            'unknown';
      } on Object {
        online = 'unknown (eval/callJs failed)';
      }
      try {
        await _append(<String, dynamic>{
          'step': '3.navigator',
          'online': online,
        });
      } on Object catch (e, st) {
        await _append(<String, dynamic>{
          'step': '3.navigator',
          'success': false,
          'online': online,
          ..._diagErrorDetails(e, st),
        });
      }

      // Step 4a/4b/4c: Core só — nunca App Check/Auth. `Firebase.apps` sem try após 4a só
      // fora de verificações “há app já?”, para não repetir o crash WebKit.
      var appsCount = 0;
      String? appName;
      var step4bOk = false;
      var step4cOk = false;
      // —— 4a: apenas `DefaultFirebaseOptions.currentPlatform` (leitura; sem `Firebase.initializeApp`)
      try {
        final opts = DefaultFirebaseOptions.currentPlatform;
        await _append(<String, dynamic>{
          'step': '4a.firebase_options_generated',
          'success': true,
          ..._netTestFirebaseOptionsRow(opts),
        });
      } on Object catch (e, st) {
        await _append(<String, dynamic>{
          'step': '4a.firebase_options_generated',
          'success': false,
          ..._diagErrorDetails(e, st),
        });
      }
      // —— 4b: `DefaultFirebaseOptions.currentPlatform` (comportamento clássico; bootstrap usa [firebaseOptionsForInit])
      var step4bError = false;
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        ).timeout(
          _firebaseInitTimeout,
          onTimeout: () {
            throw TimeoutException(
              '4b: Firebase.initializeApp (DefaultFirebaseOptions.currentPlatform) timeout',
              _firebaseInitTimeout,
            );
          },
        );
        try {
          appsCount = Firebase.apps.length;
        } on Object {
          appsCount = 0;
        }
        if (appsCount > 0) {
          try {
            appName = Firebase.apps.first.name;
          } on Object {
            appName = null;
          }
        }
        step4bOk = appsCount > 0;
        await _append(<String, dynamic>{
          'step': '4b.firebase_initialize_generated_options',
          'success': step4bOk,
          'optionsSource': 'DefaultFirebaseOptions.currentPlatform',
          'method': 'Firebase.initializeApp (no auth, no app check)',
          'timeoutCapSeconds': _firebaseInitTimeout.inSeconds,
          'appsCount': appsCount,
          'appName': appName,
        });
      } on Object catch (e, st) {
        step4bError = true;
        try {
          appsCount = Firebase.apps.length;
        } on Object {
          appsCount = 0;
        }
        if (e is FirebaseException && e.code == 'duplicate-app' && appsCount > 0) {
          try {
            appName = Firebase.apps.first.name;
          } on Object {
            appName = null;
          }
          await _append(<String, dynamic>{
            'step': '4b.firebase_initialize_generated_options',
            'success': true,
            'optionsSource': 'DefaultFirebaseOptions.currentPlatform',
            'method': 'Firebase.initializeApp (no auth, no app check)',
            'note': 'duplicate-app',
            'timeoutCapSeconds': _firebaseInitTimeout.inSeconds,
            'appsCount': appsCount,
            'appName': appName,
          });
        } else {
          await _append(<String, dynamic>{
            'step': '4b.firebase_initialize_generated_options',
            'success': false,
            'optionsSource': 'DefaultFirebaseOptions.currentPlatform',
            'method': 'Firebase.initializeApp (no auth, no app check)',
            'timeoutCapSeconds': _firebaseInitTimeout.inSeconds,
            'appsCount': appsCount,
            ..._diagErrorDetails(e, st),
          });
        }
      }
      // —— 4c: opções [FirebaseOptions] idênticas a firebase_options web (só se 4b falhar e ainda sem apps)
      if (step4bError && appsCount == 0) {
        try {
          await Firebase.initializeApp(
            options: kExplicitWebBootstrapFirebaseOptions,
          ).timeout(
            _firebaseInitTimeout,
            onTimeout: () {
              throw TimeoutException(
                '4c: explicit web options timeout',
                _firebaseInitTimeout,
              );
            },
          );
          try {
            appsCount = Firebase.apps.length;
          } on Object {
            appsCount = 0;
          }
          if (appsCount > 0) {
            try {
              appName = Firebase.apps.first.name;
            } on Object {
              appName = null;
            }
          }
          step4cOk = appsCount > 0;
          await _append(<String, dynamic>{
            'step': '4c.firebase_initialize_explicit_web_options',
            'success': step4cOk,
            'optionsSource': 'kExplicitWebBootstrapFirebaseOptions (espelha firebase_options web)',
            'method': 'Firebase.initializeApp (no auth, no app check)',
            'if4bFailedAnd4cSucceeds':
                'possível divergência em DefaultFirebaseOptions.get currentPlatform (improvável na Web: kIsWeb).',
            'timeoutCapSeconds': _firebaseInitTimeout.inSeconds,
            'appsCount': appsCount,
            'appName': appName,
          });
        } on Object catch (e, st) {
          if (e is FirebaseException && e.code == 'duplicate-app') {
            try {
              appsCount = Firebase.apps.length;
            } on Object {
              appsCount = 0;
            }
            if (appsCount > 0) {
              try {
                appName = Firebase.apps.first.name;
              } on Object {
                appName = null;
              }
            }
            await _append(<String, dynamic>{
              'step': '4c.firebase_initialize_explicit_web_options',
              'success': appsCount > 0,
              'optionsSource': 'kExplicitWebBootstrapFirebaseOptions',
              'note': 'duplicate-app',
              'appsCount': appsCount,
              'appName': appName,
            });
          } else {
            try {
              appsCount = Firebase.apps.length;
            } on Object {
              appsCount = 0;
            }
            await _append(<String, dynamic>{
              'step': '4c.firebase_initialize_explicit_web_options',
              'success': false,
              'optionsSource': 'kExplicitWebBootstrapFirebaseOptions',
              ..._diagErrorDetails(e, st),
              'appsCount': appsCount,
            });
          }
        }
      } else if (!step4bOk && appsCount == 0) {
        await _append(<String, dynamic>{
          'step': '4c.firebase_initialize_explicit_web_options',
          'success': false,
          'skipped': true,
          'reason': '4b did not error or appsCount already > 0',
        });
      }

      // —— 5.app_check_token
      if (appsCount == 0) {
        try {
          await _append(<String, dynamic>{
            'step': '5.app_check_token',
            'success': false,
            'skipped': true,
            'reason': 'no_firebase',
          });
        } on Object catch (e, st) {
          await _append(<String, dynamic>{
            'step': '5.app_check_token',
            'success': false,
            'skipped': true,
            'reason': 'no_firebase',
            'appendError': e.toString(),
            'stack': st.toString(),
          });
        }
      } else {
        try {
          final token = await FirebaseAppCheck.instance
              .getToken(false)
              .timeout(const Duration(seconds: 30));
          await _append(<String, dynamic>{
            'step': '5.app_check_token',
            'success': token != null && token.isNotEmpty,
            'tokenLength': token?.length ?? 0,
          });
        } on Object catch (e, st) {
          await _append(<String, dynamic>{
            'step': '5.app_check_token',
            'success': false,
            'interopNote':
                'Safari/embedded WebView: App Check + reCAPTCHA pode lançar TypeError; não implica init Firebase inválido',
            ..._diagErrorDetails(e, st),
          });
        }
      }

      final slug = _slug;
      if (appsCount == 0) {
        for (final key in const <String>['6', '7', '8', '9']) {
          final label = switch (key) {
            '6' => '6.firestore_direct_doc',
            '7' => '7.firestore_slug_query',
            '8' => '8.config_doc',
            '9' => '9.produtos_publicos',
            _ => '9.produtos_publicos',
          };
          try {
            await _append(<String, dynamic>{
              'step': label,
              'success': false,
              'skipped': true,
              'reason': 'no_firebase',
            });
          } on Object catch (e, st) {
            await _append(<String, dynamic>{
              'step': label,
              'success': false,
              'skipped': true,
              'reason': 'no_firebase',
              'appendError': e.toString(),
              'stack': st.toString(),
            });
          }
        }
      } else {
        try {
          final lojas = FirebaseFirestore.instance.collection('lojas');

          try {
            final snap = await lojas.doc(slug).get();
            await _append(<String, dynamic>{
              'step': '6.firestore_direct_doc',
              'path': 'lojas/$slug',
              'success': true,
              'exists': snap.exists,
            });
          } on Object catch (e, st) {
            await _append(<String, dynamic>{
              'step': '6.firestore_direct_doc',
              'path': 'lojas/$slug',
              'success': false,
              ..._diagErrorDetails(e, st),
            });
          }

          try {
            final q = await lojas
                .where('slug', isEqualTo: slug)
                .limit(1)
                .get();
            await _append(<String, dynamic>{
              'step': '7.firestore_slug_query',
              'success': true,
              'count': q.docs.length,
              'firstDocId': q.docs.isNotEmpty ? q.docs.first.id : '',
            });
          } on Object catch (e, st) {
            await _append(<String, dynamic>{
              'step': '7.firestore_slug_query',
              'success': false,
              ..._diagErrorDetails(e, st),
            });
          }

          try {
            final cfg = await lojas
                .doc(slug)
                .collection('config')
                .doc('config')
                .get();
            await _append(<String, dynamic>{
              'step': '8.config_doc',
              'path': 'lojas/$slug/config/config',
              'success': true,
              'exists': cfg.exists,
            });
          } on Object catch (e, st) {
            await _append(<String, dynamic>{
              'step': '8.config_doc',
              'path': 'lojas/$slug/config/config',
              'success': false,
              ..._diagErrorDetails(e, st),
            });
          }

          try {
            final pubRef = lojas.doc(slug).collection('produtos_publicos');
            final liveRef = lojas.doc(slug).collection('produtos');
            var pubCount = 0;
            var liveAtivoCount = 0;
            try {
              pubCount = (await pubRef.count().get()).count ?? 0;
            } on Object {
              final snap = await pubRef.limit(2000).get();
              pubCount = snap.docs.length;
            }
            try {
              liveAtivoCount = (await liveRef
                      .where('ativo', isEqualTo: true)
                      .count()
                      .get())
                  .count ??
                  0;
            } on Object {
              final snap = await liveRef
                  .where('ativo', isEqualTo: true)
                  .limit(2000)
                  .get();
              liveAtivoCount = snap.docs.length;
            }
            await _append(<String, dynamic>{
              'step': '9.produtos_publicos',
              'path': 'lojas/$slug/produtos_publicos',
              'success': true,
              'count': pubCount,
              'note':
                  'Coleção espelho/legada; o catálogo lê `produtos` (ver 9b), não esta.',
            });
            await _append(<String, dynamic>{
              'step': '9b.catalog_produtos',
              'path': 'lojas/$slug/produtos',
              'query': 'ativo==true',
              'success': true,
              'count': liveAtivoCount,
              'note':
                  'Fonte usada por PublicCatalogScreen (kLiveProdutosCol).',
            });
          } on Object catch (e, st) {
            await _append(<String, dynamic>{
              'step': '9.produtos_publicos',
              'path': 'lojas/$slug/produtos_publicos',
              'success': false,
              ..._diagErrorDetails(e, st),
            });
            await _append(<String, dynamic>{
              'step': '9b.catalog_produtos',
              'path': 'lojas/$slug/produtos',
              'success': false,
              ..._diagErrorDetails(e, st),
            });
          }
        } on Object catch (e, st) {
          for (final label in const <String>[
            '6.firestore_direct_doc',
            '7.firestore_slug_query',
            '8.config_doc',
            '9.produtos_publicos',
          ]) {
            await _append(<String, dynamic>{
              'step': label,
              'success': false,
              'skipped': true,
              'reason': 'firestore_bootstrap_error',
              ..._diagErrorDetails(e, st),
            });
          }
        }
      }

      try {
        final swRaw = web_plat.Web.localStorageGet('mp_diag_sw_state') ?? '';
        var controllerExists = '';
        var registrations = '';
        var caches = '';
        var iosswfixRan = '';
        if (swRaw.isNotEmpty) {
          try {
            final decoded = jsonDecode(swRaw);
            if (decoded is Map) {
              controllerExists = (decoded['controller'] ?? '').toString();
              registrations = (decoded['registrations'] ?? '').toString();
              caches = (decoded['caches'] ?? '').toString();
              iosswfixRan = (decoded['iosswfixRan'] ?? '').toString();
            }
          } catch (_) {}
        }
        await _append(<String, dynamic>{
          'step': '10.service_worker_cache',
          'controllerExists': controllerExists,
          'registrations': registrations,
          'caches': caches,
          'iosswfixRan': iosswfixRan,
          'raw': swRaw,
        });
      } on Object catch (e, st) {
        await _append(<String, dynamic>{
          'step': '10.service_worker_cache',
          'success': false,
          ..._diagErrorDetails(e, st),
        });
      }

      try {
        final fetchRaw = web_plat.Web.localStorageGet('mp_fetch_log') ?? '[]';
        await _append(<String, dynamic>{
          'step': '11.fetch_log',
          'raw': fetchRaw,
        });
      } on Object catch (e, st) {
        await _append(<String, dynamic>{
          'step': '11.fetch_log',
          'success': false,
          ..._diagErrorDetails(e, st),
        });
      }
    } on Object catch (e, st) {
      _runFatal = e;
      _runFatalStack = st;
      prov['netTestRunFatalInProvenance'] = e.toString();
      prov['netTestRunFatalStackInProvenance'] = st.toString();
      await _append(<String, dynamic>{
        'step': '0.nettest_fatal',
        'success': false,
        'note': 'caught at outer _run; should be rare (each step has its own try/catch)',
        ..._diagErrorDetails(e, st),
      });
    } finally {
      _buildProvenance = prov;
      if (kIsWeb) {
        try {
          final u = _initialWebUri ?? Uri.base;
          final out = <String, dynamic>{
            'buildId': kCatalogDiagBuildId,
            'buildProvenance': prov,
            'timestamp': DateTime.now().toIso8601String(),
            'host': u.host,
            'path': u.path,
            'query': u.query,
            'slug': _slug,
            'netTest': _steps,
          };
          final raw = jsonEncode(out);
          web_plat.Web.localStorageSet('mp_catalog_nettest_result', raw);
          web_plat.Web.localStorageSet('mp_last_runtime_error', raw);
        } catch (_) {}
      }
      _running = false;
      if (mounted) {
        setState(() {
          _netTestComplete = true;
        });
      } else {
        _netTestComplete = true;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uri = _initialWebUri ?? Uri.base;
    final payload = <String, dynamic>{
      'buildId': kCatalogDiagBuildId,
      'buildProvenance': _buildProvenance,
      'host': uri.host,
      'path': uri.path,
      'query': uri.query,
      'slug': _slug,
      'steps': _steps,
    };
    if (_runFatal != null) {
      payload['netTestOuterFatal'] = {
        'error': _runFatal.toString(),
        'stack': _runFatalStack?.toString() ?? '',
      };
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('Net Test Catálogo (diag)')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _netTestComplete
                ? SelectableText(
                    const JsonEncoder.withIndent('  ').convert(payload),
                  )
                : const Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                      Text(
                        'Executando netTest...',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _CatalogResolveTestApp extends StatelessWidget {
  const _CatalogResolveTestApp();

  @override
  Widget build(BuildContext context) {
    final uri = _initialWebUri ?? Uri.base;
    final slug = _lojaSlugOrIdFromUrl();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('Resolve Test Catálogo')),
        body: FutureBuilder<StoreResolveResult>(
          future: StoreResolverFacade.resolveForPublicCatalog(
            lojaIdFromUrl: slug,
          ),
          builder: (context, snapshot) {
            final payload = <String, dynamic>{
              'buildId': kCatalogDiagBuildId,
              'host': uri.host,
              'path': uri.path,
              'query': uri.query,
              'slug': slug,
            };
            if (snapshot.hasData) {
              final r = snapshot.data!;
              payload.addAll({
                'success': r.success,
                'lojaId': r.canonicalStoreId ?? '',
                'reason': r.failureReason ?? '',
                'resolverStage': r.resolverStage ?? '',
                'resolverAttempt': r.resolverAttempt ?? '',
                'diagnostics': r.diagnostics ?? <String, dynamic>{},
                'error': r.errorMessage ?? '',
              });
              web_plat.Web.localStorageSet(
                'mp_catalog_resolver_result',
                jsonEncode(payload),
              );
              web_plat.Web.localStorageSet(
                'mp_last_runtime_error',
                jsonEncode(payload),
              );
            } else if (snapshot.hasError) {
              payload.addAll({
                'success': false,
                'lojaId': '',
                'reason': 'resolve_test_exception',
                'resolverStage': 'resolveTest.futureBuilder',
                'resolverAttempt':
                    'StoreResolverFacade.resolveForPublicCatalog',
                'error': snapshot.error.toString(),
                'stack': '',
              });
              web_plat.Web.localStorageSet(
                'mp_catalog_resolver_result',
                jsonEncode(payload),
              );
            }
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child:
                    SelectableText(const JsonEncoder.withIndent('  ').convert(
                  payload,
                )),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CatalogDiagnosticApp extends StatelessWidget {
  const _CatalogDiagnosticApp();

  @override
  Widget build(BuildContext context) {
    final uri = _initialWebUri ?? Uri.base;
    final raw = web_plat.Web.localStorageGet('mp_last_runtime_error');
    final resolverRaw =
        web_plat.Web.localStorageGet('mp_catalog_resolver_result');
    String fase = '';
    String error = '';
    String stack = '';
    String slug = _lojaSlugOrIdFromUrl();
    String lojaId = '';
    String reason = '';
    String resolverStage = '';
    String resolverAttempt = '';
    String firestorePath = '';
    String firestoreErrorCode = '';
    String firestoreErrorMessage = '';
    String docExists = '';
    String docId = '';
    String slugField = '';
    String ativo = '';
    String publicado = '';
    String catalogoAtivo = '';
    String status = '';
    final rawValue = (raw ?? '').isNotEmpty ? (raw ?? '') : (resolverRaw ?? '');
    if (rawValue.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawValue);
        if (decoded is Map) {
          fase = (decoded['fase'] ?? '').toString();
          error = (decoded['error'] ?? '').toString();
          stack = (decoded['stack'] ?? '').toString();
          if ((decoded['slug'] ?? '').toString().trim().isNotEmpty) {
            slug = (decoded['slug'] ?? '').toString().trim();
          }
          lojaId = (decoded['lojaId'] ?? '').toString();
          reason = (decoded['reason'] ?? '').toString();
          resolverStage = (decoded['resolverStage'] ?? '').toString();
          resolverAttempt = (decoded['resolverAttempt'] ?? '').toString();
          firestorePath = (decoded['firestorePath'] ?? '').toString();
          firestoreErrorCode = (decoded['firestoreErrorCode'] ?? '').toString();
          firestoreErrorMessage =
              (decoded['firestoreErrorMessage'] ?? '').toString();
          docExists = (decoded['docExists'] ?? '').toString();
          docId = (decoded['docId'] ?? '').toString();
          slugField = (decoded['slugField'] ?? '').toString();
          ativo = (decoded['ativo'] ?? '').toString();
          publicado = (decoded['publicado'] ?? '').toString();
          catalogoAtivo = (decoded['catalogoAtivo'] ?? '').toString();
          status = (decoded['status'] ?? '').toString();
        }
      } catch (_) {}
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('Diagnóstico Catálogo')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              'buildId=$kCatalogDiagBuildId\n'
              'host=${uri.host}\n'
              'path=${uri.path}\n'
              'query=${uri.query}\n'
              'userAgent=${web_plat.Web.userAgent()}\n'
              'slug=$slug\n'
              'lojaId=$lojaId\n'
              'fase=$fase\n'
              'reason=$reason\n'
              'resolverStage=$resolverStage\n'
              'resolverAttempt=$resolverAttempt\n'
              'firestorePath=$firestorePath\n'
              'firestoreErrorCode=$firestoreErrorCode\n'
              'firestoreErrorMessage=$firestoreErrorMessage\n'
              'docExists=$docExists\n'
              'docId=$docId\n'
              'slugField=$slugField\n'
              'ativo=$ativo\n'
              'publicado=$publicado\n'
              'catalogoAtivo=$catalogoAtivo\n'
              'status=$status\n'
              'error=$error\n'
              'stack=$stack\n'
              'mp_last_runtime_error_raw=$rawValue',
            ),
          ),
        ),
      ),
    );
  }
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
      // Rotas mínimas para fallback (ex.: voltar para Home quando abrir por link).
      routes: {
        '/home': (_) => const HomeScreen(),
        '/login': (_) => const LoginScreen(),
      },
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

  Widget _withCatStartDiagOverlay(Widget child) {
    final enabled = kIsWeb && Uri.base.queryParameters['diag'] == '1';
    if (!enabled) return child;
    const trackedEvents = <String>[
      'CAT_START.main.enter',
      'CAT_START.runApp.catalog_web_root.fast_path',
      'CAT_START.first_useful_paint',
      'CAT_START.produtos_stream.first_data',
      'CAT_START.products_grid.first_viewport_frame',
      'CAT_START.catalog_interactive',
    ];
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          right: 8,
          bottom: 8,
          child: IgnorePointer(
            child: ValueListenableBuilder<int>(
              valueListenable: CatalogStartupTrace.revisionListenable,
              builder: (_, __, ___) {
                final events = CatalogStartupTrace.eventsSnapshot();
                final tracked = <Map<String, Object?>>[];
                for (final name in trackedEvents) {
                  int? tMs;
                  for (final e in events) {
                    if (e['event'] == name) tMs = e['t_ms'] as int?;
                  }
                  tracked.add(<String, Object?>{'event': name, 't_ms': tMs});
                }
                final tail = events.reversed.take(6).toList().reversed.toList();
                return Container(
                  width: 360,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.72),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: DefaultTextStyle(
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      height: 1.25,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('CAT_START DIAG (temporário)'),
                        const SizedBox(height: 6),
                        for (final e in tracked)
                          Text(
                            '${e['event']}: ${e['t_ms'] ?? '--'}ms',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        const SizedBox(height: 6),
                        const Text('Últimos eventos:'),
                        for (final e in tail)
                          Text(
                            '- ${e['event']} @ ${e['t_ms']}ms',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final uri = Uri.base;
    final path = uri.path;
    final isCatalogPath = path.startsWith('/loja/') ||
        path.contains('/loja/') ||
        (uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'loja');
    final host = uri.host.toLowerCase();
    // Heurística só para texto da splash (antes do Firestore): domínios dedicados ao catálogo.
    final looksLikeDedicatedCatalogHost =
        host.contains('catalogo.') || host.startsWith('catalogo.');
    final isCatalog =
        kIsWeb && (isCatalogPath || looksLikeDedicatedCatalogHost);
    final splash = _withCatStartDiagOverlay(Scaffold(
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Text(
                isCatalog
                    ? 'Estamos preparando uma experiência incrível para você.'
                    : 'Preparando tudo para você ter a melhor experiência…',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    ));
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      builder: (context, child) {
        if (!kIsWeb) return child ?? const SizedBox.shrink();
        final u = Uri.base;
        if (u.queryParameters['diag'] != '1' ||
            u.queryParameters['appStartTrace'] != '1') {
          return child ?? const SizedBox.shrink();
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: child ?? const SizedBox.shrink()),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                color: Colors.black87,
                child: SafeArea(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ValueListenableBuilder<int>(
                      valueListenable: AppStartTraceCollector.revision,
                      builder: (context, _, __) {
                        return SingleChildScrollView(
                          padding: const EdgeInsets.all(8),
                          child: DefaultTextStyle(
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              height: 1.2,
                              fontFamily: 'monospace',
                            ),
                            child: Text(
                              'buildId=$kCatalogDiagBuildId\n'
                              'host=${Uri.base.host} path=${Uri.base.path} query=${Uri.base.query}\n'
                              'UA=${web_plat.Web.userAgent()}\n'
                              'routeDecision=${_catalogRouteDecisionForInitialWebUri().kind.name}\n'
                              'appStartTrace (Splash = [_BootApp] "Preparando tudo…")\n\n'
                              '${AppStartTraceCollector.dumpText()}',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
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
/// WebKit: aceder a [Firebase.apps] antes de um [Firebase.initializeApp] seguro
/// pode lançar (ex.: *Null check operator used on a null value*). Usar isto no guard.
///
/// *Source map* (build web `npx source-map-cli resolve main.dart.js.map <line> <col>`):
/// `~13026` → [Firebase.apps] (`package:firebase_core/.../firebase.dart`);
/// `~124972` → [FirebaseCoreWeb] (`firebase_core_web` inject script); stack auxiliar
/// a `web_root_boot_trace`/`[ensureFirebaseInitializedOnce]`.
bool _safeFirebaseAppsIsNotEmpty() {
  try {
    return Firebase.apps.isNotEmpty;
  } on Object {
    return false;
  }
}

/// Uma instância de in-flight; duplicar podia disparear dois `initializeApp` em condição de corrida.
Future<bool>? _firebaseCoreInitFuture;

Future<bool> ensureFirebaseInitializedOnce() => _initFirebaseCore();

Future<bool> _initFirebaseCore() async {
  if (_safeFirebaseAppsIsNotEmpty()) {
    if (kDebugMode) {
      debugPrint(
        '[CATALOG_BOOT] firebase.min.ok (already initialized, skip duplicate)',
      );
    }
    return true;
  }
  _firebaseCoreInitFuture ??= _initFirebaseCorePerform();
  try {
    final ok = await _firebaseCoreInitFuture!;
    if (!ok) {
      _firebaseCoreInitFuture = null;
    }
    return ok;
  } catch (e) {
    _firebaseCoreInitFuture = null;
    rethrow;
  }
}

Future<bool> _initFirebaseCorePerform() async {
  final skipAuthPersistence = kIsWeb &&
      _isWebNetTestDiagnosticsQuery(_initialWebUri ?? Uri.base);
  CatalogStartupTrace.spanStart('CAT_START.firebase_init');
  logD('➡️ Firebase.initializeApp...');
  boot.mark('firebase.init.begin');
  try {
    await Firebase.initializeApp(
      options: firebaseOptionsForInit(),
    ).timeout(const Duration(seconds: 15));

    // Web: manter usuário logado; em `diag&netTest` / `diag&bootTrace` pula (WebKit: `setPersistence` pode
    // lançar "Null check" em interop) — o netTest chama `Firebase.initializeApp` isolado.
    if (kIsWeb && !skipAuthPersistence && _safeFirebaseAppsIsNotEmpty()) {
      try {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
        logD('🔐 [BOOT] Auth persistência LOCAL (permanece logado até Sair)');
      } catch (e, st) {
        logD('⚠️ [BOOT] setPersistence: $e  $st');
      }
    } else if (kIsWeb && skipAuthPersistence) {
      logD('ℹ️ [BOOT] setPersistence omitido (modo netTest/diag no Web).');
    }

    boot.mark('firebase.init.ok');
    CatalogStartupTrace.spanEnd('CAT_START.firebase_init', data: {'ok': true});
    logD('✅ Firebase inicializado');
    return true;
  } on TimeoutException catch (e) {
    logD('! Firebase.initializeApp demorou demais (type=${e.runtimeType})');
    boot.mark('firebase.init.timeout', e);
    logD(
        '! Não foi possível inicializar o Firebase. Continuando em modo OFFLINE.');
    boot.mark('firebase.init.offline', e);
    CatalogStartupTrace.spanEnd('CAT_START.firebase_init',
        data: {'ok': false, 'timeout': true});
    unawaited(_logCatalogRuntimeError(
      fase: 'firebaseInit',
      error: e,
      stack: StackTrace.current,
    ));
    return false;
  } on FirebaseException catch (e) {
    if (e.code == 'duplicate-app' && _safeFirebaseAppsIsNotEmpty()) {
      logD(
          'ℹ️ Firebase já estava inicializado (duplicate-app). Usando instância existente.');
      boot.mark('firebase.init.duplicate');
      CatalogStartupTrace.spanEnd('CAT_START.firebase_init',
          data: {'ok': true, 'duplicate': true});
      return true;
    } else {
      boot.mark('firebase.init.fail', e);
      CatalogStartupTrace.spanEnd('CAT_START.firebase_init',
          data: {'ok': false, 'error_type': e.runtimeType.toString()});
      unawaited(_logCatalogRuntimeError(
        fase: 'firebaseInit',
        error: e,
        stack: StackTrace.current,
      ));
      rethrow;
    }
  } catch (e, st) {
    // Tudo que não for Timeout / Firebase (ex.: null check / TypeError do JS, Auth interop)
    logD('! Firebase init genérico (type=${e.runtimeType}): $e  $st');
    boot.mark('firebase.init.unexpected', e);
    CatalogStartupTrace.spanEnd(
      'CAT_START.firebase_init',
      data: {
        'ok': false,
        'error_type': e.runtimeType.toString(),
        'unhandled': true,
      },
    );
    unawaited(
      _logCatalogRuntimeError(
        fase: 'firebaseInit',
        error: e,
        stack: st,
      ),
    );
    return false;
  }
}

void _debugLogPublicCatalogBootChoice(Uri uriWeb) {
  if (!kIsWeb || !kDebugMode) return;
  final isDefaultHost = AppUrls.isDefaultMasterPalmCatalogHost(uriWeb.host);
  final isCatPath =
      _uriHasLojaPathPriority(uriWeb) && !_uriIsPagamentoPublicPath(uriWeb);
  final isCustomCand = _shouldOfferCustomDomainCatalogFastPath(uriWeb);
  var selectedBootMode = 'admin_or_full_bootstrap';
  if (isCatPath || isCustomCand) {
    selectedBootMode = 'public_catalog_fastpath';
  }
  debugPrint('[BOOT] currentUri $uriWeb');
  debugPrint('[BOOT] host ${uriWeb.host}');
  debugPrint('[BOOT] path ${uriWeb.path}');
  debugPrint('[BOOT] isDefaultMasterPalmCatalogHost $isDefaultHost');
  debugPrint('[BOOT] isCatalogPath $isCatPath');
  debugPrint('[BOOT] isCustomCatalogDomainCandidate $isCustomCand');
  debugPrint('[BOOT] selectedBootMode $selectedBootMode');
}

// ===========================================================================
// ▶️ MAIN
// ===========================================================================
Future<void> main() async {
  CatalogStartupTrace.mark('CAT_START.main.enter');
  await runWithGlobalErrorHook(() async {
    WidgetsFlutterBinding.ensureInitialized();
    BootPerfLog.resetBoot();
    _installUltraEarlyCatalogErrorCapture();
    CatalogStartupTrace.mark('CAT_START.flutter_binding.ready');

    // Web: usar path na URL (/loja/slug) em vez de hash (#/loja/slug) para o lojaId ser lido corretamente
    if (kIsWeb) {
      url_strategy.usePathUrlStrategy();
      // Captura URL inicial para decisão catálogo vs app (evita redirect durante bootstrap)
      final initialUri = Uri.base;
      _initialWebUri = initialUri;
      if (initialUri.queryParameters['diag'] == '1' &&
          initialUri.queryParameters['appStartTrace'] == '1') {
        AppStartTraceCollector.clear();
        AppStartTraceCollector.mark('main.enter', detail: initialUri.toString());
      }

      // GATE ABSOLUTO (antes de qualquer bootstrap/fallback do catálogo):
      // ?diag=1&netTest=1 deve sempre abrir diagnóstico técnico e retornar.
      if (_shouldForceNetTest(initialUri)) {
        runApp(const _CatalogNetTestApp());
        return;
      }

      web_plat.Web.localStorageSet('mp_catalog_build_id', kCatalogDiagBuildId);
      _setCatalogPhase('main.start');
      logD('🌐 [MAIN] URL inicial (para catálogo): ${_initialWebUri?.path}');
      // Não inicializar Google Sign-In aqui: evita redirecionar para Google antes
      // de exibir a tela de login. O init é feito na LoginScreen quando o usuário vê as opções.
      if (_shouldForceDiagScreen(initialUri)) {
        runApp(const _CatalogDiagnosticApp());
        return;
      }
      if (_shouldForceResolveTest(initialUri)) {
        runApp(const _CatalogResolveTestApp());
        return;
      }

      // bootTrace+diag: raiz do **web app** (Safari/Chrome/WebView no iPhone = mesmo Flutter Web;
      // não há APK nativo iOS neste fluxo). Não monta PublicCatalogScreen (ver [WebRootBootTraceApp]).
      if (initialUri.queryParameters['bootTrace'] == '1' &&
          initialUri.queryParameters['diag'] == '1') {
        final d = _catalogRouteDecisionForInitialWebUri();
        if (d.kind == CatalogInitialRouteKind.appRoot) {
          final isPublicCat = _uriHasLojaPathPriority(initialUri) &&
              !_uriIsPagamentoPublicPath(initialUri);
          runApp(
            WebRootBootTraceApp(
              buildId: kCatalogDiagBuildId,
              initialUri: initialUri,
              routeDecision: d,
              isPublicCatalogPath: isPublicCat,
              isAppHost:
                  AppUrls.isDefaultMasterPalmCatalogHost(initialUri.host),
              initFirebase: ensureFirebaseInitializedOnce,
              onContinue: () {
                runApp(const _BootApp());
              },
            ),
          );
          return;
        }
      }
    }

    logD('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    logD('🚀 [MAIN] Iniciando MasterPalm');
    logD('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    // FAST PATH CIRÚRGICO: catálogo público via /loja/* e domínio próprio (incl. iPhone Web na vitrine).
    //
    // [AppUrls.isDefaultMasterPalmCatalogHost] = app + firebase hosting, **não** é domínio de loja.
    // A raiz `/` nunca deve renderizar [CatalogDomainBootstrapErrorApp] (só domínio próprio sem mapeamento).
    // Catálogo no host do app: apenas `/loja/{slug}` ou query/fragment legado explícito (`?loja=`, etc.).
    //
    // Catálogo público não deve passar pelo bootstrap pesado do app antes do primeiro frame.
    // Isso causa tela branca. Renderizar loader imediatamente; não chamar `_bootstrapSafe` aqui
    // (Hive, sessão, RemoteConfig, AppCheck pesado só no app administrativo).
    if (kIsWeb) {
      final uriWeb = _initialWebUri ?? Uri.base;
      _setCatalogPhase('route.detected');
      _debugLogPublicCatalogBootChoice(uriWeb);
      if (kDebugMode) {
        final atRoot = uriWeb.path.isEmpty || uriWeb.path == '/';
        if (AppUrls.isDefaultMasterPalmCatalogHost(uriWeb.host) &&
            atRoot &&
            !_uriHasLojaPathPriority(uriWeb) &&
            !_uriHasExplicitCatalogQueryOrFragment(uriWeb) &&
            !_uriIsPagamentoPublicPath(uriWeb)) {
          final cd = _catalogRouteDecisionForInitialWebUri();
          assert(
            cd.kind == CatalogInitialRouteKind.appRoot,
            'ROUTEGUARD: host do app na raiz deve ser appRoot, nunca ${cd.kind}',
          );
        }
      }
      // Raiz de app.mastepalm.com.br/ → fluxo normal ([_BootApp]/MyApp), nunca erro de catálogo aqui.

      final isPublicCatalogPath =
          _uriHasLojaPathPriority(uriWeb) && !_uriIsPagamentoPublicPath(uriWeb);
      if (isPublicCatalogPath) {
        final routeDecision = _catalogRouteDecisionForInitialWebUri();
        if (routeDecision.kind == CatalogInitialRouteKind.lojaPathOrSlugInvalid ||
            routeDecision.kind == CatalogInitialRouteKind.legacyQueryInvalid) {
          _setCatalogPhase('route.loja_path.invalid');
          runApp(InvalidPublicLojaPathApp(
            uri: uriWeb,
            buildId: kCatalogDiagBuildId,
          ));
          return;
        }
        if (routeDecision.kind == CatalogInitialRouteKind.publicCatalogByLojaPath) {
          _setCatalogPhase('catalog.slug.extracted');
          final lojaSlugOrId = routeDecision.extractedSlugOrId?.isNotEmpty == true
              ? routeDecision.extractedSlugOrId!
              : _lojaSlugOrIdFromUrl();
          _logWebCatalogDiag(
            source: 'fast_path.loja_path.enter',
            slugOrId: lojaSlugOrId,
            resolvedLojaId: lojaSlugOrId,
          );
          final vendedorRef = _vendedorRefFromUrl();
          final indicacaoRef = _indicacaoRefFromUrl();
          final produtoRef = _produtoRefFromUrl();
          CatalogStartupTrace.mark(
              'CAT_START.runApp.catalog_bootstrap_gate.loja_path');
          runApp(PublicCatalogBootstrapApp(
            firebaseSpanName: 'CAT_START.fast_path.firebase_min_init',
            initFirebase: ensureFirebaseInitializedOnce,
            afterFirebaseMinReady: ({
              required void Function(String? nomeLoja) updateNomeLoja,
              required void Function(String? logoUrl) updateLogoUrl,
            }) async {
              _setCatalogPhase('catalog.loja.load.start');
              // /loja/{id}: nome costuma vir depois no stream de config; mantemos fallback leve aqui.
              updateNomeLoja(null);
              updateLogoUrl(null);
              StoreResolverFacade.seedPublicCatalogResolveFromBootstrap(
                urlSlugOrId: lojaSlugOrId,
                resolvedCanonicalStoreId: lojaSlugOrId,
              );
              _logWebCatalogDiag(
                source: 'fast_path.loja_path.seeded',
                slugOrId: lojaSlugOrId,
                resolvedLojaId: lojaSlugOrId,
              );
              CatalogStartupTrace.mark(
                  'CAT_START.fast_path.public_resolver_seeded',
                  data: {'loja_slug_or_id': lojaSlugOrId},
              );
              CatalogStartupTrace.mark(
                  'CAT_START.runApp.catalog_web_root.fast_path',
                  data: {
                    'loja_slug_or_id': lojaSlugOrId,
                  },
              );
              if (kDebugMode) {
                debugPrint('[CATALOG_BOOT] catalog.root.render');
              }
              _setCatalogPhase('catalog.loja.load.done');
              _setCatalogPhase('publicCatalogScreen.render');
              runApp(CatalogWebRoot(
                lojaId: lojaSlugOrId,
                vendedorRef: vendedorRef,
                indicacaoRef: indicacaoRef,
                produtoRef: produtoRef,
              ));
            },
          ));
          return;
        }
        logW(
          '⚠️ [MAIN] Rota /loja/* inesperada (${routeDecision.kind}) — sem fast path de catálogo',
        );
      }

      // FAST PATH: domínio próprio (host mapeado em catalog_domains).
      if (_shouldOfferCustomDomainCatalogFastPath(uriWeb)) {
        final hostNorm = normalizeCatalogDomainHost(uriWeb.host);
        final cached = CatalogDomainBrowserCache.read(hostNorm);
        final cachedNomeLoja = sanitizePublicStoreName(cached?.nomeLoja);
        final cachedLogoUrl = sanitizePublicStoreLogoUrl(cached?.logoUrl);
        CatalogStartupTrace.mark(
            'CAT_START.runApp.catalog_bootstrap_gate.custom_domain');
        runApp(PublicCatalogBootstrapApp(
          firebaseSpanName: 'CAT_START.custom_domain.fast_path.firebase',
          initFirebase: ensureFirebaseInitializedOnce,
          initialNomeLoja: cachedNomeLoja,
          initialLogoUrl: cachedLogoUrl,
          afterFirebaseMinReady: ({
            required void Function(String? nomeLoja) updateNomeLoja,
            required void Function(String? logoUrl) updateLogoUrl,
          }) async {
            _setCatalogPhase('catalog.domain.resolve.start');
            if (kDebugMode) {
              debugPrint('[CATALOG_BOOT] domain.resolve.begin');
            }
            CatalogStartupTrace.spanStart('CAT_START.custom_domain.fast_path');
            CatalogDomainFirestoreHit? domainHit;
            try {
              domainHit = await resolveCatalogDomainHitForPublicCatalogHost(
                uriWeb.host,
                useBrowserCache: true,
              ).timeout(
                kCatalogDomainResolveBudget,
                onTimeout: () => null,
              );
            } catch (e, st) {
              logW(
                '⚠️ [MAIN] Resolução domínio próprio (fast path) falhou (type=${e.runtimeType})',
              );
              unawaited(_logCatalogRuntimeError(
                fase: 'domainResolver',
                error: e,
                stack: st,
              ));
            }

            final nomeLoja = (domainHit?.nomeLoja ?? '').trim();
            if (nomeLoja.isNotEmpty) {
              updateNomeLoja(nomeLoja);
            }
            final logoUrl = sanitizePublicStoreLogoUrl(domainHit?.logoUrl);
            if (logoUrl != null) {
              updateLogoUrl(logoUrl);
            }
            final fromMappedHost = (domainHit?.lojaId ?? '').trim();
            _setCatalogPhase('catalog.domain.resolve.done');
            if (fromMappedHost.isNotEmpty) {
              String lojaIdResolvido = fromMappedHost;
              try {
                lojaIdResolvido =
                    await _fastResolveStoreIdFromDomainIndex(fromMappedHost);
              } catch (e, st) {
                logW(
                    '⚠️ [MAIN] Resolver lojaId (domínio fast path) falhou (type=${e.runtimeType})');
                unawaited(_logCatalogRuntimeError(
                  fase: 'lojaLoad',
                  error: e,
                  stack: st,
                  slug: fromMappedHost,
                ));
              }
              StoreResolverFacade.seedPublicCatalogResolveFromBootstrap(
                urlSlugOrId: fromMappedHost,
                resolvedCanonicalStoreId: lojaIdResolvido,
              );
              _logWebCatalogDiag(
                source: 'fast_path.custom_domain.seeded',
                slugOrId: fromMappedHost,
                resolvedLojaId: lojaIdResolvido,
              );
              final vendedorRef = _vendedorRefFromUrl();
              final indicacaoRef = _indicacaoRefFromUrl();
              final produtoRef = _produtoRefFromUrl();
              logD(
                  '🌐 [MAIN] Public Catalog FAST domínio próprio host=$hostNorm → $lojaIdResolvido');
              if (kDebugMode) {
                debugPrint('[CATALOG_BOOT] domain.resolve.ok');
              }
              CatalogStartupTrace.spanEnd(
                'CAT_START.custom_domain.fast_path',
                data: {
                  'ok': true,
                  'host': hostNorm,
                  'loja_id': lojaIdResolvido,
                },
              );
              CatalogStartupTrace.mark(
                'CAT_START.runApp.catalog_web_root.custom_domain_fast',
                data: {'host': hostNorm, 'loja_id': lojaIdResolvido},
              );
              if (kDebugMode) {
                debugPrint('[CATALOG_BOOT] catalog.root.render');
              }
              _setCatalogPhase('catalog.loja.load.done');
              _setCatalogPhase('publicCatalogScreen.render');
              runApp(CatalogWebRoot(
                lojaId: lojaIdResolvido,
                vendedorRef: vendedorRef,
                indicacaoRef: indicacaoRef,
                produtoRef: produtoRef,
              ));
              return;
            }

            CatalogStartupTrace.spanEnd(
              'CAT_START.custom_domain.fast_path',
              data: {'ok': false, 'reason': 'no_mapping'},
            );
            logD(
                '🌐 [MAIN] Domínio próprio sem mapeamento ativo (fast path) host=$hostNorm → tela amigável');
            CatalogStartupTrace.mark(
                'CAT_START.runApp.catalog_domain_resolve_error');
            runApp(const CatalogDomainBootstrapErrorApp());
          },
        ));
        return;
      }
    }

    CatalogStartupTrace.mark('CAT_START.runApp.boot_app');
    runApp(const _BootApp());

    try {
      logD('🟦 [MAIN] Chamando _bootstrapSafe()...');
      CatalogStartupTrace.spanStart('CAT_START.bootstrap_safe');
      await _bootstrapSafe();
      CatalogStartupTrace.spanEnd('CAT_START.bootstrap_safe');
      _appStartMark('post_bootstrap.after_await_bootstrap');
      logD('🟩 [MAIN] _bootstrapSafe() concluído com sucesso');

      try {
        final lojaViaLojaService = await LojaIdService.get();
        logD('🟪 [MAIN] Loja via LojaIdService.get() → $lojaViaLojaService');
      } catch (e) {
        logD(
            '🟥 [MAIN] Erro ao obter loja via LojaIdService.get() (type=${e.runtimeType})');
      }

      if (kIsWeb) {
        final uri = Uri.base;
        if (uri.path == '/mp-oauth-callback') {
          logD('🌐 [MAIN] Callback OAuth MP detectado em /mp-oauth-callback');
          CatalogStartupTrace.mark('CAT_START.runApp.mp_oauth_callback');
          runApp(MpOAuthCallbackScreen(uri: uri));
          return;
        }
        final mpOAuth = uri.queryParameters['mp_oauth'];
        if (mpOAuth == 'ok' || mpOAuth == 'error') {
          logD('🌐 [MAIN] Redirect OAuth MP detectado: $mpOAuth');
          CatalogStartupTrace.mark('CAT_START.runApp.mp_oauth_result');
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
        final uriWeb = _initialWebUri ?? Uri.base;
        _setCatalogPhase('route.detected');
        if (_uriIsPagamentoPublicPath(uriWeb)) {
          logD(
              '🌐 [MAIN] Path /pagamento/* → MyApp (fluxo MP; não CatalogWebRoot)');
          CatalogStartupTrace.mark('CAT_START.runApp.my_app.pagamento_path');
          runApp(const MyApp());
          registerWebPopStateLogger();
          return;
        }
        final isCat = _isPublicCatalogUrl();
        logD('🌐 [MAIN] _isPublicCatalogUrl() → $isCat');

        if (isCat) {
          final routePre = _catalogRouteDecisionForInitialWebUri();
          if (routePre.kind == CatalogInitialRouteKind.lojaPathOrSlugInvalid ||
              routePre.kind == CatalogInitialRouteKind.legacyQueryInvalid) {
            runApp(InvalidPublicLojaPathApp(
              uri: uriWeb,
              buildId: kCatalogDiagBuildId,
            ));
            return;
          }
          _setCatalogPhase('catalog.slug.extracted');
          final slugOuId = _lojaSlugOrIdFromUrl();
          _setCatalogPhase('catalog.loja.load.start');
          String lojaIdResolvido = slugOuId;
          try {
            lojaIdResolvido = await _resolveSlugToStoreIdIfNeeded(slugOuId);
          } catch (e) {
            logW(
                '⚠️ [MAIN] Resolver slug falhou, usando slug da URL (type=${e.runtimeType})');
          }
          StoreResolverFacade.seedPublicCatalogResolveFromBootstrap(
            urlSlugOrId: slugOuId,
            resolvedCanonicalStoreId: lojaIdResolvido,
          );
          final vendedorRef = _vendedorRefFromUrl();
          final indicacaoRef = _indicacaoRefFromUrl();
          final produtoRef = _produtoRefFromUrl();

          logD('🌐 [MAIN] Public Catalog slug/id resolvido');
          CatalogStartupTrace.mark('CAT_START.runApp.catalog_web_root');
          _setCatalogPhase('catalog.loja.load.done');
          _setCatalogPhase('publicCatalogScreen.render');
          runApp(CatalogWebRoot(
            lojaId: lojaIdResolvido,
            vendedorRef: vendedorRef,
            indicacaoRef: indicacaoRef,
            produtoRef: produtoRef,
          ));
        } else if (!isCat &&
            AppUrls.isDefaultMasterPalmCatalogHost(uriWeb.host) &&
            !_uriHasLojaPathPriority(uriWeb) &&
            !_uriHasExplicitCatalogQueryOrFragment(uriWeb)) {
          // Host do SPA (app / firebase web) na raiz: **não** bloquear em catalog_domains/Firestore
          // (WebKit podia pendurar o await e deixar a splash "Preparando tudo…" para sempre).
          _appStartMark('web.route',
              detail: 'app_host_root_skip_catalog_domains',
              finalDecision: 'my_app');
          logD(
            '🌐 [MAIN] Host admin canónico na raiz (sem /loja) → MyApp sem catalog_domains',
          );
          CatalogStartupTrace.mark('CAT_START.runApp.my_app.app_host_root');
          runApp(const MyApp());
          registerWebPopStateLogger();
          return;
        } else if (!_uriHasLojaPathPriority(uriWeb) &&
            !_uriHasExplicitCatalogQueryOrFragment(uriWeb) &&
            !isAdminWebAppPath(uriWeb) &&
            !AppUrls.isFirebaseAdminAppPreviewHost(uriWeb.host) &&
            _safeFirebaseAppsIsNotEmpty()) {
          final hostNorm = normalizeCatalogDomainHost(uriWeb.host);
          _setCatalogPhase('catalog.domain.resolve.start');
          final fromMappedHost = await resolveLojaIdForPublicCatalogHost(
            uriWeb.host,
            useBrowserCache: true,
          ).timeout(kCatalogDomainResolveBudget, onTimeout: () => null);
          if (fromMappedHost != null && fromMappedHost.isNotEmpty) {
            _setCatalogPhase('catalog.domain.resolve.done');
            String lojaIdResolvido = fromMappedHost;
            try {
              lojaIdResolvido =
                  await _fastResolveStoreIdFromDomainIndex(fromMappedHost);
            } catch (e) {
              logW(
                  '⚠️ [MAIN] Resolver lojaId (domínio mapeado) falhou (type=${e.runtimeType})');
            }
            StoreResolverFacade.seedPublicCatalogResolveFromBootstrap(
              urlSlugOrId: fromMappedHost,
              resolvedCanonicalStoreId: lojaIdResolvido,
            );
            final vendedorRef = _vendedorRefFromUrl();
            final indicacaoRef = _indicacaoRefFromUrl();
            final produtoRef = _produtoRefFromUrl();
            logD(
                '🌐 [MAIN] Public Catalog via catalog_domains host=$hostNorm → $lojaIdResolvido');
            CatalogStartupTrace.mark(
                'CAT_START.runApp.catalog_web_root.domain_map');
            _setCatalogPhase('catalog.loja.load.done');
            _setCatalogPhase('publicCatalogScreen.render');
            runApp(CatalogWebRoot(
              lojaId: lojaIdResolvido,
              vendedorRef: vendedorRef,
              indicacaoRef: indicacaoRef,
              produtoRef: produtoRef,
            ));
          } else if (_isPublicMarketingSite()) {
            logD(
                '🌐 [MAIN] Host site público → PublicMarketingWebApp (sem AppWeb admin na raiz)');
            CatalogStartupTrace.mark('CAT_START.runApp.marketing_web_app');
            runApp(const PublicMarketingWebApp());
          } else {
            logD('🌐 [MAIN] Web padrão → iniciando MyApp()');
            CatalogStartupTrace.mark('CAT_START.runApp.my_app.web_default');
            _appStartMark('runapp.my_app', detail: 'web_default_inner');
            runApp(const MyApp());
            registerWebPopStateLogger();
          }
        } else if (_isPublicMarketingSite()) {
          logD(
              '🌐 [MAIN] Host site público → PublicMarketingWebApp (sem AppWeb admin na raiz)');
          CatalogStartupTrace.mark('CAT_START.runApp.marketing_web_app');
          runApp(const PublicMarketingWebApp());
        } else {
          logD('🌐 [MAIN] Web padrão → iniciando MyApp()');
          CatalogStartupTrace.mark('CAT_START.runApp.my_app.web_default');
          _appStartMark('runapp.my_app', detail: 'web_default_outer');
          runApp(const MyApp());
          registerWebPopStateLogger();
        }
      } else {
        logD('📱 [MAIN] Rodando em Mobile/Desktop → iniciando MyApp()');
        CatalogStartupTrace.mark('CAT_START.runApp.my_app.native');
        runApp(const MyApp());
      }
    } catch (e, st) {
      logE('❌ Bootstrap ERROR (type=${e.runtimeType})', error: e, st: st);
      if (_isAppStartTraceQuery()) {
        AppStartTraceCollector.persistError('main.bootstrap', e, st);
        AppStartTraceCollector.mark('bootstrap.ERROR', detail: e.toString());
      }
      _logWebCatalogDiag(source: 'main.bootstrap.error');
      unawaited(_logCatalogRuntimeError(
        fase: 'render',
        error: e,
        stack: st,
      ));
      CatalogStartupTrace.mark('CAT_START.runApp.boot_error',
          data: {'error_type': e.runtimeType.toString()});
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

    for (final name in [
      'estoque',
      'catalogo',
      'config_catalogo',
      'categorias'
    ]) {
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
// HIVE: adapters ERP (sincronamente pesado — centenas de registros no isolate)
// ===========================================================================

void _registerAllHiveAdaptersBootstrap() {
  if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ClienteAdapter());
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
  if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
  if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(FornecedorAdapter());
  if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(UsuarioAdapter());
  if (!Hive.isAdapterRegistered(5))
    Hive.registerAdapter(ProdutoCatalogoAdapter());
  if (!Hive.isAdapterRegistered(6))
    Hive.registerAdapter(CatalogoConfigAdapter());
  if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(VendaItemAdapter());
  if (!Hive.isAdapterRegistered(8))
    Hive.registerAdapter(FechamentoMensalAdapter());
  if (!Hive.isAdapterRegistered(13))
    Hive.registerAdapter(SubcategoriaAdapter());
  if (!Hive.isAdapterRegistered(14)) Hive.registerAdapter(CupomPremioAdapter());
  if (!Hive.isAdapterRegistered(15))
    Hive.registerAdapter(MasterConfigAdapter());
  if (!Hive.isAdapterRegistered(16)) Hive.registerAdapter(MetaAdapter());
  if (!Hive.isAdapterRegistered(17)) Hive.registerAdapter(CategoriaAdapter());
  if (!Hive.isAdapterRegistered(18)) Hive.registerAdapter(EstoqueItemAdapter());
  if (!Hive.isAdapterRegistered(25))
    Hive.registerAdapter(ComissaoConfigAdapter());
  if (!Hive.isAdapterRegistered(26))
    Hive.registerAdapter(ComissaoVendedorAdapter());
  if (!Hive.isAdapterRegistered(27))
    Hive.registerAdapter(VendaTrackingAdapter());
  if (!Hive.isAdapterRegistered(28))
    Hive.registerAdapter(ComissaoVendaAdapter());
  if (!Hive.isAdapterRegistered(10)) Hive.registerAdapter(NotaFiscalAdapter());
  if (!Hive.isAdapterRegistered(11))
    Hive.registerAdapter(NotaFiscalItemAdapter());
  if (!Hive.isAdapterRegistered(29))
    Hive.registerAdapter(ContaReceberAdapter());
  if (!Hive.isAdapterRegistered(30))
    Hive.registerAdapter(LancamentoFinanceiroAdapter());
  if (!Hive.isAdapterRegistered(31))
    Hive.registerAdapter(GastoFixoMensalAdapter());
  if (!Hive.isAdapterRegistered(32))
    Hive.registerAdapter(CompraFornecedorAdapter());
  if (!Hive.isAdapterRegistered(33))
    Hive.registerAdapter(CompraFornecedorItemAdapter());
  if (!Hive.isAdapterRegistered(34))
    Hive.registerAdapter(CompraItemPipelineAdapter());
  if (!Hive.isAdapterRegistered(35))
    Hive.registerAdapter(ContaPagarAdapter());
}

/// Catálogo web: não bloquear [main] com dezenas de [registerAdapter] síncronos
/// antes do 2º [runApp(CatalogWebRoot)] — agenda após o próximo event loop.
Future<void> _registerHiveAdaptersBootstrapDeferred() async {
  await Future<void>.delayed(Duration.zero);
  _registerAllHiveAdaptersBootstrap();
  boot.mark('hive.adapters.ok');
}

Future<Box<dynamic>> _hiveOpenTracked(String name) async {
  _appStartMark('hive.open.begin', detail: name);
  try {
    final b = await Hive.openBox(name).timeout(_kHiveOpenBudget);
    _appStartMark('hive.open.ok', detail: name);
    return b;
  } on TimeoutException catch (_) {
    _appStartMark('hive.open.TIMEOUT', detail: name);
    rethrow;
  }
}

// ===========================================================================
// 🧰 BOOTSTRAP
// ===========================================================================
Future<void> _bootstrapSafe() async {
  _appStartMark('bootstrap.enter');
  BootPerfLog.markBoot('bootstrap.enter');
  logD('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  logD('[BOOT-ROUTER] Iniciando _bootstrapSafe()');
  logD('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  boot.mark('intl.start');
  Intl.defaultLocale = 'pt_BR';
  // Carregar padrões de data pt_BR em background: no Web o asset é grande e atrasa
  // o primeiro frame (login/splash) se aguardar aqui.
  unawaited(
    initializeDateFormatting('pt_BR').then((_) {
      boot.mark('intl.ok');
      logD('🟢 [BOOT] Intl date symbols pt_BR carregados (deferred)');
    }).catchError((Object e, StackTrace st) {
      boot.mark('intl.fail', e);
      logW('⚠️ [BOOT] initializeDateFormatting falhou (type=${e.runtimeType})');
      if (kDebugMode) logD('$st');
    }),
  );
  logD('🟢 [BOOT] Intl defaultLocale=pt_BR (date symbols em background)');

  BootPerfLog.markBoot('firebase_init_start');
  final firebaseOk = await _initFirebaseCore();
  BootPerfLog.markBoot('firebase_init_end', detail: 'ok=$firebaseOk');
  _appStartMark('firebase.done', detail: 'ok=$firebaseOk');
  logD('[BOOT-AUTH] firebaseOk=$firebaseOk');

  final webCatalogMinimalBoot = kIsWeb &&
      firebaseOk &&
      await _webShouldMinimalBootstrapForPublicCatalogViewer();
  if (webCatalogMinimalBoot) {
    logD(
      '[BOOT-CATALOG-WEB] Catálogo público na web → bootstrap mínimo (sem aguardar auth longa nem RemoteConfig/AppCheck antes do catálogo)',
    );
  }

  if (firebaseOk && kIsWeb && kDebugMode) {
    logD(
      'ℹ️ [WEB] OAuth: em Authentication → Settings → Authorized domains, inclua '
      'App Web canônico: ${AppUrls.appWebHostCanonical}; legado: ${AppUrls.appWebHostLegacyTypo} (ver docs/DOMAIN_APP_WEB.md e SETUP_FIREBASE_WEB.md)',
    );
  }

  // ⚡ FAST PATH (web + mobile): sem usuário → bootstrap mínimo para login
  // Web: aguardar auth restaurar (currentUser pode ser null temporariamente)
  bool hasUser = false;
  if (firebaseOk) {
    var u = FirebaseAuth.instance.currentUser;
    if (!webCatalogMinimalBoot && u == null && kIsWeb) {
      // Sessão persistida costuma aparecer no 1º evento; visitante sem login nunca
      // recebe usuário não-anônimo — não pode esperar 5s (atrasava muito o 1º acesso).
      logD(
          '🟡 [BOOT] Web: currentUser null, aguardando restauração auth (até 2,5s)...');
      _appStartMark('auth.stateChanges.wait');
      try {
        await FirebaseAuth.instance
            .authStateChanges()
            .where((x) => x != null && !x.isAnonymous)
            .first
            .timeout(
              const Duration(milliseconds: 2500),
              onTimeout: () => null,
            );
        _appStartMark('auth.stateChanges.done',
            detail: FirebaseAuth.instance.currentUser?.uid ?? 'null');
        u = FirebaseAuth.instance.currentUser;
      } catch (_) {
        _appStartMark('auth.stateChanges.error');
      }
    }
    hasUser = u != null && !u.isAnonymous;
    BootPerfLog.markBoot('auth_end', detail: 'hasUser=$hasUser');
    _appStartMark('auth.resolved', detail: 'hasUser=$hasUser');
    logD('[BOOT-AUTH] currentUser → hasUser=$hasUser');
  }
  final isNoUser = !hasUser;
  if (webCatalogMinimalBoot || isNoUser) {
    if (webCatalogMinimalBoot) {
      logD(
          '[BOOT-CATALOG-WEB] Fast path: catálogo público (visitante ou admin na mesma origem)');
    } else {
      logD(
          '[BOOT-OFFLINE] Fast path: sem usuário → bootstrap mínimo para login');
    }
    boot.mark('auth.no_user');
    boot.mark('appcheck.skip_fastpath');
    boot.mark('remoteconfig.defer');
    FirebaseGuard.markReady();
    boot.mark('hive.init.begin');
    BootPerfLog.markBoot('hive_start');
    if (kIsWeb) {
      _appStartMark('hive.initFlutter.begin');
      await Hive.initFlutter().timeout(_kHiveInitFlutterBudget);
      _appStartMark('hive.initFlutter.ok');
    } else {
      final dirPath = await getAppDocsDirPath();
      await Hive.initFlutter(dirPath);
    }
    boot.mark('hive.init.ok');
    BootPerfLog.markBoot('hive_end');
    logD(
      '[BOOT-FASTPATH] adapters ERP em background (sem bloquear 1º frame; visitante/login)',
    );
    unawaited(_registerHiveAdaptersBootstrapDeferred());
    await _hiveOpenTracked('sessao');
    await _hiveOpenTracked('config');
    boot.mark('hive.boxes.critical');
    _appStartMark('session_sanity.begin');
    try {
      await SessionSanity.fixIfNoFirebaseUser()
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      _appStartMark('session_sanity.TIMEOUT');
    } on Object {
      _appStartMark('session_sanity.error');
    }
    initDarkModeFromHive();
    boot.mark('local.fix.ok');
    scheduleBootstrapDeferredWork(
      delay: Duration(milliseconds: webCatalogMinimalBoot ? 0 : 120),
      logTag:
          webCatalogMinimalBoot ? 'catalog_web_deferred_min' : 'fastpath_full',
      work: () => _bootstrapDeferredFull(
        firebaseOk: firebaseOk,
        publicCatalogWebVisitor: webCatalogMinimalBoot,
      ),
    );
    _appStartMark('bootstrap.fastpath.done',
        finalDecision: 'login_deferred_in_background');
    logD('✅ [BOOT] Bootstrap fast path concluído – mostrando login');
    logD(boot.dump());
    return;
  }

  // Fluxo completo (mobile ou web com usuário já logado)
  if (firebaseOk) {
    BootPerfLog.markBoot('appcheck_start');
    logD(
        '[BOOT_FIREBASE_PHASE] RemoteConfig + AppCheck + Monitoring (paralelo)');
    await Future.wait<void>([
      RemoteConfigService.init().timeout(const Duration(seconds: 8),
          onTimeout: () {
        logD('[BOOT-OFFLINE] RemoteConfig timeout – usando defaults');
      }).catchError((Object e, StackTrace _) {
        logW(
            '[BOOT-OFFLINE] RemoteConfig falhou (type=${e.runtimeType}) – usando defaults');
      }),
      initFirebaseAppCheck().timeout(const Duration(seconds: 5), onTimeout: () {
        logD('[BOOT-OFFLINE] AppCheck timeout – continuando sem proteção');
      }).catchError((Object e, StackTrace st) {
        logW('[AppCheck] (ignorado) Falha não bloqueia render.',
            tag: 'APP-CHECK');
        if (kDebugMode) logD('   (type=${e.runtimeType})\n   $st');
      }),
      initFirebaseMonitoring().timeout(const Duration(seconds: 3),
          onTimeout: () {
        logD('[BOOT-OFFLINE] Monitoring timeout – ignorado');
      }).catchError((Object _, StackTrace __) {}),
    ]);
    _appStartMark('bootstrap.remote_parallel.done');
    BootPerfLog.markBoot('appcheck_end');
    boot.mark('remoteconfig.ok');
    boot.mark('appcheck.ok');
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

  // FCM: adiado para [BOOT_DEFERRED] (_bootstrapLoggedInHeavy) — não bloqueia 1º frame útil.

  FirebaseGuard.markReady();

  boot.mark('hive.init.begin');
  BootPerfLog.markBoot('hive_start');
  if (!kIsWeb) {
    final dirPath = await getAppDocsDirPath();
    await Hive.initFlutter(dirPath);
    logD('🟦 [BOOT] Hive.initFlutter() em: $dirPath');
  } else {
    _appStartMark('hive.initFlutter.begin');
    await Hive.initFlutter().timeout(_kHiveInitFlutterBudget);
    _appStartMark('hive.initFlutter.ok');
    logD('🟦 [BOOT] Hive.initFlutter() (Web)');
  }
  boot.mark('hive.init.ok');
  BootPerfLog.markBoot('hive_end');

  _registerAllHiveAdaptersBootstrap();
  boot.mark('hive.adapters.ok');
  logD('🟢 [BOOT] Adapters Hive registrados');

  // ✅ Reset controlado de boxes com schema antigo (evita crash por typeId inválido)
  await resetHiveIfSchemaChanged();

  // [BOOT_HIVE_LAZY] NotificacaoService, SyncQueue, boxes legadas → _bootstrapLoggedInHeavy (pós-frame)

  Future<void> openDynamicCritical(String name) async {
    if (Hive.isBoxOpen(name)) return;
    try {
      await Hive.openBox(name).timeout(_kHiveOpenBudget);
      logD('[BOOT_CRITICAL] Hive box: $name');
    } catch (e) {
      logD('🟥 [BOOT_CRITICAL] Erro ao abrir $name (type=${e.runtimeType})');
      if (!kIsWeb) {
        try {
          final dirPath = await getAppDocsDirPath();
          final file = File('$dirPath/$name.hive');
          if (await file.exists()) {
            logD('🧹 [BOOT_CRITICAL] Deletando arquivo corrompido: $name.hive');
            await file.delete();
          }
          await Hive.openBox(name);
        } catch (e2) {
          logD(
              '🟥 [BOOT_CRITICAL] Falha ao recuperar $name (type=${e2.runtimeType})');
        }
      }
    }
  }

  await openDynamicCritical('sessao');
  await openDynamicCritical('config');
  boot.mark('hive.boxes.critical');

  _appStartMark('session_sanity.begin');
  try {
    await SessionSanity.fixIfNoFirebaseUser()
        .timeout(const Duration(seconds: 8));
  } on TimeoutException {
    _appStartMark('session_sanity.TIMEOUT');
  } on Object {
    _appStartMark('session_sanity.error');
  }

  // Web com usuário: aguardar Auth restaurar sessão antes de resolver store_id
  if (firebaseOk && kIsWeb && FirebaseAuth.instance.currentUser == null) {
    logD('🟡 [WEB_BOOT] Aguardando Auth restaurar sessão (até 4s)...');
    _appStartMark('auth.web_restore.wait');
    try {
      await FirebaseAuth.instance
          .authStateChanges()
          .where((u) => u != null)
          .first
          .timeout(const Duration(seconds: 4), onTimeout: () => null);
      _appStartMark('auth.web_restore.done',
          detail: FirebaseAuth.instance.currentUser?.uid ?? 'null');
      logD('🟢 [WEB_BOOT] Auth restaurado');
    } catch (_) {
      _appStartMark('auth.web_restore.error');
    }
  }

  await _ensureStoreIdOnBootstrap(firebaseOk: firebaseOk);
  mpStoreDiag('BOOT.afterEnsureStoreId');

  if (kDebugMode) {
    final sessao = Hive.box('sessao');
    final config = Hive.box('config');
    logD('[BOOT_CRITICAL] sessao.keys → ${sessao.keys.toList()}');
    logD('[BOOT_CRITICAL] config.keys → ${config.keys.toList()}');
    logD(
        '[BOOT_CRITICAL] store_id sessao=${sessao.get("store_id")} config=${config.get("store_id")}');
  }

  initDarkModeFromHive();

  await _fixPedidoLinkBase();

  boot.mark('local.fix.ok');

  logD(
      '✅ [BOOT_CRITICAL] Caminho crítico concluído — [BOOT_DEFERRED] agendado');
  logD(boot.dump());

  _scheduleLoggedInHeavyOnce(firebaseOk: firebaseOk);

  _appStartMark('bootstrap.leave', finalDecision: 'my_app_ready');
  BootPerfLog.markBoot('bootstrap.leave', detail: 'my_app_ready');
  logD('🟢 [BOOT] _bootstrapSafe() finalizado (crítico; pesado em background)');
}

/// Executa etapas do bootstrap em background (usado no fast path web sem usuário).
Future<void> _bootstrapDeferred({required bool firebaseOk}) async {
  try {
    await _ensureStoreIdOnBootstrap(firebaseOk: firebaseOk);
    await _fixPedidoLinkBase();
    if (_safeFirebaseAppsIsNotEmpty()) {
      await refreshPermissoesLocais();
    }
    await backup_auto_service.BackupAutoService.iniciarAgendamento();
    try {
      final autoSync = ProdutoAutoSyncService();
      await autoSync.start();
      logD('✅ [BOOT] Auto-sincronização de produtos iniciada (deferred)');
    } catch (e) {
      logW(
          '⚠️ [BOOT] Erro ao iniciar auto-sync deferred (type=${e.runtimeType})');
    }
    await SoftDeleteService.processOnStartup();
    await FinanceiroSoftDeleteService.processOnStartup();
    logD('🟢 [BOOT] _bootstrapDeferred() concluído');
  } catch (e, st) {
    logW('⚠️ [BOOT] _bootstrapDeferred falhou (type=${e.runtimeType})');
    if (kDebugMode) logD('   $st');
  }
}

/// Bootstrap completo em background (fast path web + mobile): RemoteConfig, App Check, boxes Hive, SyncQueue, etc.
///
/// [publicCatalogWebVisitor]: visitante abrindo só `/loja/...` (ou host mapeado) — não abre dezenas de
/// boxes Hive nem SyncQueue/auto-sync; isso deixava o catálogo web lento sem benefício.
Future<void> _bootstrapDeferredFull({
  required bool firebaseOk,
  bool publicCatalogWebVisitor = false,
}) async {
  try {
    if (publicCatalogWebVisitor) {
      logD(
        '[BOOT-CATALOG-WEB] deferred mínimo: sem Hive extra, SyncQueue, auto-sync '
        '(visitante catálogo público)',
      );
      if (firebaseOk) {
        unawaited(
          RemoteConfigService.init()
              .timeout(const Duration(seconds: 8), onTimeout: () {})
              .catchError((Object _, StackTrace __) {}),
        );
        unawaited(
          initFirebaseAppCheck()
              .timeout(const Duration(seconds: 5), onTimeout: () {})
              .catchError((Object _, StackTrace __) {}),
        );
        unawaited(
          initFirebaseMonitoring()
              .timeout(const Duration(seconds: 3), onTimeout: () {})
              .catchError((Object _, StackTrace __) {}),
        );
      }
      logD(
          '🟢 [BOOT] _bootstrapDeferredFull() concluído (catálogo web mínimo)');
      return;
    }

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
          logW(
            '[WEB_BOX_FALLBACK] box=$name contexto=deferred_open',
            tag: 'WEB_BOX_FALLBACK',
          );
        } catch (_) {}
      } else {
        try {
          final dirPath = await getAppDocsDirPath();
          final file = File('$dirPath/$name.hive');
          if (await file.exists()) await file.delete();
          await Hive.openBox<T>(name);
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
              logD('[AUTH] Firebase OFFLINE – usando AuthService.offline()');
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
                final args = raw is Map
                    ? Map<String, dynamic>.from(
                        raw.map((k, v) => MapEntry(k.toString(), v)))
                    : null;
                return VerifyEmailScreen(
                  email: args?['email']?.toString(),
                  nextRoute: args?['nextRoute']?.toString() ?? '/',
                );
              },
              '/preconfig': (_) => const LojaPreconfigScreen(),
              '/fornecedores': (_) => _planGate(
                    PlanGateFeature.fornecedores,
                    const FornecedoresScreen(),
                  ),
              '/vendas': (_) => kIsWeb
                  ? const AdminWebRouteShell(child: VendasScreen())
                  : const VendasScreen(),
              '/clientes': (_) => kIsWeb
                  ? const AdminWebRouteShell(child: ClientesScreen())
                  : const ClientesScreen(),
              '/estoque': (_) => const EstoqueScreen(),
              '/historico_cliente': (_) => const HistoricoClientesScreen(),
              '/backup': (_) => _planGate(
                    PlanGateFeature.backupLoja,
                    const BackupScreen(),
                  ),
              '/relatorios': (_) => const RelatoriosScreen(),
              '/precificacao': (_) => _planGate(
                    PlanGateFeature.precificacao,
                    const PrecificacaoUniversalScreen(),
                  ),
              '/modelos_importacao': (ctx) {
                final raw = ModalRoute.of(ctx)?.settings.arguments;
                final map = raw is Map
                    ? Map<String, dynamic>.from(
                        raw.map((k, v) => MapEntry(k.toString(), v)),
                      )
                    : null;
                final t = map?['tab'];
                int idx = 0;
                if (t is int) {
                  idx = t;
                } else if (t is num) {
                  idx = t.toInt();
                } else if (t != null) {
                  idx = int.tryParse(t.toString()) ?? 0;
                }
                return _planGate(
                  PlanGateFeature.modelosImportacao,
                  ModelosImportacaoScreen(initialTabIndex: idx),
                );
              },
              '/relatorio_vendedor': (_) => _planGate(
                    PlanGateFeature.vendedores,
                    const RelatorioVendedorScreen(),
                  ),
              '/cadastro': (_) => const CadastroScreen(),
              '/permissao': (_) => const PermissoesScreen(),
              '/permissoes': (_) => const PermissoesScreen(),
              '/plano': (_) => _authRoute(const PlanoScreen()),
              '/planos': (_) => _authRoute(const PlanosScreen()),
              '/admin_usuarios': (_) => const AdminUsuariosScreen(),
              '/mestre/assinaturas': (_) => const MasterPlanAccessScreen(),
              '/master_login': (_) => const MasterLoginScreen(),
              '/master_config': (_) => const MasterConfigScreen(),
              '/catalog_payment_support': (ctx) => CatalogPaymentSupportScreen(
                    routeArguments: ModalRoute.of(ctx)?.settings.arguments,
                  ),
              '/site_config': (_) => const SiteConfigScreen(),
              '/cadastro_usuarios': (_) => _planGate(
                    PlanGateFeature.vendedores,
                    const VendedoresScreen(),
                  ),
              '/cadastro_usuario': (_) => _planGate(
                    PlanGateFeature.vendedores,
                    const VendedoresScreen(),
                  ),
              '/gerenciar_vendedores': (_) => _planGate(
                    PlanGateFeature.vendedores,
                    const VendedoresScreen(),
                  ),
              '/vendedores': (_) => _planGate(
                    PlanGateFeature.vendedores,
                    const VendedoresScreen(),
                  ),
              '/visualizar_permissoes': (_) =>
                  const VisualizarPermissoesScreen(),
              // Catálogo interno admin = Estoque (produtos Hive). CatalogoScreen
              // legado (/catalogo) apontava para box `catalogo_*` desatualizada.
              '/catalogo_interno': (_) => const CatalogoInternoScreen(),
              '/catalogo': (_) => const EstoqueScreen(),
              '/cadastro_catalogo': (_) => const CadastroCatalogoScreen(),
              '/relatorio_financeiro': (_) => _planGate(
                    PlanGateFeature.relatorioFinanceiroDetalhado,
                    const RelatorioFinanceiroScreen(),
                  ),
              '/relatorios_financeiros': (_) => _planGate(
                    PlanGateFeature.relatoriosFinanceirosHub,
                    ScopeRouteGate(
                      allow: AccessScopeService.canSeeFinanceiroMetasLoja,
                      child: const RelatoriosFinanceirosScreen(),
                    ),
                  ),
              '/relatorio_mais_vendidos': (ctx) => _lojaIdRouteGated(
                    PlanGateFeature.maisVendidos,
                    (lojaId) => ScopeRouteGate(
                      allow: AccessScopeService.canSeeMaisVendidos,
                      child: RelatorioMaisVendidosScreen(lojaId: lojaId),
                    ),
                  ),
              '/relatorio_ranking_clientes': (ctx) => _lojaIdRouteGated(
                    PlanGateFeature.relatorioRankingClientes,
                    (lojaId) => RelatorioRankingClientesScreen(lojaId: lojaId),
                  ),
              '/relatorio_lucratividade_produto': (ctx) => _lojaIdRouteGated(
                    PlanGateFeature.relatorioLucratividade,
                    (lojaId) =>
                        RelatorioLucratividadeProdutoScreen(lojaId: lojaId),
                  ),
              '/carrinhos_abandonados': (ctx) => _lojaIdRouteGated(
                    PlanGateFeature.carrinhosAbandonados,
                    (lojaId) => CarrinhosAbandonadosScreen(lojaId: lojaId),
                  ),
              '/config_carrinhos_abandonados': (ctx) => _lojaIdRouteGated(
                    PlanGateFeature.carrinhosAbandonados,
                    (lojaId) =>
                        CarrinhoAbandonadoConfigScreen(lojaId: lojaId),
                  ),
              '/catalog_avaliacoes_moderacao': (ctx) => _lojaIdRouteGated(
                    PlanGateFeature.catalogoAvaliacoesModeracao,
                    (lojaId) => kIsWeb
                        ? AdminWebRouteShell(
                            child: CatalogAvaliacoesModeracaoScreen(
                                lojaId: lojaId),
                          )
                        : CatalogAvaliacoesModeracaoScreen(lojaId: lojaId),
                  ),
              '/config/pagamentos': (_) => _planGate(
                    PlanGateFeature.configurarPagamentosOnline,
                    const ConfigPagamentosSimplesScreen(),
                  ),
              '/config-pagamentos': (_) => _planGate(
                    PlanGateFeature.configurarPagamentosOnline,
                    const ConfigPagamentosScreen(),
                  ),
              '/admin_sync': (_) => _planGate(
                    PlanGateFeature.adminSync,
                    const AdminSyncScreen(),
                  ),
              '/configuracoes_catalogo': (_) => const LojaConfigScreen(),
              '/health': (_) => const HealthCheckScreen(),
              '/diagnostico': (_) => const DiagnosticoAppScreen(),
              '/ajuda': (_) => const AjudaScreen(),
              '/config_pin': (_) => const ConfigPinScreen(),
              '/test_checkout': (_) => const TestCheckout(),
              '/pedidos_pendentes': (_) => _planGate(
                    PlanGateFeature.pedidosPrePedidos,
                    _pedidosRoute(),
                  ),
              '/pedidos': (ctx) {
                final raw = ModalRoute.of(ctx)?.settings.arguments;
                final map = raw is Map
                    ? Map<String, dynamic>.from(
                        raw.map((k, v) => MapEntry(k.toString(), v)))
                    : null;
                final lojaIdArg = map?['lojaId']?.toString();
                final pedidoIdArg = map?['pedidoId']?.toString();
                if (lojaIdArg != null && lojaIdArg.isNotEmpty) {
                  return _planGate(
                    PlanGateFeature.pedidosPrePedidos,
                    PrePedidosScreen(
                      lojaId: lojaIdArg,
                      initialPedidoId:
                          pedidoIdArg?.isNotEmpty == true ? pedidoIdArg : null,
                    ),
                  );
                }
                return _planGate(
                  PlanGateFeature.pedidosPrePedidos,
                  _pedidosRoute(),
                );
              },
              '/onboarding_loja': (_) => const OnboardingLojaScreen(),
              '/campanhas_sorteio': (_) => _planGate(
                    PlanGateFeature.campanhasSorteios,
                    const CampanhasSorteioScreen(),
                  ),
              '/marketing_hub': (_) => _planGate(
                    PlanGateFeature.campanhasSorteios,
                    const MarketingHubScreen(),
                  ),
              '/campanhas_dashboard': (_) => _planGate(
                    PlanGateFeature.campanhasSorteios,
                    const CampanhasDashboardScreen(),
                  ),
              '/roleta_dashboard': (_) => _planGate(
                    PlanGateFeature.campanhasSorteios,
                    const RoletaDashboardScreen(),
                  ),
              '/roleta_historico': (_) => _planGate(
                    PlanGateFeature.campanhasSorteios,
                    const RoletaHistoricoScreen(),
                  ),
              '/marketing_estatisticas': (_) => _planGate(
                    PlanGateFeature.campanhasSorteios,
                    const MarketingEstatisticasScreen(),
                  ),
              '/fretes_cupons': (_) => _planGate(
                    PlanGateFeature.fretesCupons,
                    const FretesCuponsScreen(),
                  ),
              '/metas_comissoes': (_) => _planGate(
                    PlanGateFeature.metasComissoes,
                    const MetasComissoesRoute(),
                  ),
              '/vendas_canceladas_vendedor': (_) =>
                  const VendasCanceladasVendedorRoute(),
              '/motor_crescimento': (ctx) => _lojaIdRouteGated(
                    PlanGateFeature.motorCrescimento,
                    (lojaId) => MotorCrescimentoScreen(lojaId: lojaId),
                  ),
              '/campanhas_sugeridas': (ctx) => _lojaIdRouteGated(
                    PlanGateFeature.campanhasSugeridas,
                    (lojaId) => CampanhasSugeridasScreen(lojaId: lojaId),
                  ),
              '/notas_fiscais': (_) => _planGate(
                    PlanGateFeature.notasFiscais,
                    const NotasFiscaisScreen(),
                  ),
              '/contas_receber': (_) => _planGate(
                    PlanGateFeature.contasReceber,
                    const ContasReceberScreen(),
                  ),
              '/contas_pagar': (_) => _planGate(
                    PlanGateFeature.financeiroLancamentos,
                    const ContasPagarScreen(),
                  ),
              '/financeiro': (ctx) {
                DateTime? mesInicial;
                final raw = ModalRoute.of(ctx)?.settings.arguments;
                if (raw is Map) {
                  final m = raw['mesInicial'];
                  if (m is DateTime) mesInicial = m;
                }
                return _planGate(
                  PlanGateFeature.financeiroLancamentos,
                  FinanceiroScreen(mesInicial: mesInicial),
                );
              },
              '/globo_sorteio': (_) => _planGate(
                    PlanGateFeature.globoSorteio,
                    const GloboSorteioScreenWrapper(),
                  ),
              '/dashboard_insights': (_) => _lojaIdRouteGated(
                    PlanGateFeature.insights,
                    (lojaId) => DashboardInsightsScreen(lojaId: lojaId),
                  ),
              '/dicas_ia': (_) => _planGate(
                    PlanGateFeature.dicasIA,
                    const DicasIaScreen(),
                  ),
              '/textos_whatsapp_ia': (_) => _planGate(
                    PlanGateFeature.textosWhatsappIA,
                    const TextosWhatsAppIaScreen(),
                  ),
              '/gerar_postagem': (_) => _planGate(
                    PlanGateFeature.gerarPostagem,
                    const GerarPostagemScreen(),
                  ),
              '/compartilhar_whatsapp': (_) => _planGate(
                    PlanGateFeature.compartilharWhatsapp,
                    const CompartilharWhatsAppScreen(),
                  ),
              '/analise_vendas_ia': (_) => _planGate(
                    PlanGateFeature.analiseVendasIA,
                    const AnaliseVendasIaScreen(),
                  ),
              '/home': (_) => const HomeScreen(),
              '/marketplaces': (_) => _planGate(
                    PlanGateFeature.marketplaces,
                    const MarketplacesScreen(),
                  ),
              '/configuracoes/canais_meta': (_) => _planGate(
                    PlanGateFeature.canaisMeta,
                    const CanaisMetaScreen(),
                  ),

              // ✅ ROTA /loja: na Web usa SEMPRE o lojaId da URL (path ou fragment); no app usa LojaIdService
              '/loja': (_) {
                if (kIsWeb) {
                  final fromUrl = _lojaSlugOrIdFromUrl();
                  if (fromUrl.isNotEmpty && fromUrl != 'minha-loja') {
                    final pageRaw = Uri.base.queryParameters['page']?.trim();
                    final pageSplit = catalogInterpretPageQueryParam(pageRaw);
                    final cartId = Uri.base.queryParameters['cart']?.trim();
                    final produtoId =
                        Uri.base.queryParameters['produto']?.trim();
                    final prodParam = catalogSanitizeProdQuery(
                        Uri.base.queryParameters['prod']);
                    final tam = Uri.base.queryParameters['tam']?.trim();
                    final cor = Uri.base.queryParameters['cor']?.trim();
                    final xv =
                        catalogSanitizeXvQuery(Uri.base.queryParameters['xv']);
                    final cat = Uri.base.queryParameters['cat']?.trim();
                    final sub = Uri.base.queryParameters['sub']?.trim();
                    final ord = Uri.base.queryParameters['ord']?.trim();
                    final pmin = Uri.base.queryParameters['pmin']?.trim();
                    final pmax = Uri.base.queryParameters['pmax']?.trim();
                    final searchQ = Uri.base.queryParameters['q']?.trim();
                    logD(
                        '🛒 [ROUTE /loja] Web: lojaId da URL → $fromUrl, page=$pageRaw, cart=$cartId, produto=$produtoId');
                    return PublicCatalogScreen(
                        lojaId: fromUrl,
                        vendedorRef: _vendedorRefFromUrl(),
                        indicacaoClienteRef: _indicacaoRefFromUrl(),
                        initialPage: pageSplit.namedInitialPage,
                        initialCatalogPage: pageSplit.catalogPage1Based,
                        initialCartId:
                            cartId?.isNotEmpty == true ? cartId : null,
                        initialProdutoId:
                            produtoId?.isNotEmpty == true ? produtoId : null,
                        initialProd: prodParam,
                        initialTam: tam?.isNotEmpty == true ? tam : null,
                        initialCor: cor?.isNotEmpty == true ? cor : null,
                        initialXv: xv,
                        initialCat: cat?.isNotEmpty == true ? cat : null,
                        initialSub: sub?.isNotEmpty == true ? sub : null,
                        initialOrd: ord?.isNotEmpty == true ? ord : null,
                        initialPmin: pmin?.isNotEmpty == true ? pmin : null,
                        initialPmax: pmax?.isNotEmpty == true ? pmax : null,
                        initialQ: searchQ?.isNotEmpty == true ? searchQ : null);
                  }
                }
                return FutureBuilder<String?>(
                  future: LojaIdService.get(),
                  builder: (_, snap) {
                    final lojaId = (snap.data ?? '').trim();
                    // Sem loja ou placeholder: mostra "Configure sua loja online". Nunca abre outra loja.
                    if (lojaId.isEmpty || !isValidForPublicLink(lojaId)) {
                      logD(
                          '🛒 [ROUTE /loja] Sem loja válida → ConfigureLojaPlaceholderScreen');
                      return const ConfigureLojaPlaceholderScreen();
                    }
                    final vendedorRef = _vendedorRefFromUrl();
                    final indicacaoRef = _indicacaoRefFromUrl();
                    final cartId = kIsWeb
                        ? (Uri.base.queryParameters['cart']?.trim())
                        : null;
                    final produtoId = kIsWeb
                        ? (Uri.base.queryParameters['produto']?.trim())
                        : null;
                    final prodParam = kIsWeb
                        ? catalogSanitizeProdQuery(
                            Uri.base.queryParameters['prod'])
                        : null;
                    final tam = kIsWeb
                        ? (Uri.base.queryParameters['tam']?.trim())
                        : null;
                    final cor = kIsWeb
                        ? (Uri.base.queryParameters['cor']?.trim())
                        : null;
                    final xv = kIsWeb
                        ? catalogSanitizeXvQuery(Uri.base.queryParameters['xv'])
                        : null;
                    final cat = kIsWeb
                        ? (Uri.base.queryParameters['cat']?.trim())
                        : null;
                    final sub = kIsWeb
                        ? (Uri.base.queryParameters['sub']?.trim())
                        : null;
                    final ord = kIsWeb
                        ? (Uri.base.queryParameters['ord']?.trim())
                        : null;
                    final pmin = kIsWeb
                        ? (Uri.base.queryParameters['pmin']?.trim())
                        : null;
                    final pmax = kIsWeb
                        ? (Uri.base.queryParameters['pmax']?.trim())
                        : null;
                    final searchQ =
                        kIsWeb ? (Uri.base.queryParameters['q']?.trim()) : null;
                    final pageSplit = catalogInterpretPageQueryParam(
                      kIsWeb ? Uri.base.queryParameters['page']?.trim() : null,
                    );
                    return PublicCatalogScreen(
                        lojaId: lojaId,
                        vendedorRef: vendedorRef,
                        indicacaoClienteRef: indicacaoRef,
                        initialPage: pageSplit.namedInitialPage,
                        initialCatalogPage: pageSplit.catalogPage1Based,
                        initialCartId:
                            cartId?.isNotEmpty == true ? cartId : null,
                        initialProdutoId:
                            produtoId?.isNotEmpty == true ? produtoId : null,
                        initialProd: prodParam,
                        initialTam: tam?.isNotEmpty == true ? tam : null,
                        initialCor: cor?.isNotEmpty == true ? cor : null,
                        initialXv: xv,
                        initialCat: cat?.isNotEmpty == true ? cat : null,
                        initialSub: sub?.isNotEmpty == true ? sub : null,
                        initialOrd: ord?.isNotEmpty == true ? ord : null,
                        initialPmin: pmin?.isNotEmpty == true ? pmin : null,
                        initialPmax: pmax?.isNotEmpty == true ? pmax : null,
                        initialQ: searchQ?.isNotEmpty == true ? searchQ : null);
                  },
                );
              },

              // ✅ ROTA /loja_preview: pré-visualização interna (draft_config/produtos).
              // Importante no Web: rota nomeada para manter histórico do browser (back funciona no iPhone).
              '/loja_preview': (ctx) {
                final rawArgs = ModalRoute.of(ctx)?.settings.arguments;
                final args = rawArgs is Map
                    ? rawArgs.cast<String, dynamic>()
                    : <String, dynamic>{};
                final lojaIdArg = args['lojaId']?.toString().trim() ?? '';
                return LojaPreviewShellScreen(lojaId: lojaIdArg);
              },
            },
            onGenerateRoute: app_routes.onGenerateRoute,
          );
        },
      ),
    );
  }
}
