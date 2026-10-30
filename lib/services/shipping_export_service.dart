// lib/services/shipping_export_service.dart
// Exportação automática do frete (carrinho Melhor Envio/SuperFrete) — feita no
// backend (onPrePedidoShippingExport). Aqui só leitura de estado, retry e config.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class ShippingExportService {
  ShippingExportService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'southamerica-east1');

  static const String exportFailedMessage =
      'Não foi possível enviar este frete automaticamente.';

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

  /// Linhas de status para a seção ENVIO do pedido.
  static List<String> statusLines(String? status, {String? provider}) {
    final label = providerLabel(provider);
    final destino = provider == 'superfrete' ? 'à $label' : 'ao $label';
    switch (status) {
      case 'exported':
        return ['Enviado $destino', 'Aguardando compra da etiqueta'];
      case 'exporting':
        return ['Enviando $destino...'];
      case 'failed':
        return [exportFailedMessage];
      case 'unknown':
        return [
          'Não foi possível confirmar se o envio foi criado $destino.',
          'Confira o painel $destino antes de tentar novamente.',
        ];
      case 'not_required':
        return ['Envio pela transportadora não necessário'];
      default:
        return ['Aguardando pagamento ou confirmação do pedido'];
    }
  }

  static bool canRetry(String? status, {String? provider}) {
    if (status == 'failed') return true;
    return status == 'unknown' && provider == 'melhor_envio';
  }

  static String messageForErrorCode(String? code, {String? provider}) {
    final label = providerLabel(provider);
    switch (code) {
      case 'PROVIDER_ACCOUNT_NOT_CONNECTED':
        return 'Conecte a conta $label da loja em Fretes e Cupons para enviar fretes automaticamente.';
      case 'LEGACY_TOKEN_NEEDS_ROTATION':
        return 'Por segurança, cadastre novamente o token $label em Fretes e Cupons.';
      case 'UNSUPPORTED_BY_CURRENT_API':
        return 'O envio automático para a $label ainda não está disponível. Crie o envio no painel da $label.';
      case 'SENDER_DATA_REQUIRED':
        return 'Complete os dados do remetente em Fretes e Cupons.';
      case 'SHIPPING_DOCUMENT_DATA_REQUIRED':
        return 'Informe a chave da nota fiscal ou use declaração de conteúdo nos dados do remetente.';
      case 'RECIPIENT_DATA_INCOMPLETE':
        return 'O endereço de entrega do cliente está incompleto.';
      case 'QUOTE_SNAPSHOT_MISSING':
        return 'Este pedido não tem os dados da cotação do frete. Crie o envio manualmente no painel da transportadora.';
      case 'PROVIDER_AUTH_FAILED':
        return 'A $label recusou o acesso. Verifique o token em Fretes e Cupons.';
      case 'PROVIDER_VALIDATION_FAILED':
        return 'A $label recusou os dados do envio. Confira o pedido e o remetente.';
      case 'PROVIDER_RATE_LIMITED':
        return 'Muitas tentativas em pouco tempo. Aguarde alguns minutos.';
      case 'PROVIDER_UNAVAILABLE':
      case 'PROVIDER_RESPONSE_INVALID':
        return 'A $label não respondeu como esperado.';
      default:
        return '';
    }
  }

  static Future<Map<String, dynamic>> retryExport({
    required String lojaId,
    required String orderId,
  }) async {
    try {
      final callable = _functions.httpsCallable('retryShippingExport');
      final res = await callable.call(<String, dynamic>{
        'lojaId': lojaId,
        'orderId': orderId,
      }).timeout(const Duration(seconds: 60));
      final raw = res.data;
      return raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{'ok': false};
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'permission-denied') {
        return {
          'ok': false,
          'message':
              'Sua conta não possui permissão para configurar fretes desta loja.',
        };
      }
      if (e.code == 'failed-precondition' || e.code == 'resource-exhausted') {
        return {'ok': false, 'message': e.message ?? exportFailedMessage};
      }
      return {'ok': false, 'message': exportFailedMessage};
    } catch (e) {
      debugPrint('[ShippingExport] retry falhou (type=${e.runtimeType})');
      return {'ok': false, 'message': exportFailedMessage};
    }
  }

  static Future<Map<String, dynamic>?> getAutomationConfig({
    required String lojaId,
  }) async {
    try {
      final callable = _functions.httpsCallable('shippingGetAutomationConfig');
      final res = await callable.call(<String, dynamic>{'lojaId': lojaId})
          .timeout(const Duration(seconds: 30));
      final raw = res.data;
      return raw is Map ? Map<String, dynamic>.from(raw) : null;
    } catch (e) {
      debugPrint(
        '[ShippingExport] getAutomationConfig falhou (type=${e.runtimeType})',
      );
      return null;
    }
  }

  static Future<Map<String, dynamic>> saveAutomationConfig({
    required String lojaId,
    Map<String, dynamic>? sender,
    Map<String, bool>? flags,
  }) async {
    try {
      final callable = _functions.httpsCallable('shippingSaveAutomationConfig');
      await callable.call(<String, dynamic>{
        'lojaId': lojaId,
        if (sender != null) 'sender': sender,
        if (flags != null) 'flags': flags,
      }).timeout(const Duration(seconds: 30));
      return {'ok': true};
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'permission-denied') {
        return {
          'ok': false,
          'message':
              'Sua conta não possui permissão para configurar fretes desta loja.',
        };
      }
      final details = e.details;
      if (details is Map && details['code'] == 'SENDER_DATA_REQUIRED') {
        return {
          'ok': false,
          'message':
              'Preencha nome, CPF ou CNPJ, CEP, endereço, número, bairro, cidade e UF do remetente.',
        };
      }
      return {'ok': false, 'message': 'Não foi possível salvar a configuração.'};
    } catch (e) {
      debugPrint(
        '[ShippingExport] saveAutomationConfig falhou (type=${e.runtimeType})',
      );
      return {'ok': false, 'message': 'Não foi possível salvar a configuração.'};
    }
  }
}
