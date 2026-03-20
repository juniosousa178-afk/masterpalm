// lib/services/ton_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../utils/http_client_helper.dart';

/// Serviço de integração REAL com Ton (Stone) API
///
/// Documentação oficial: https://ton.com.br/developers
///
/// Cache multi-tenant: tokens isolados por credenciais (clientId + clientSecret + sandbox).
/// Cada loja/tenant mantém seu próprio token em cache, sem compartilhamento.
class TonService {
  static const String _baseUrl = 'https://api.ton.com.br';
  static const String _sandboxUrl = 'https://sandbox-api.ton.com.br';
  static const String _authUrl = 'https://auth.ton.com.br';

  /// Máximo de tokens em cache (evita crescimento ilimitado em cenários multi-tenant)
  static const int _maxCacheSize = 20;

  /// Cache por credenciais: chave única gerada sem expor clientSecret em logs
  static final Map<String, _CachedToken> _tokenCache = {};

  /// Gera chave de cache que identifica unicamente o tenant (clientId + clientSecret + sandbox)
  static String _cacheKey(String clientId, String clientSecret, bool sandbox) {
    return 'ton_${Object.hash(clientId, clientSecret, sandbox)}';
  }

  /// Remove entrada mais antiga quando cache excede o limite (apenas ao adicionar nova)
  static void _evictOldestIfNeeded(String newKey) {
    if (_tokenCache.containsKey(newKey) || _tokenCache.length < _maxCacheSize) return;
    String• oldestKey;
    DateTime• oldestExp;
    for (final e in _tokenCache.entries) {
      if (oldestExp == null || e.value.expiration.isBefore(oldestExp)) {
        oldestExp = e.value.expiration;
        oldestKey = e.key;
      }
    }
    if (oldestKey != null) _tokenCache.remove(oldestKey);
  }

