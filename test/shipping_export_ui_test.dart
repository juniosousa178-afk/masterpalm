import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/shipping_export_service.dart';

void main() {
  group('ShippingExportService — textos', () {
    test('exportado no Melhor Envio aguarda compra da etiqueta', () {
      expect(
        ShippingExportService.statusLines('exported', provider: 'melhor_envio'),
        ['Enviado ao Melhor Envio', 'Aguardando compra da etiqueta'],
      );
      expect(
        ShippingExportService.statusLines('exported', provider: 'superfrete'),
        ['Enviado à SuperFrete', 'Aguardando compra da etiqueta'],
      );
      expect(
        ShippingExportService.statusLines(
          'exported',
          provider: 'melhor_envio',
          reconciledManually: true,
        ).first,
        'Envio confirmado pela loja no carrinho no Melhor Envio',
      );
    });

    test('falha mostra mensagem padrão', () {
      expect(
        ShippingExportService.statusLines('failed', provider: 'melhor_envio'),
        ['Não foi possível enviar este frete automaticamente.'],
      );
    });

    test('incerto: texto exigido, sem reenvio automático', () {
      expect(
        ShippingExportService.statusLines('unknown', provider: 'melhor_envio'),
        [
          'Não foi possível confirmar se o envio foi criado no Melhor Envio. '
              'Verifique o carrinho antes de tentar novamente.',
        ],
      );
      expect(
        ShippingExportService.uncertainMessage('superfrete'),
        contains('criado na SuperFrete'),
      );
    });

    test('retry direto só após falha; incerto exige decisão do lojista', () {
      expect(ShippingExportService.canRetry('failed'), isTrue);
      expect(ShippingExportService.canRetry('unknown'), isFalse);
      expect(ShippingExportService.canRetry('exported'), isFalse);
      expect(ShippingExportService.canRetry(null), isFalse);
      expect(ShippingExportService.needsResolution('unknown'), isTrue);
      expect(ShippingExportService.needsResolution('failed'), isFalse);
      expect(ShippingExportResolution.notInCart.wire, 'not_in_cart');
      expect(ShippingExportResolution.alreadyInCart.wire, 'already_in_cart');
    });

    test('mensagens orientam o lojista', () {
      expect(
        ShippingExportService.messageForErrorCode(
          'PROVIDER_ACCOUNT_NOT_CONNECTED',
          provider: 'melhor_envio',
        ),
        contains('Conecte a conta Melhor Envio'),
      );
      expect(
        ShippingExportService.messageForErrorCode(
          'PROVIDER_EXPORT_CONTRACT_NOT_VERIFIED',
          provider: 'superfrete',
        ),
        contains('em homologação'),
      );
      for (final code in [
        'SHIPPING_QUOTE_MISSING',
        'SHIPPING_QUOTE_EXPIRED',
        'SHIPPING_QUOTE_PRICE_MISMATCH',
        'SHIPPING_QUOTE_SERVICE_MISMATCH',
      ]) {
        expect(
          ShippingExportService.messageForErrorCode(code, provider: 'melhor_envio'),
          isNotEmpty,
          reason: code,
        );
      }
    });

    test('serviço não contém endpoints nem cabeçalhos de provedor', () {
      final src =
          File('lib/services/shipping_export_service.dart').readAsStringSync();
      expect(src, contains("httpsCallable('retryShippingExport')"));
      expect(src, contains("httpsCallable('shippingGetAutomationConfig')"));
      expect(src, contains("httpsCallable('shippingSaveAutomationConfig')"));
      expect(src, contains("'resolution': resolution.wire"));
      expect(src.contains('api.superfrete.com'), isFalse);
      expect(src.contains('melhorenvio.com.br'), isFalse);
      expect(src.contains('Authorization'), isFalse);
      expect(src.contains('Bearer'), isFalse);
      expect(src.contains('providerShipmentId'), isFalse,
          reason: 'ID do provedor nunca é enviado pelo cliente');
    });
  });

  group('pre_pedidos_screen — seção ENVIO', () {
    late String src;
    setUp(() {
      src = File('lib/screens/pre_pedidos_screen.dart').readAsStringSync();
    });

    test('seção nova com retry, resolução manual e links oficiais na raiz do provedor', () {
      expect(src, contains('_buildShippingExportSection'));
      expect(src, contains("'Tentar novamente'"));
      expect(src, contains("'Verificar carrinho'"));
      expect(src, contains("'Já está no carrinho'"));
      expect(src, contains("'Não está no carrinho — enviar'"));
      expect(src, contains('ShippingExportResolution.alreadyInCart'));
      expect(src, contains('ShippingExportResolution.notInCart'));
      expect(src, contains("'Abrir no Melhor Envio'"));
      expect(src, contains("'Abrir na SuperFrete'"));
      expect(src, contains("'melhor_envio': 'https://melhorenvio.com.br/'"));
      expect(src, contains("'superfrete': 'https://superfrete.com/'"));
      expect(src, contains('Frete pago pelo cliente:'));
      expect(src, contains('Prazo informado:'));
      expect(src.contains("frete['cotacao']"), isFalse);
    });

    test('seção legada continua para pedidos com shippingPreOrder', () {
      expect(src, contains('_buildShippingPreOrderSection(dados)'));
    });
  });

  group('fretes_cupons_screen — envio automático', () {
    test('card de automação usa callables, sem token no cliente', () {
      final screen =
          File('lib/screens/fretes_cupons_screen.dart').readAsStringSync();
      expect(screen, contains('ShippingAutomationCard(lojaId: _slug!)'));
      final card =
          File('lib/widgets/shipping_automation_card.dart').readAsStringSync();
      expect(card, contains('ShippingExportService.saveAutomationConfig'));
      expect(card, contains('ShippingExportService.getAutomationConfig'));
      expect(card.contains('FirebaseFirestore'), isFalse);
      expect(card.contains('token'), isFalse);
      expect(card, contains('A etiqueta não é comprada automaticamente.'));
      expect(card, contains('Pedidos pagos por Pix direto na chave da loja e pedidos feitos antes da ativação '));
      expect(card, contains("'não são enviados automaticamente.'"));
    });

    test('SuperFrete em homologação: só permite desligar', () {
      final card =
          File('lib/widgets/shipping_automation_card.dart').readAsStringSync();
      expect(card, contains('Em homologação — ainda não disponível.'));
      expect(card, contains("if (!_autoSuperFrete) 'superFrete': false"));
      expect(card.contains("'superFrete': _autoSuperFrete"), isFalse);
      expect(card, contains("'stateRegister': _stateRegisterCtrl.text.trim()"));
    });
  });
}
