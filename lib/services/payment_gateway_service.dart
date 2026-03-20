// lib/services/payment_gateway_service.dart
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'mercadopago_service.dart';
import 'pagseguro_service.dart';
import 'ton_service.dart';
import 'infinitepay_service.dart';

/// Serviço unificado de processamento de pagamentos
/// Gerencia todos os gateways de pagamento de forma transparente
class PaymentGatewayService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Cria um pagamento PIX usando o gateway configurado para a loja
  ///
  /// Retorna dados do PIX (QR Code, etc) ou null em caso de erro
  static Future<Map<String, dynamic>?> criarPagamentoPix({
    required String lojaId,
    required double valor,
    required String descricao,
    String? cpfPagador,
    String? nomePagador,
    String? emailPagador,
    String? referencia,
    int? expiracaoMinutos,
  }) async {
    try {
      // 1. Carregar configurações de pagamento da loja
      final configDoc = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('config')
          .doc('payments')
          .get();

      if (!configDoc.exists) {
        debugPrint('❌ Configurações de pagamento não encontradas para loja: $lojaId');
        return null;
      }

      final config = configDoc.data()!;
      final checkout = config['checkout'] as Map<String, dynamic>?;
      final gateway = checkout?['gateway'] ?? checkout?['gatewayPadrao'] ?? 'whatsapp';

      debugPrint('🔹 Gateway selecionado: $gateway');

      // 2. Processar pagamento de acordo com o gateway
      switch (gateway) {
        case 'mp':
          return await _processarMercadoPago(
            config: config,
            valor: valor,
            descricao: descricao,
            email: emailPagador,
            cpf: cpfPagador,
            externalReference: referencia,
          );

        case 'pagseguro':
          return await _processarPagSeguro(
            config: config,
            valor: valor,
            descricao: descricao,
            cpf: cpfPagador,
            nome: nomePagador,
            email: emailPagador,
            referencia: referencia,
            expiracaoMinutos: expiracaoMinutos,
          );

        case 'ton':
          return await _processarTon(
            config: config,
            valor: valor,
            descricao: descricao,
            cpf: cpfPagador,
            nome: nomePagador,
            externalId: referencia,
            expiracaoMinutos: expiracaoMinutos,
          );

        case 'infinitepay':
          return await _processarInfinitePay(
            config: config,
            valor: valor,
            descricao: descricao,
            cpf: cpfPagador,
            nome: nomePagador,
            email: emailPagador,
            referencia: referencia,
            expiracaoMinutos: expiracaoMinutos,
          );

        case 'whatsapp':
        default:
          debugPrint('⚠️  Gateway WhatsApp - pagamento manual via PIX');
          // Retorna chave PIX manual
          final chavePix = checkout?['pixKey'] ?? checkout?['chavePix'];
          if (chavePix != null && chavePix.toString().isNotEmpty) {
            return {
              'gateway': 'pix_manual',
              'chave_pix': chavePix,
              'valor': valor,
              'descricao': descricao,
            };
          }
          return null;
      }
    } catch (e) {
      debugPrint('❌ Erro ao criar pagamento PIX (type=${e.runtimeType})');
      return null;
    }
  }

  /// Processa pagamento via Mercado Pago
  static Future<Map<String, dynamic>?> _processarMercadoPago({
    required Map<String, dynamic> config,
    required double valor,
    required String descricao,
    String? email,
    String? cpf,
    String? externalReference,
  }) async {
    final mp = config['mp'] as Map<String, dynamic>?;
    final accessToken = mp?['access_token'] ?? mp?['token'];

    if (accessToken == null || accessToken.toString().isEmpty) {
      debugPrint('❌ Token do Mercado Pago não configurado');
      return null;
    }

    final result = await MercadoPagoService.criarPagamentoPix(
      accessToken: accessToken.toString(),
      valor: valor,
      descricao: descricao,
      email: email,
      cpf: cpf,
      externalReference: externalReference,
    );

    if (result != null) {
      result['gateway'] = 'mercadopago';
    }

    return result;
  }

  /// Processa pagamento via PagSeguro
  static Future<Map<String, dynamic>?> _processarPagSeguro({
    required Map<String, dynamic> config,
    required double valor,
    required String descricao,
    String? cpf,
    String? nome,
    String? email,
    String? referencia,
    int? expiracaoMinutos,
  }) async {
    final pagseguro = config['pagseguro'] as Map<String, dynamic>?;
    final token = pagseguro?['token'];

    if (token == null || token.toString().isEmpty) {
      debugPrint('❌ Token do PagSeguro não configurado');
      return null;
    }

    // Formatar dados do cliente
    final customer = cpf != null && nome != null && email != null
        ? PagSeguroService.formatarCliente(
            nome: nome,
            email: email,
            cpf: cpf,
          )
        : {
            'name': 'Cliente',
            'email': 'cliente@email.com',
            'tax_id': '00000000000',
          };

    final result = await PagSeguroService.criarCobrancaPix(
      token: token.toString(),
      valor: valor,
      descricao: descricao,
      customer: customer,
      referencia: referencia,
      expiracaoSegundos: expiracaoMinutos != null ? expiracaoMinutos * 60 : null,
    );

    if (result != null) {
      result['gateway'] = 'pagseguro';
    }

    return result;
  }

  /// Processa pagamento via Ton
  static Future<Map<String, dynamic>?> _processarTon({
    required Map<String, dynamic> config,
    required double valor,
    required String descricao,
    String? cpf,
    String? nome,
    String? externalId,
    int? expiracaoMinutos,
  }) async {
    final ton = config['ton'] as Map<String, dynamic>?;
    final clientId = ton?['client_id'];
    final clientSecret = ton?['client_secret'];

    if (clientId == null || clientSecret == null ||
        clientId.toString().isEmpty || clientSecret.toString().isEmpty) {
      debugPrint('❌ Credenciais da Ton não configuradas');
      return null;
    }

    final result = await TonService.criarCobrancaPix(
      clientId: clientId.toString(),
      clientSecret: clientSecret.toString(),
      valor: valor,
      descricao: descricao,
      cpfPagador: cpf,
      nomePagador: nome,
      externalId: externalId,
      expiracaoMinutos: expiracaoMinutos,
    );

    if (result != null) {
      result['gateway'] = 'ton';
    }

    return result;
  }

  /// Processa pagamento via InfinitePay
  static Future<Map<String, dynamic>?> _processarInfinitePay({
    required Map<String, dynamic> config,
    required double valor,
    required String descricao,
    String? cpf,
    String? nome,
    String? email,
    String? referencia,
    int? expiracaoMinutos,
  }) async {
    final infinitepay = config['infinitpay'] as Map<String, dynamic>?;
    final apiKey = infinitepay?['api_key'];

    if (apiKey == null || apiKey.toString().isEmpty) {
      debugPrint('❌ API Key do InfinitePay não configurada');
      return null;
    }

    final result = await InfinitePayService.criarCobrancaPix(
      apiKey: apiKey.toString(),
      valor: valor,
      descricao: descricao,
      cpfPagador: cpf,
      nomePagador: nome,
      emailPagador: email,
      referencia: referencia,
      expiracaoMinutos: expiracaoMinutos,
    );

    if (result != null) {
      result['gateway'] = 'infinitepay';
    }

    return result;
  }

  /// Consulta status de um pagamento
  static Future<Map<String, dynamic>?> consultarPagamento({
    required String lojaId,
    required String gateway,
    required String paymentId,
  }) async {
    try {
      final configDoc = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('config')
          .doc('payments')
          .get();

      if (!configDoc.exists) {
        return null;
      }

      final config = configDoc.data()!;

      switch (gateway) {
        case 'mercadopago':
        case 'mp':
          final mp = config['mp'] as Map<String, dynamic>?;
          final accessToken = mp?['access_token'] ?? mp?['token'];
          if (accessToken != null) {
            return await MercadoPagoService.consultarPagamento(
              accessToken: accessToken.toString(),
              paymentId: paymentId,
            );
          }
          break;

        case 'pagseguro':
          final pagseguro = config['pagseguro'] as Map<String, dynamic>?;
          final token = pagseguro?['token'];
          if (token != null) {
            return await PagSeguroService.consultarCobranca(
              token: token.toString(),
              chargeId: paymentId,
            );
          }
          break;

        case 'ton':
          final ton = config['ton'] as Map<String, dynamic>?;
          final clientId = ton?['client_id'];
          final clientSecret = ton?['client_secret'];
          if (clientId != null && clientSecret != null) {
            return await TonService.consultarCobranca(
              clientId: clientId.toString(),
              clientSecret: clientSecret.toString(),
              chargeId: paymentId,
            );
          }
          break;

        case 'infinitepay':
          final infinitepay = config['infinitpay'] as Map<String, dynamic>?;
          final apiKey = infinitepay?['api_key'];
          if (apiKey != null) {
            return await InfinitePayService.consultarPagamento(
              apiKey: apiKey.toString(),
              paymentId: paymentId,
            );
          }
          break;
      }

      return null;
    } catch (e) {
      debugPrint('❌ Erro ao consultar pagamento (type=${e.runtimeType})');
      return null;
    }
  }

  /// Valida configurações de pagamento de uma loja
  static Future<Map<String, bool>> validarConfiguracoes({
    required String lojaId,
  }) async {
    final result = <String, bool>{
      'mercadopago': false,
      'pagseguro': false,
      'ton': false,
      'infinitepay': false,
    };

    try {
      final configDoc = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('config')
          .doc('payments')
          .get();

      if (!configDoc.exists) {
        return result;
      }

      final config = configDoc.data()!;

      // Mercado Pago
      final mp = config['mp'] as Map<String, dynamic>?;
      final mpToken = mp?['access_token'] ?? mp?['token'];
      if (mpToken != null && mpToken.toString().isNotEmpty) {
        result['mercadopago'] = await MercadoPagoService.validarCredenciais(
          accessToken: mpToken.toString(),
        );
      }

      // PagSeguro
      final pagseguro = config['pagseguro'] as Map<String, dynamic>?;
      final psToken = pagseguro?['token'];
      if (psToken != null && psToken.toString().isNotEmpty) {
        result['pagseguro'] = await PagSeguroService.validarToken(
          token: psToken.toString(),
        );
      }

      // Ton
      final ton = config['ton'] as Map<String, dynamic>?;
      final tonClientId = ton?['client_id'];
      final tonClientSecret = ton?['client_secret'];
      if (tonClientId != null && tonClientSecret != null) {
        result['ton'] = await TonService.validarCredenciais(
          clientId: tonClientId.toString(),
          clientSecret: tonClientSecret.toString(),
        );
      }

      // InfinitePay
      final infinitepay = config['infinitpay'] as Map<String, dynamic>?;
      final ipApiKey = infinitepay?['api_key'];
      if (ipApiKey != null && ipApiKey.toString().isNotEmpty) {
        result['infinitepay'] = await InfinitePayService.validarApiKey(
          apiKey: ipApiKey.toString(),
        );
      }

      return result;
    } catch (e) {
      debugPrint('❌ Erro ao validar configurações (type=${e.runtimeType})');
      return result;
    }
  }
}