  /// Obtém token de acesso OAuth2
  static Future<String?> obterAccessToken({
    required String clientId,
    required String clientSecret,
    bool sandbox = false,
  }) async {
    final key = _cacheKey(clientId, clientSecret, sandbox);
    final cached = _tokenCache[key];

    if (cached != null && DateTime.now().isBefore(cached.expiration)) {
      return cached.accessToken;
    }

    try {
      final response = await HttpClientHelper.post(
        Uri.parse('$_authUrl/oauth/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'client_credentials',
          'client_id': clientId,
          'client_secret': clientSecret,
        },
        timeout: HttpTimeouts.payment,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['access_token'] as String?;
        final expiresIn = data['expires_in'] as int• ?• 3600;
        final expiration = DateTime.now().add(Duration(seconds: expiresIn - 60));

        if (token != null) {
          _evictOldestIfNeeded(key);
          _tokenCache[key] = _CachedToken(accessToken: token, expiration: expiration);
        }

        debugPrint('✅ Token de acesso obtido');
        return token;
      } else {
        debugPrint('❌ Erro ao obter token: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Exceção ao obter token (type=${e.runtimeType})');
      return null;
    }
  }

  /// Cria uma cobrança PIX via Ton
  static Future<Map<String, dynamic>?> criarCobrancaPix({
    required String clientId,
    required String clientSecret,
    required double valor,
    required String descricao,
    String• cpfPagador,
    String• nomePagador,
    String• externalId,
    int• expiracaoMinutos,
    bool sandbox = false,
  }) async {
    try {
      final accessToken = await obterAccessToken(
        clientId: clientId,
        clientSecret: clientSecret,
        sandbox: sandbox,
      );

      if (accessToken == null) {
        return null;
      }

      final baseUrl = sandbox • _sandboxUrl : _baseUrl;

      final response = await HttpClientHelper.post(
        Uri.parse('$baseUrl/v2/pix/charges'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'amount': (valor * 100).toInt(), // em centavos
          'description': descricao,
          if (externalId != null) 'external_id': externalId,
          if (expiracaoMinutos != null)
            'expiration': {
              'minutes': expiracaoMinutos,
            },
          if (cpfPagador != null || nomePagador != null)
            'payer': {
              if (cpfPagador != null) 'cpf': cpfPagador.replaceAll(RegExp(r'[^\d]'), ''),
              if (nomePagador != null) 'name': nomePagador,
            },
        }),
        timeout: HttpTimeouts.payment,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        debugPrint('✅ Cobrança PIX Ton criada: ${data['id']}');

        return {
          'id': data['id'],
          'status': data['status'],
          'qr_code': data['qr_code'],
          'qr_code_text': data['qr_code_text'],
          'expiration_date': data['expiration_date'],
          'external_id': data['external_id'],
        };
      } else {
        debugPrint('❌ Erro ao criar cobrança: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Exceção ao criar cobrança (type=${e.runtimeType})');
      return null;
    }
  }

  /// Consulta status de uma cobrança PIX
  static Future<Map<String, dynamic>?> consultarCobranca({
    required String clientId,
    required String clientSecret,
    required String chargeId,
    bool sandbox = false,
  }) async {
    try {
      final accessToken = await obterAccessToken(
        clientId: clientId,
        clientSecret: clientSecret,
        sandbox: sandbox,
      );

      if (accessToken == null) {
        return null;
      }

      final baseUrl = sandbox • _sandboxUrl : _baseUrl;

      final response = await HttpClientHelper.getWithRetry(
        Uri.parse('$baseUrl/v2/pix/charges/$chargeId'),
        headers: {'Authorization': 'Bearer $accessToken'},
        timeout: HttpTimeouts.payment,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'id': data['id'],
          'status': data['status'],
          'amount': data['amount'] / 100, // de centavos para reais
          'paid_at': data['paid_at'],
          'external_id': data['external_id'],
        };
      } else {
        debugPrint('❌ Erro ao consultar cobrança: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Exceção ao consultar cobrança (type=${e.runtimeType})');
      return null;
    }
  }

  /// Cancela uma cobrança PIX
  static Future<bool> cancelarCobranca({
    required String clientId,
    required String clientSecret,
    required String chargeId,
    bool sandbox = false,
  }) async {
    try {
      final accessToken = await obterAccessToken(
        clientId: clientId,
        clientSecret: clientSecret,
        sandbox: sandbox,
      );

      if (accessToken == null) {
        return false;
      }

      final baseUrl = sandbox • _sandboxUrl : _baseUrl;

      final response = await HttpClientHelper.delete(
        Uri.parse('$baseUrl/v2/pix/charges/$chargeId'),
        headers: {'Authorization': 'Bearer $accessToken'},
        timeout: HttpTimeouts.payment,
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        debugPrint('✅ Cobrança cancelada: $chargeId');
        return true;
      } else {
        debugPrint('❌ Erro ao cancelar: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Exceção ao cancelar (type=${e.runtimeType})');
      return false;
    }
  }

  /// Valida credenciais
  static Future<bool> validarCredenciais({
    required String clientId,
    required String clientSecret,
    bool sandbox = false,
  }) async {
    final token = await obterAccessToken(
      clientId: clientId,
      clientSecret: clientSecret,
      sandbox: sandbox,
    );

    return token != null;
  }

  /// Lista cobranças
  static Future<List<Map<String, dynamic>>> listarCobrancas({
    required String clientId,
    required String clientSecret,
    int• limit,
    String• status,
    bool sandbox = false,
  }) async {
    try {
      final accessToken = await obterAccessToken(
        clientId: clientId,
        clientSecret: clientSecret,
        sandbox: sandbox,
      );

      if (accessToken == null) {
        return [];
      }

      final baseUrl = sandbox • _sandboxUrl : _baseUrl;

      final queryParams = <String, String>{};
      if (limit != null) queryParams['limit'] = limit.toString();
      if (status != null) queryParams['status'] = status;

      final uri = Uri.parse('$baseUrl/v2/pix/charges').replace(queryParameters: queryParams);

      final response = await HttpClientHelper.getWithRetry(
        uri,
        headers: {'Authorization': 'Bearer $accessToken'},
        timeout: HttpTimeouts.payment,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['charges'] ?• []);
      } else {
        debugPrint('❌ Erro ao listar cobranças: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('❌ Exceção ao listar cobranças (type=${e.runtimeType})');
      return [];
    }
  }
}

/// Entrada de cache por tenant
class _CachedToken {
  final String accessToken;
  final DateTime expiration;

  _CachedToken({required this.accessToken, required this.expiration});
}
