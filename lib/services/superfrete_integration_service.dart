// lib/services/superfrete_integration_service.dart
// Integração SuperFrete via Cloud Functions (sem chamadas diretas à API).

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class SuperFreteConfigStatus {
  final bool configured;
  final bool sandbox;
  final String? maskedToken;
  final String? lastValidationStatus;
  final bool legacyTokenNeedsRotation;
  final bool enabled;

  const SuperFreteConfigStatus({
    required this.configured,
    this.sandbox = false,
    this.maskedToken,
    this.lastValidationStatus,
    this.legacyTokenNeedsRotation = false,
    this.enabled = true,
  });

  factory SuperFreteConfigStatus.fromMap(Map? raw) {
    final m = raw ?? {};
    return SuperFreteConfigStatus(
      configured: m['configured'] == true,
      sandbox: m['sandbox'] == true,
      maskedToken: m['maskedToken']?.toString(),
      lastValidationStatus: m['lastValidationStatus']?.toString(),
      legacyTokenNeedsRotation: m['legacyTokenNeedsRotation'] == true,
      enabled: m['enabled'] != false,
    );
  }
}

class SuperFreteIntegrationService {
  SuperFreteIntegrationService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'southamerica-east1');

  static String _messageForSafeCode(String? safeCode) {
    switch (safeCode) {
      case 'TOKEN_INVALIDO':
        return 'O token informado é inválido ou expirou. Gere um novo token na SuperFrete.';
      case 'SANDBOX_INCOMPATIVEL':
        return 'O token não corresponde ao ambiente selecionado. Confira a opção Sandbox.';
      case 'ENDPOINT_INCORRETO':
        return 'Não foi possível validar a integração. Nossa equipe já foi avisada.';
      case 'API_INDISPONIVEL':
        return 'A SuperFrete está temporariamente indisponível. Tente novamente em alguns minutos.';
      case 'TIMEOUT':
        return 'A conexão demorou mais que o esperado. Tente novamente.';
      case 'RATE_LIMIT':
        return 'Muitas tentativas em pouco tempo. Aguarde alguns minutos e tente novamente.';
      case 'PERMISSION_DENIED':
        return 'Sua conta não possui permissão para configurar fretes desta loja.';
      case 'ERRO_INTERNO_NAO_TRATADO':
        return 'Não foi possível testar a conexão. Tente novamente.';
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

    final code = e.code;
    final msg = (e.message ?? '').trim();
    if (code == 'permission-denied') {
      if (msg.toLowerCase().contains('token')) {
        return 'O token informado é inválido ou expirou. Gere um novo token na SuperFrete.';
      }
      return 'Sua conta não possui permissão para configurar fretes desta loja.';
    }
    if (code == 'unavailable') {
      return 'A SuperFrete está temporariamente indisponível. Tente novamente em alguns minutos.';
    }
    if (code == 'resource-exhausted') {
      return 'Muitas tentativas em pouco tempo. Aguarde alguns minutos e tente novamente.';
    }
    if (code == 'failed-precondition' && msg.isNotEmpty) return msg;
    if (code == 'deadline-exceeded') {
      return 'A conexão demorou mais que o esperado. Tente novamente.';
    }
    if (code == 'invalid-argument' && msg.isNotEmpty) return msg;
    if (code == 'internal') {
      return 'Não foi possível testar a conexão. Tente novamente.';
    }
    return 'Não foi possível concluir a operação na SuperFrete. Tente novamente.';
  }

  static Future<Map<String, dynamic>> testConnection({
    required String lojaId,
    required String token,
    bool sandbox = false,
  }) async {
    try {
      final callable = _functions.httpsCallable('superFreteTestConnection');
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
      debugPrint('[SuperFrete] testConnection falhou (type=${e.runtimeType})');
      return {
        'ok': false,
        'message':
            'Não foi possível testar a conexão. Verifique a internet e tente novamente.',
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
      final callable = _functions.httpsCallable('superFreteSaveConfig');
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
      debugPrint('[SuperFrete] saveConfig falhou (type=${e.runtimeType})');
      return {
        'ok': false,
        'message': 'Não foi possível salvar a integração. Tente novamente.',
      };
    }
  }

  static Future<SuperFreteConfigStatus> getConfigStatus({
    required String lojaId,
  }) async {
    try {
      final callable = _functions.httpsCallable('superFreteGetConfigStatus');
      final res = await callable
          .call(<String, dynamic>{'lojaId': lojaId})
          .timeout(const Duration(seconds: 15));
      final raw = res.data;
      if (raw is Map) {
        return SuperFreteConfigStatus.fromMap(Map<String, dynamic>.from(raw));
      }
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
          '[SuperFrete] getConfigStatus (${e.code}) type=${e.runtimeType}');
    } catch (e) {
      debugPrint('[SuperFrete] getConfigStatus falhou (type=${e.runtimeType})');
    }
    return const SuperFreteConfigStatus(configured: false);
  }

  static Future<Map<String, dynamic>> quote({
    required String lojaId,
    required String destinationCep,
    required double pesoGrams,
    double altura = 10,
    double largura = 20,
    double comprimento = 30,
    double valorDeclarado = 10,
    String? cepOrigem,
  }) async {
    try {
      final callable = _functions.httpsCallable('superFreteQuote');
      final res = await callable.call(<String, dynamic>{
        'lojaId': lojaId,
        'destinationCep': destinationCep,
        'peso': pesoGrams,
        'altura': altura,
        'largura': largura,
        'comprimento': comprimento,
        'valorDeclarado': valorDeclarado,
        if (cepOrigem != null && cepOrigem.isNotEmpty) 'cepOrigem': cepOrigem,
      }).timeout(const Duration(seconds: 25));

      final raw = res.data;
      if (raw is! Map) {
        return {'sucesso': false, 'erro': 'RESPOSTA_INVALIDA'};
      }
      final data = Map<String, dynamic>.from(raw);
      return {
        'sucesso': data['sucesso'] == true,
        'opcoes': data['opcoes'] ?? [],
        if (data['erro'] != null) 'erro': data['erro'],
      };
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[SuperFrete] quote (${e.code}) type=${e.runtimeType}');
      return {
        'sucesso': false,
        'erro': _friendlyMessage(e),
      };
    } catch (e) {
      debugPrint('[SuperFrete] quote falhou (type=${e.runtimeType})');
      return {
        'sucesso': false,
        'erro':
            'SuperFrete temporariamente indisponível. Tente novamente em alguns minutos.',
      };
    }
  }

  static Future<Map<String, dynamic>> createCheckout({
    required String lojaId,
    required dynamic servicoId,
    required Map<String, dynamic> from,
    required Map<String, dynamic> to,
    required Map<String, dynamic> package,
    required double valorDeclarado,
    String? pedidoRef,
  }) async {
    try {
      final callable = _functions.httpsCallable('superFreteCreateCheckout');
      final res = await callable.call(<String, dynamic>{
        'lojaId': lojaId,
        'servicoId': servicoId,
        'from': from,
        'to': to,
        'package': package,
        'valorDeclarado': valorDeclarado,
        if (pedidoRef != null && pedidoRef.isNotEmpty) 'pedidoRef': pedidoRef,
      }).timeout(const Duration(seconds: 30));
      final raw = res.data;
      return raw is Map
          ? Map<String, dynamic>.from(raw)
          : {'sucesso': false};
    } on FirebaseFunctionsException catch (e) {
      return {'sucesso': false, 'erro': _friendlyMessage(e)};
    } catch (e) {
      debugPrint('[SuperFrete] createCheckout falhou (type=${e.runtimeType})');
      return {
        'sucesso': false,
        'erro': 'Não foi possível criar envio na SuperFrete.',
      };
    }
  }
}
