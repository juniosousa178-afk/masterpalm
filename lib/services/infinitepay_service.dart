// lib/services/infinitepay_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Serviço de integração REAL com InfinitePay API
///
/// Documentação oficial: https://developers.infinitepay.io
class InfinitePayService {
  static const String _baseUrl = 'https://api.infinitepay.io';
  static const String _sandboxUrl = 'https://sandbox-api.infinitepay.io';

  /// Cria uma cobrança PIX via InfinitePay
  static Future<Map<String, dynamic>?> criarCobrancaPix({
    required String apiKey,
    required double valor,
    required String descricao,
    String? cpfPagador,
    String? nomePagador,
    String? emailPagador,
    String? referencia,
    int? expiracaoMinutos,
    bool sandbox = false,
  }) async {
    try {
      final baseUrl = sandbox ? _sandboxUrl : _baseUrl;

      final response = await http.post(
        Uri.parse('$baseUrl/v2/payments/pix'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'amount': (valor * 100).toInt(), // em centavos
          'description': descricao,
          if (referencia != null) 'reference': referencia,
          if (expiracaoMinutos != null)
            'expiration_time': DateTime.now()
                .add(Duration(minutes: expiracaoMinutos))
                .toIso8601String(),
          if (cpfPagador != null || nomePagador != null || emailPagador != null)
            'payer': {
              if (cpfPagador != null) 'document': cpfPagador.replaceAll(RegExp(r'[^\d]'), ''),
              if (nomePagador != null) 'name': nomePagador,
              if (emailPagador != null) 'email': emailPagador,
            },
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        debugPrint('✅ Cobrança PIX InfinitePay criada: ${data['id']}');

        return {
          'id': data['id'],
          'status': data['status'],
          'qr_code': data['pix']?['qr_code'],
          'qr_code_base64': data['pix']?['qr_code_base64'],
          'expiration_date': data['pix']?['expiration_date'],
          'reference': data['reference'],
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

  /// Cria um link de pagamento (checkout)
  static Future<Map<String, dynamic>?> criarLinkPagamento({
    required String apiKey,
    required double valor,
    required String descricao,
    List<String>? metodosPermitidos,
    String? referencia,
    Map<String, dynamic>? customer,
    Map<String, dynamic>? urlsRedirecionamento,
    bool sandbox = false,
  }) async {
    try {
      final baseUrl = sandbox ? _sandboxUrl : _baseUrl;

      final response = await http.post(
        Uri.parse('$baseUrl/v2/payment-links'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'amount': (valor * 100).toInt(),
          'description': descricao,
          if (referencia != null) 'reference': referencia,
          if (metodosPermitidos != null) 'allowed_methods': metodosPermitidos,
          if (customer != null) 'customer': customer,
          if (urlsRedirecionamento != null) 'redirect_urls': urlsRedirecionamento,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        debugPrint('✅ Link de pagamento criado: ${data['id']}');

        return {
          'id': data['id'],
          'url': data['url'],
          'short_url': data['short_url'],
          'reference': data['reference'],
        };
      } else {
        debugPrint('❌ Erro ao criar link: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Exceção ao criar link (type=${e.runtimeType})');
      return null;
    }
  }

  /// Consulta status de um pagamento
  static Future<Map<String, dynamic>?> consultarPagamento({
    required String apiKey,
    required String paymentId,
    bool sandbox = false,
  }) async {
    try {
      final baseUrl = sandbox ? _sandboxUrl : _baseUrl;

      final response = await http.get(
        Uri.parse('$baseUrl/v2/payments/$paymentId'),
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'id': data['id'],
          'status': data['status'],
          'amount': data['amount'] / 100,
          'payment_method': data['payment_method'],
          'paid_at': data['paid_at'],
          'reference': data['reference'],
        };
      } else {
        debugPrint('❌ Erro ao consultar pagamento: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Exceção ao consultar pagamento (type=${e.runtimeType})');
      return null;
    }
  }

  /// Cancela um pagamento
  static Future<bool> cancelarPagamento({
    required String apiKey,
    required String paymentId,
    bool sandbox = false,
  }) async {
    try {
      final baseUrl = sandbox ? _sandboxUrl : _baseUrl;

      final response = await http.post(
        Uri.parse('$baseUrl/v2/payments/$paymentId/cancel'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        debugPrint('✅ Pagamento cancelado: $paymentId');
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

  /// Estorna um pagamento
  static Future<bool> estornarPagamento({
    required String apiKey,
    required String paymentId,
    double? valorParcial,
    bool sandbox = false,
  }) async {
    try {
      final baseUrl = sandbox ? _sandboxUrl : _baseUrl;

      final response = await http.post(
        Uri.parse('$baseUrl/v2/payments/$paymentId/refund'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          if (valorParcial != null) 'amount': (valorParcial * 100).toInt(),
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✅ Pagamento estornado: $paymentId');
        return true;
      } else {
        debugPrint('❌ Erro ao estornar: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Exceção ao estornar (type=${e.runtimeType})');
      return false;
    }
  }

  /// Valida API Key
  static Future<bool> validarApiKey({
    required String apiKey,
    bool sandbox = false,
  }) async {
    try {
      final baseUrl = sandbox ? _sandboxUrl : _baseUrl;

      final response = await http.get(
        Uri.parse('$baseUrl/v2/account'),
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ Erro ao validar API Key (type=${e.runtimeType})');
      return false;
    }
  }

  /// Obtém informações da conta
  static Future<Map<String, dynamic>?> obterInfoConta({
    required String apiKey,
    bool sandbox = false,
  }) async {
    try {
      final baseUrl = sandbox ? _sandboxUrl : _baseUrl;

      final response = await http.get(
        Uri.parse('$baseUrl/v2/account'),
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'id': data['id'],
          'name': data['name'],
          'document': data['document'],
          'email': data['email'],
        };
      }
      return null;
    } catch (e) {
      debugPrint('❌ Erro ao obter info da conta (type=${e.runtimeType})');
      return null;
    }
  }

  /// Lista pagamentos
  static Future<List<Map<String, dynamic>>> listarPagamentos({
    required String apiKey,
    int? limit,
    String? status,
    DateTime? dataInicio,
    DateTime? dataFim,
    bool sandbox = false,
  }) async {
    try {
      final baseUrl = sandbox ? _sandboxUrl : _baseUrl;

      final queryParams = <String, String>{};
      if (limit != null) queryParams['limit'] = limit.toString();
      if (status != null) queryParams['status'] = status;
      if (dataInicio != null) queryParams['start_date'] = dataInicio.toIso8601String();
      if (dataFim != null) queryParams['end_date'] = dataFim.toIso8601String();

      final uri = Uri.parse('$baseUrl/v2/payments').replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['payments'] ?? []);
      } else {
        debugPrint('❌ Erro ao listar pagamentos: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('❌ Exceção ao listar pagamentos (type=${e.runtimeType})');
      return [];
    }
  }
}
