// lib/services/melhor_envio_integration_service.dart
// Integração Melhor Envio via Cloud Functions (token somente no backend).

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class MelhorEnvioConfigStatus {
  final bool configured;
  final bool sandbox;
  final String? maskedToken;
  final String? lastValidationStatus;
  final bool legacyTokenNeedsRotation;
  final bool enabled;

  const MelhorEnvioConfigStatus({
    required this.configured,
    this.sandbox = false,
    this.maskedToken,
    this.lastValidationStatus,
    this.legacyTokenNeedsRotation = false,
    this.enabled = true,
  });

  factory MelhorEnvioConfigStatus.fromMap(Map? raw) {
    final m = raw ?? {};
    return MelhorEnvioConfigStatus(
      configured: m['configured'] == true,
      sandbox: m['sandbox'] == true,
      maskedToken: m['maskedToken']?.toString(),
      lastValidationStatus: m['lastValidationStatus']?.toString(),
      legacyTokenNeedsRotation: m['legacyTokenNeedsRotation'] == true,
      enabled: m['enabled'] != false,
    );
  }
}

class MelhorEnvioIntegrationService {
  MelhorEnvioIntegrationService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'southamerica-east1');

  static String _messageForSafeCode(String? safeCode) {
    switch (safeCode) {
      case 'TOKEN_INVALIDO':
        return 'O token informado é inválido ou expirou. Gere um novo token no Melhor Envio.';
      case 'API_INDISPONIVEL':
        return 'O Melhor Envio está temporariamente indisponível. Tente novamente em alguns minutos.';
      case 'RATE_LIMIT':
        return 'Muitas tentativas em pouco tempo. Aguarde alguns minutos e tente novamente.';
      case 'PERMISSION_DENIED':
        return 'Sua conta não possui permissão para configurar fretes desta loja.';
      case 'ERRO_AO_SALVAR_CONFIG':
        return 'Não foi possível salvar a configuração. Tente novamente.';
      default:
        return '';
    }
  }

  static String _friendlyMessage(FirebaseFunctionsException e) {
    final details = e.details;
    if (details is Map) {
      final fromCode = _messageForSafeCode(details['code']?.toString());
      if (fromCode.isNotEmpty) return fromCode;
    }
    if (e.code == 'permission-denied') {
      return 'O token informado é inválido ou expirou. Gere um novo token no Melhor Envio.';
    }
    if (e.code == 'unavailable') {
      return 'O Melhor Envio está temporariamente indisponível. Tente novamente em alguns minutos.';
    }
    if (e.code == 'resource-exhausted') {
      return 'Muitas tentativas em pouco tempo. Aguarde alguns minutos e tente novamente.';
    }
    if (e.code == 'invalid-argument' && (e.message ?? '').isNotEmpty) {
      return e.message!;
    }
    return 'Não foi possível concluir a operação no Melhor Envio. Tente novamente.';
  }

  static Future<Map<String, dynamic>> testConnection({
    required String lojaId,
    required String token,
    bool sandbox = false,
  }) async {
    try {
      final callable = _functions.httpsCallable('melhorEnvioTestConnection');
      final res = await callable.call(<String, dynamic>{
        'lojaId': lojaId,
        'token': token,
        'sandbox': sandbox,
      }).timeout(const Duration(seconds: 22));
      final raw = res.data;
      return raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{'ok': false};
    } on FirebaseFunctionsException catch (e) {
      return {'ok': false, 'message': _friendlyMessage(e)};
    } catch (e) {
      debugPrint('[MelhorEnvio] testConnection falhou (type=${e.runtimeType})');
      return {
        'ok': false,
        'message': 'Não foi possível testar a conexão. Tente novamente.',
      };
    }
  }

  static Future<Map<String, dynamic>> saveConfig({
    required String lojaId,
    required String token,
    required String cepOrigem,
    bool sandbox = false,
  }) async {
    try {
      final callable = _functions.httpsCallable('melhorEnvioSaveConfig');
      final res = await callable.call(<String, dynamic>{
        'lojaId': lojaId,
        'token': token,
        'cepOrigem': cepOrigem,
        'sandbox': sandbox,
      }).timeout(const Duration(seconds: 30));
      final raw = res.data;
      return raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{'ok': false};
    } on FirebaseFunctionsException catch (e) {
      return {'ok': false, 'message': _friendlyMessage(e)};
    } catch (e) {
      debugPrint('[MelhorEnvio] saveConfig falhou (type=${e.runtimeType})');
      return {
        'ok': false,
        'message': 'Não foi possível salvar a configuração. Tente novamente.',
      };
    }
  }

  static Future<MelhorEnvioConfigStatus> getConfigStatus({
    required String lojaId,
  }) async {
    try {
      final callable = _functions.httpsCallable('melhorEnvioGetConfigStatus');
      final res = await callable
          .call(<String, dynamic>{'lojaId': lojaId})
          .timeout(const Duration(seconds: 20));
      final raw = res.data;
      if (raw is Map) {
        return MelhorEnvioConfigStatus.fromMap(Map<String, dynamic>.from(raw));
      }
    } catch (e) {
      debugPrint('[MelhorEnvio] getConfigStatus falhou (type=${e.runtimeType})');
    }
    return const MelhorEnvioConfigStatus(configured: false);
  }
}
