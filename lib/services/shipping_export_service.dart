// lib/services/shipping_export_service.dart
// Exportação automática do frete (carrinho Melhor Envio/SuperFrete) — feita no
// backend (onPrePedidoShippingExport). Aqui só leitura de estado, retry e config.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Decisão do lojista depois de conferir o carrinho do provedor (resultado incerto).
enum ShippingExportResolution {
  /// Conferiu e o envio não está no carrinho → o servidor faz um novo envio.
  notInCart('not_in_cart'),

  /// O envio já está no carrinho → marca como enviado, sem novo envio.
  alreadyInCart('already_in_cart');

  const ShippingExportResolution(this.wire);
  final String wire;
}

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

  static String _no(String? provider) =>
      provider == 'superfrete' ? 'na ${providerLabel(provider)}' : 'no ${providerLabel(provider)}';

  /// Resultado incerto: nunca há reenvio automático.
  static String uncertainMessage(String? provider) =>
      'Não foi possível confirmar se o envio foi criado ${_no(provider)}. '
      'Verifique o carrinho antes de tentar novamente.';

  /// Linhas de status para a seção ENVIO do pedido.
  static List<String> statusLines(
    String? status, {
    String? provider,
    bool reconciledManually = false,
  }) {
    final label = providerLabel(provider);
    final destino = provider == 'superfrete' ? 'à $label' : 'ao $label';
    switch (status) {
      case 'exported':
        return [
          reconciledManually
              ? 'Envio confirmado pela loja no carrinho ${_no(provider)}'
              : 'Enviado $destino',
          'Aguardando compra da etiqueta',
        ];
      case 'exporting':
        return ['Enviando $destino...'];
      case 'failed':
        return [exportFailedMessage];
      case 'unknown':
        return [uncertainMessage(provider)];
      case 'not_required':
        return ['Envio pela transportadora não necessário'];
      default:
        return ['Aguardando pagamento ou confirmação do pedido'];
    }
  }

  /// Nova tentativa direta só após falha definitiva (nada foi criado no provedor).
  static bool canRetry(String? status) => status == 'failed';

  /// Resultado incerto: o lojista precisa conferir o carrinho e escolher uma ação.
  static bool needsResolution(String? status) => status == 'unknown';

  static String messageForErrorCode(String? code, {String? provider}) {
    final label = providerLabel(provider);
    switch (code) {
      case 'PROVIDER_ACCOUNT_NOT_CONNECTED':
        return 'Conecte a conta $label da loja em Fretes e Cupons para enviar fretes automaticamente.';
      case 'LEGACY_TOKEN_NEEDS_ROTATION':
        return 'Por segurança, cadastre novamente o token $label em Fretes e Cupons.';
      case 'PROVIDER_EXPORT_CONTRACT_NOT_VERIFIED':
        return 'O envio automático para a $label está em homologação. Crie o envio no painel da $label.';
      case 'SENDER_DATA_REQUIRED':
        return 'Complete os dados do remetente em Fretes e Cupons.';
      case 'SHIPPING_DOCUMENT_DATA_REQUIRED':
        return 'Para nota fiscal, informe a chave da NF no pedido e a inscrição estadual do remetente; ou use declaração de conteúdo.';
      case 'RECIPIENT_DATA_INCOMPLETE':
        return 'Os dados de entrega do cliente estão incompletos (CPF, número ou bairro).';
      case 'SHIPPING_QUOTE_MISSING':
      case 'SHIPPING_QUOTE_NOT_FOUND':
      case 'SHIPPING_QUOTE_STORE_MISMATCH':
        return 'Este pedido não tem uma cotação de frete válida. Crie o envio manualmente no painel da $label.';
      case 'SHIPPING_QUOTE_EXPIRED':
        return 'A cotação do frete deste pedido expirou. Crie o envio manualmente no painel da $label.';
      case 'SHIPPING_QUOTE_SERVICE_MISMATCH':
      case 'SHIPPING_QUOTE_DESTINATION_MISMATCH':
      case 'SHIPPING_QUOTE_ITEMS_MISMATCH':
      case 'SHIPPING_QUOTE_PRICE_MISMATCH':
      case 'SHIPPING_QUOTE_INSURANCE_MISMATCH':
      case 'SHIPPING_ORDER_TOTAL_INCONSISTENT':
        return 'O frete do pedido não confere com a cotação. Confira o pedido e crie o envio manualmente no painel da $label.';
      case 'PROVIDER_AUTH_FAILED':
        return 'A $label recusou o acesso. Verifique o token em Fretes e Cupons.';
      case 'PROVIDER_VALIDATION_FAILED':
        return 'A $label recusou os dados do envio. Confira o pedido e o remetente.';
      case 'PROVIDER_RATE_LIMITED':
        return 'Muitas tentativas em pouco tempo. Aguarde alguns minutos.';
      case 'PROVIDER_UNREACHABLE':
        return 'Não foi possível conectar à $label. Nada foi enviado; tente novamente.';
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
    ShippingExportResolution? resolution,
  }) async {
    try {
      final callable = _functions.httpsCallable('retryShippingExport');
      final res = await callable.call(<String, dynamic>{
        'lojaId': lojaId,
        'orderId': orderId,
        if (resolution != null) 'resolution': resolution.wire,
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
      if (details is Map &&
          details['code'] == 'PROVIDER_EXPORT_CONTRACT_NOT_VERIFIED') {
        return {
          'ok': false,
          'message':
              'O envio automático para a SuperFrete ainda está em homologação.',
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
