// lib/services/remote_config_safe_service.dart
// Leitura segura de Remote Config para dados sensíveis (ETAPA 16).
// Sempre retorna fallback em erro; não altera inicialização do RC.

import 'dart:convert';

import 'package:firebase_remote_config/firebase_remote_config.dart';

import '../core/logger.dart';

class RemoteConfigSafeService {
  RemoteConfigSafeService._();

  static FirebaseRemoteConfig get _rc => FirebaseRemoteConfig.instance;

  /// Retorna true apenas se a chave estiver ativa (true no RC).
  /// Em qualquer falha, retorna [fallback].
  static bool isFlagOn(String key, {bool fallback = false}) {
    try {
      return _rc.getBool(key);
    } catch (e, st) {
      logW('RemoteConfigSafeService.isFlagOn($key) falhou, usando fallback=$fallback', tag: 'RC_SAFE');
      logE('isFlagOn (type=${e.runtimeType})', tag: 'RC_SAFE', error: e, st: st);
      return fallback;
    }
  }

  /// Lê uma lista de strings do RC: aceita JSON array ["a","b"] ou string CSV "a,b".
  /// Sanitiza: trim, lowercase, remove vazios e duplicados.
  /// Em qualquer falha, retorna [fallback].
  static List<String> getStringListFromJson(String key, {List<String> fallback = const []}) {
    try {
      final raw = _rc.getString(key).trim();
      if (raw.isEmpty) return fallback;

      List<String> list;
      if (raw.startsWith('[')) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          list = decoded.map((e) => e?.toString().trim().toLowerCase()).where((s) => s != null && s.isNotEmpty).cast<String>().toList();
        } else {
          return fallback;
        }
      } else {
        list = raw.split(',').map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toList();
      }
      final deduped = list.toSet().toList();
      return deduped.isEmpty • fallback : deduped;
    } catch (e, st) {
      logW('RemoteConfigSafeService.getStringListFromJson($key) falhou, usando fallback', tag: 'RC_SAFE');
      logE('getStringListFromJson (type=${e.runtimeType})', tag: 'RC_SAFE', error: e, st: st);
      return fallback;
    }
  }
}
