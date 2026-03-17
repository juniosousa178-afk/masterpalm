// lib/services/pagseguro_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Serviço de integração REAL com PagSeguro API
///
/// Documentação oficial: https://dev.pagseguro.uol.com.br/reference/api-de-pagamentos
class PagSeguroService {
  // Ambiente de produção
  static const String _baseUrl = 'https://api.pagseguro.com';
  // Ambiente de sandbox
  static const String _sandboxUrl = 'https://sandbox.api.pagseguro.com';

  /// Cria uma ordem de pagamento (checkout transparente)
  static Future<Map<String, dynamic>?> criarOrdem({
    required String token,
    required List<Map<String, dynamic>> itens,
    required Map<String, dynamic> customer,
    double? freteValor,
    String? referencia,
    bool sandbox = false,
  }) async {
    try {
      final baseUrl = sandbox ? _sandboxUrl : _baseUrl;

      final response = await http.post(
        Uri.parse('$baseUrl/orders'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'reference_id': referencia ?? DateTime.now().millisecondsSinceEpoch.toString(),
          'customer': customer,
          'items': itens.map((item) => {
            'reference_id': item['id'],
            'name': item['nome'],
            'quantity': item['quantidade'],
            'unit_amount': (item['preco'] * 100).toInt(), // em centavos
          }).toList(),
          if (freteValor != null)
            'shipping': {
              'amount': (freteValor * 100).toInt(),
            },
          'notification_urls': [
            'https://app.mastepalm.com.br/webhooks/pagseguro',
          ],
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        debugPrint('✅ Ordem criada: ${data['id']}');
        return data;
      } else {
        debugPrint('❌ Erro ao criar ordem: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Exceção ao criar ordem (type=${e.runtimeType})');
      return null;
    }
  }

  /// Cria uma cobrança PIX via PagSeguro
  static Future<Map<String, dynamic>?> criarCobrancaPix({
    required String token,
    required double valor,
    required String descricao,
    required Map<String, dynamic> customer,
    String? referencia,
    int? expiracaoSegundos,
    bool sandbox = false,
  }) async {
    try {
      final baseUrl = sandbox ? _sandboxUrl : _baseUrl;

      final response = await http.post(
        Uri.parse('$baseUrl/charges'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'x-idempotency-key': DateTime.now().millisecondsSinceEpoch.toString(),
        },
        body: jsonEncode({
          'reference_id': referencia ?? DateTime.now().millisecondsSinceEpoch.toString(),
          'description': descricao,
          'amount': {
            'value': (valor * 100).toInt(), // em centavos
            'currency': 'BRL',
          },
          'payment_method': {
            'type': 'PIX',
            if (expiracaoSegundos != null)
              'pix': {
                'expiration_date': DateTime.now()
                    .add(Duration(seconds: expiracaoSegundos))
                    .toIso8601String(),
              },
          },
          'customer': customer,
          'notification_urls': [
            'https://app.mastepalm.com.br/webhooks/pagseguro',
          ],
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        debugPrint('✅ Cobrança PIX criada: ${data['id']}');

        return {
          'id': data['id'],
          'status': data['status'],
          'qr_code': data['qr_codes']?[0]?['text'],
          'qr_code_image': data['qr_codes']?[0]?['links']?[0]?['href'],
          'expiration_date': data['qr_codes']?[0]?['expiration_date'],
        };
      } else {
        debugPrint('❌ Erro ao criar cobrança PIX: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Exceção ao criar cobrança PIX (type=${e.runtimeType})');
      return null;
    }
  }

  /// Consulta status de uma cobrança
  static Future<Map<String, dynamic>?> consultarCobranca({
    required String token,
    required String chargeId,
    bool sandbox = false,
  }) async {
    try {
      final baseUrl = sandbox ? _sandboxUrl : _baseUrl;

      final response = await http.get(
        Uri.parse('$baseUrl/charges/$chargeId'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'id': data['id'],
          'status': data['status'],
          'amount': data['amount']?['value'] / 100, // de centavos para reais
          'paid_at': data['paid_at'],
          'reference_id': data['reference_id'],
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

  /// Cancela uma cobrança
  static Future<bool> cancelarCobranca({
    required String token,
    required String chargeId,
    bool sandbox = false,
  }) async {
    try {
      final baseUrl = sandbox ? _sandboxUrl : _baseUrl;

      final response = await http.post(
        Uri.parse('$baseUrl/charges/$chargeId/cancel'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
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

  /// Valida token de acesso
  static Future<bool> validarToken({
    required String token,
    bool sandbox = false,
  }) async {
    try {
      final baseUrl = sandbox ? _sandboxUrl : _baseUrl;

      final response = await http.get(
        Uri.parse('$baseUrl/public-keys/card'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ Erro ao validar token (type=${e.runtimeType})');
      return false;
    }
  }

  /// Formata dados do cliente para PagSeguro
  static Map<String, dynamic> formatarCliente({
    required String nome,
    required String email,
    required String cpf,
    String? telefone,
  }) {
    return {
      'name': nome,
      'email': email,
      'tax_id': cpf.replaceAll(RegExp(r'[^\d]'), ''),
      if (telefone != null)
        'phones': [
          {
            'country': '55',
            'area': telefone.substring(0, 2),
            'number': telefone.substring(2),
            'type': 'MOBILE',
          }
        ],
    };
  }
}
