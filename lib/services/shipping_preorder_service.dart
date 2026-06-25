// lib/services/shipping_preorder_service.dart
// Pré-pedido de envio (carrinho) — somente retry administrativo via backend.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class ShippingPreOrderService {
  ShippingPreOrderService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'southamerica-east1');

  static String statusLabel(String? status) {
    switch (status) {
      case 'created':
        return 'Criado';
      case 'processing':
        return 'Aguardando criação';
      case 'needs_product_data':
        return 'Dados de produto pendentes';
      case 'failed':
        return 'Falhou ao criar';
      case 'pending':
        return 'Aguardando criação';
      default:
        return 'Aguardando criação';
    }
  }

  static String providerLabel(String? provider) {
    switch (provider) {
      case 'superfrete':
        return 'SuperFrete';
      case 'melhor_envio':
        return 'Melhor Envio';
      default:
        return 'Transportadora';
    }
  }

  static String messageForErrorCode(String? code) {
    switch (code) {
      case 'PRODUCT_SHIPPING_DATA_MISSING':
        return 'Alguns produtos ainda não possuem peso ou medidas para gerar o envio.';
      case 'ADDRESS_INCOMPLETE':
        return 'O endereço de entrega está incompleto.';
      case 'PROVIDER_NOT_CONFIGURED':
        return 'Configure a integração de frete antes de criar o pré-pedido.';
      case 'API_INDISPONIVEL':
        return 'A transportadora está temporariamente indisponível. Tente novamente mais tarde.';
      case 'RATE_LIMIT':
        return 'Muitas tentativas em pouco tempo. Aguarde alguns minutos.';
      case 'PRE_ORDER_FAILED':
        return 'Não foi possível criar o pré-pedido de envio.';
      case 'PRE_ORDER_CREATED':
        return 'Pré-pedido criado com sucesso.';
      case 'LEGACY_TOKEN_NEEDS_ROTATION':
        return 'Configure um novo token do Melhor Envio na tela de fretes antes de criar o pré-pedido.';
      case 'EXTERNAL_RECONCILIATION_UNAVAILABLE':
        return 'Criação automática de pré-pedido SuperFrete indisponível até suporte oficial de reconciliação externa.';
      default:
        return '';
    }
  }

  static Future<Map<String, dynamic>> retryPreOrder({
    required String lojaId,
    required String orderId,
  }) async {
    try {
      final callable = _functions.httpsCallable('retryShippingPreOrder');
      final res = await callable.call(<String, dynamic>{
        'lojaId': lojaId,
        'orderId': orderId,
      }).timeout(const Duration(seconds: 45));
      final raw = res.data;
      return raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{'ok': false};
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      if (details is Map) {
        final code = details['code']?.toString();
        final msg = messageForErrorCode(code);
        if (msg.isNotEmpty) {
          return {'ok': false, 'message': msg};
        }
      }
      if (e.code == 'permission-denied') {
        return {
          'ok': false,
          'message':
              'Sua conta não possui permissão para configurar fretes desta loja.',
        };
      }
      return {
        'ok': false,
        'message': 'Não foi possível criar o pré-pedido de envio.',
      };
    } catch (e) {
      debugPrint('[ShippingPreOrder] retry falhou (type=${e.runtimeType})');
      return {
        'ok': false,
        'message': 'Não foi possível criar o pré-pedido de envio.',
      };
    }
  }
}
