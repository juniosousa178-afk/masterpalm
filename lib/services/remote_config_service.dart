// lib/services/remote_config_service.dart
// Serviço para buscar configurações remotas (ex: chave reCAPTCHA).
// Fallback para valores padrão se Remote Config falhar.

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

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
  static bool _initialized = false;

  /// Retorna a chave reCAPTCHA (do Remote Config ou fallback)
  static String get recaptchaSiteKey => _recaptchaSiteKey;

  /// Preço do plano mensal (Remote Config ou fallback)
  static double get planoMensalPreco => _planoMensalPreco;

  /// Preço do plano anual (Remote Config ou fallback)
  static double get planoAnualPreco => _planoAnualPreco;

  /// API Key da Globo da Sorte (Remote Config – nunca hardcoded)
  static String get globoSorteApiKey => _globoSorteApiKey;

  /// Inicializa Remote Config e busca valores.
  /// Chamar após Firebase.initializeApp().
  static Future<void> init() async {
    if (_initialized) return;

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
