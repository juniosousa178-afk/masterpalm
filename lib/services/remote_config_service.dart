// lib/services/remote_config_service.dart
// Serviço para buscar configurações remotas (ex: chave reCAPTCHA).
// Fallback para valores padrão se Remote Config falhar.

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;

import '../core/logger.dart';

class RemoteConfigService {
  RemoteConfigService._();

  static FirebaseRemoteConfig get _rc => FirebaseRemoteConfig.instance;

  /// Chaves do Remote Config
  static const String _keyRecaptchaSiteKey = 'recaptcha_site_key';
  static const String _keyPlanoMensalPreco = 'plano_mensal_preco';
  static const String _keyPlanoAnualPreco = 'plano_anual_preco';
  static const String _keyGloboSorteApiKey = 'globo_sorte_api_key';

  /// Valores padrão (fallback)
  static const String _defaultRecaptchaSiteKey =
      '6Ldz2esrAAAAAEXa0zdZlGPC7Bn4rnGX_jswYlTv';
  static const double _defaultPlanoMensalPreco = 39.99;
  static const double _defaultPlanoAnualPreco = 349.99;
  static const String _defaultGloboSorteApiKey = '';

  static String _recaptchaSiteKey = _defaultRecaptchaSiteKey;
  static double _planoMensalPreco = _defaultPlanoMensalPreco;
  static double _planoAnualPreco = _defaultPlanoAnualPreco;
  static String _globoSorteApiKey = _defaultGloboSorteApiKey;
  static bool _useRecurringPlanBilling = false;
  /// UIDs ou e-mails (minúsculos) que podem usar checkout v2 com [use_recurring_plan_billing] global `false`.
  static final Set<String> _recurringPlanBillingAllowlist = {};
  static bool _initialized = false;

  /// Retorna a chave reCAPTCHA (do Remote Config ou fallback)
  static String get recaptchaSiteKey => _recaptchaSiteKey;

  /// Preço do plano mensal (Remote Config ou fallback)
  static double get planoMensalPreco => _planoMensalPreco;

  /// Preço do plano anual (Remote Config ou fallback)
  static double get planoAnualPreco => _planoAnualPreco;

  /// API Key da Globo da Sorte (Remote Config – nunca hardcoded)
  static String get globoSorteApiKey => _globoSorteApiKey;

  /// Assinatura recorrente Mercado Pago (createPlanSubscription). Requer backend USE_RECURRING_PLAN_BILLING.
  static bool get useRecurringPlanBilling => _useRecurringPlanBilling;

  /// Rollout: `true` se RC global [use_recurring_plan_billing] **ou** UID/e-mail em [recurring_plan_billing_allowlist].
  /// O backend continua exigindo `USE_RECURRING_PLAN_BILLING`; sem isso o app faz fallback para legado.
  static bool shouldUseRecurringPlanBilling({
    required String uid,
    String? email,
  }) {
    if (_useRecurringPlanBilling) return true;
    if (_recurringPlanBillingAllowlist.isEmpty) return false;
    if (_recurringPlanBillingAllowlist.contains(uid)) return true;
    final e = (email ?? '').trim().toLowerCase();
    if (e.isNotEmpty && _recurringPlanBillingAllowlist.contains(e)) return true;
    return false;
  }

  /// Inicializa Remote Config e busca valores.
  /// Chamar após Firebase.initializeApp().
  static Future<void> init() async {
    if (_initialized) return;

    // Firebase Remote Config Web não expõe o plugin nativo; evita crash (FirebaseRemoteConfigWeb undefined).
    if (kIsWeb) {
      _initialized = true;
      logD(
        '🌐 [RemoteConfig] Web: plugin indisponível — usando valores padrão locais.',
      );
      return;
    }

    try {
      await _rc.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: kDebugMode
            ? const Duration(minutes: 1)
            : const Duration(hours: 1),
      ));

      await _rc.setDefaults({
        _keyRecaptchaSiteKey: _defaultRecaptchaSiteKey,
        _keyPlanoMensalPreco: _defaultPlanoMensalPreco,
        _keyPlanoAnualPreco: _defaultPlanoAnualPreco,
        _keyGloboSorteApiKey: _defaultGloboSorteApiKey,
        'use_recurring_plan_billing': false,
        'recurring_plan_billing_allowlist': '',
      });

      await _rc.fetchAndActivate();
      _recaptchaSiteKey =
          _rc.getString(_keyRecaptchaSiteKey).trim().isNotEmpty
              ? _rc.getString(_keyRecaptchaSiteKey)
              : _defaultRecaptchaSiteKey;

      final pMensal = _rc.getDouble(_keyPlanoMensalPreco);
      final pAnual = _rc.getDouble(_keyPlanoAnualPreco);
      if (pMensal > 0) _planoMensalPreco = pMensal;
      if (pAnual > 0) _planoAnualPreco = pAnual;

      final gsKey = _rc.getString(_keyGloboSorteApiKey).trim();
      if (gsKey.isNotEmpty) _globoSorteApiKey = gsKey;

      try {
        _useRecurringPlanBilling = _rc.getBool('use_recurring_plan_billing');
      } catch (_) {
        _useRecurringPlanBilling = false;
      }

      _recurringPlanBillingAllowlist.clear();
      try {
        final raw = _rc.getString('recurring_plan_billing_allowlist').trim();
        if (raw.isNotEmpty) {
          for (final part in raw.split(',')) {
            final s = part.trim();
            if (s.isNotEmpty) {
              _recurringPlanBillingAllowlist.add(s.contains('@') ? s.toLowerCase() : s);
            }
          }
        }
      } catch (_) {}

      _initialized = true;
      logD('✅ [RemoteConfig] Inicializado. recaptcha_site_key carregado.');
    } catch (e, st) {
      logE('⚠️ [RemoteConfig] Falha ao inicializar (type=${e.runtimeType}). Usando fallback.', error: e, st: st);
      _recaptchaSiteKey = _defaultRecaptchaSiteKey;
      _globoSorteApiKey = _defaultGloboSorteApiKey;
      _initialized = true;
    }
  }
}
