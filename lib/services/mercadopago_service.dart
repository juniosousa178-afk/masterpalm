// lib/services/mercadopago_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../utils/http_client_helper.dart';

/// Serviço de integração REAL com Mercado Pago API
///
/// Documentação oficial: https://www.mercadopago.com.br/developers/pt/docs
class MercadoPagoService {
  static const String _baseUrl = 'https://api.mercadopago.com';

  /// Cria uma preferência de pagamento (checkout)
  ///
  /// Retorna o init_point (URL para redirecionar o cliente)
  static Future<Map<String, dynamic>?> criarPreferencia({
    required String accessToken,
    required String titulo,
    required double valor,
    required int quantidade,
    int? maxInstallments,
    String? descricao,
    String? externalReference,
    String? lojaId,
    Map<String, dynamic>? payer,
    Map<String, dynamic>? backUrls,
  }) async {
    try {
      final response = await HttpClientHelper.post(
        Uri.parse('$_baseUrl/checkout/preferences'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'items': [
            {
              'title': titulo,
              'description': descricao ?? titulo,
              'quantity': quantidade,
              'currency_id': 'BRL',
              'unit_price': valor,
            }
          ],
          if (externalReference != null) 'external_reference': externalReference,
          if (lojaId != null && lojaId.isNotEmpty) 'metadata': {'lojaId': lojaId},
          if (payer != null) 'payer': payer,
          // Defaults genéricos; o catálogo público sempre envia [backUrls] com ?loja= e a CF mpCatalogPayment define notification_url.
          'back_urls': backUrls ?? {
            'success': 'https://app.mastepalm.com.br/pagamento/sucesso',
            'failure': 'https://app.mastepalm.com.br/pagamento/falha',
            'pending': 'https://app.mastepalm.com.br/pagamento/pendente',
          },
          'auto_return': 'approved',
          'statement_descriptor': 'MASTERPALM',
          'notification_url': 'https://app.mastepalm.com.br/webhooks/mercadopago',
          if (maxInstallments != null)
            'payment_methods': {
              'installments': maxInstallments.clamp(1, 24),
            },
        }),
        timeout: HttpTimeouts.payment,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        debugPrint('✅ Preferência criada: ${data['id']}');
        return {
          'id': data['id'],
          'init_point': data['init_point'],
          'sandbox_init_point': data['sandbox_init_point'],
        };
      } else {
        debugPrint('❌ Erro ao criar preferência: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Exceção ao criar preferência (type=${e.runtimeType})');
      return null;
    }
  }

  /// Cria um pagamento PIX via Mercado Pago
  ///
  /// Retorna QR Code e dados do PIX
  static Future<Map<String, dynamic>?> criarPagamentoPix({
    required String accessToken,
    required double valor,
    required String descricao,
    String? email,
    String? cpf,
    String? externalReference,
    String? lojaId,
  }) async {
    try {
      final response = await HttpClientHelper.post(
        Uri.parse('$_baseUrl/v1/payments'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
          'X-Idempotency-Key': DateTime.now().millisecondsSinceEpoch.toString(),
        },
        body: jsonEncode({
          'transaction_amount': valor,
          'description': descricao,
          'payment_method_id': 'pix',
          if (externalReference != null) 'external_reference': externalReference,
          if (lojaId != null && lojaId.isNotEmpty) 'metadata': {'lojaId': lojaId},
          'payer': {
            'email': email ?? 'cliente@mastepalm.com.br', // Email obrigatório
            if (cpf != null && cpf.isNotEmpty)
              'identification': {
                'type': 'CPF',
                'number': cpf.replaceAll(RegExp(r'[^\d]'), ''), // Remove formatação
              },
          },
        }),
        timeout: HttpTimeouts.payment,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        debugPrint('✅ Pagamento PIX criado: ${data['id']}');

        return {
          'id': data['id'],
          'status': data['status'],
          'qr_code': data['point_of_interaction']?['transaction_data']?['qr_code'],
          'qr_code_base64': data['point_of_interaction']?['transaction_data']?['qr_code_base64'],
          'ticket_url': data['point_of_interaction']?['transaction_data']?['ticket_url'],
        };
      } else {
        debugPrint('❌ Erro ao criar pagamento PIX: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Exceção ao criar pagamento PIX (type=${e.runtimeType})');
      return null;
    }
  }

  /// Consulta status de um pagamento
  static Future<Map<String, dynamic>?> consultarPagamento({
    required String accessToken,
    required String paymentId,
  }) async {
    try {
      final response = await HttpClientHelper.getWithRetry(
        Uri.parse('$_baseUrl/v1/payments/$paymentId'),
        headers: {'Authorization': 'Bearer $accessToken'},
        timeout: HttpTimeouts.payment,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'id': data['id'],
          'status': data['status'],
          'status_detail': data['status_detail'],
          'transaction_amount': data['transaction_amount'],
          'date_approved': data['date_approved'],
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

  /// Estorna um pagamento
  static Future<bool> estornarPagamento({
    required String accessToken,
    required String paymentId,
  }) async {
    try {
      final response = await HttpClientHelper.post(
        Uri.parse('$_baseUrl/v1/payments/$paymentId/refunds'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        timeout: HttpTimeouts.payment,
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

  /// Valida credenciais do Mercado Pago
  static Future<bool> validarCredenciais({
    required String accessToken,
  }) async {
    try {
      final response = await HttpClientHelper.getWithRetry(
        Uri.parse('$_baseUrl/users/me'),
        headers: {'Authorization': 'Bearer $accessToken'},
        timeout: HttpTimeouts.quick,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('✅ Credenciais válidas - Usuário: ${data['email']}');
        return true;
      } else {
        debugPrint('❌ Credenciais inválidas - Status: ${response.statusCode}');
        debugPrint('   Response: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Erro ao validar credenciais (type=${e.runtimeType})');
      return false;
    }
  }

  /// Obtém informações da conta
  static Future<Map<String, dynamic>?> obterInfoConta({
    required String accessToken,
  }) async {
    try {
      final response = await HttpClientHelper.getWithRetry(
        Uri.parse('$_baseUrl/users/me'),
        headers: {'Authorization': 'Bearer $accessToken'},
        timeout: HttpTimeouts.quick,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'id': data['id'],
          'email': data['email'],
          'nickname': data['nickname'],
          'first_name': data['first_name'],
          'last_name': data['last_name'],
        };
      }
      return null;
    } catch (e) {
      debugPrint('❌ Erro ao obter info da conta (type=${e.runtimeType})');
      return null;
    }
  }
}
