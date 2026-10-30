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
    });

    test('falha mostra mensagem padrão', () {
      expect(
        ShippingExportService.statusLines('failed', provider: 'melhor_envio'),
        ['Não foi possível enviar este frete automaticamente.'],
      );
    });

    test('retry: falha sempre; incerto só no Melhor Envio (reconciliação)', () {
      expect(ShippingExportService.canRetry('failed', provider: 'superfrete'),
          isTrue);
      expect(
          ShippingExportService.canRetry('unknown', provider: 'melhor_envio'),
          isTrue);
      expect(ShippingExportService.canRetry('unknown', provider: 'superfrete'),
          isFalse);
      expect(
          ShippingExportService.canRetry('exported', provider: 'melhor_envio'),
          isFalse);
      expect(ShippingExportService.canRetry(null), isFalse);
    });

    test('conta não conectada orienta o lojista', () {
      expect(
        ShippingExportService.messageForErrorCode(
          'PROVIDER_ACCOUNT_NOT_CONNECTED',
          provider: 'melhor_envio',
        ),
        contains('Conecte a conta Melhor Envio'),
      );
    });

    test('serviço não contém endpoints nem cabeçalhos de provedor', () {
      final src =
          File('lib/services/shipping_export_service.dart').readAsStringSync();
      expect(src, contains("httpsCallable('retryShippingExport')"));
      expect(src, contains("httpsCallable('shippingGetAutomationConfig')"));
      expect(src, contains("httpsCallable('shippingSaveAutomationConfig')"));
      expect(src.contains('api.superfrete.com'), isFalse);
      expect(src.contains('melhorenvio.com.br'), isFalse);
      expect(src.contains('Authorization'), isFalse);
      expect(src.contains('Bearer'), isFalse);
    });
  });

  group('pre_pedidos_screen — seção ENVIO', () {
    late String src;
    setUp(() {
      src = File('lib/screens/pre_pedidos_screen.dart').readAsStringSync();
    });

    test('seção nova com retry e links oficiais na raiz do provedor', () {
      expect(src, contains('_buildShippingExportSection'));
      expect(src, contains("'Tentar novamente'"));
      expect(src, contains("'Abrir no Melhor Envio'"));
      expect(src, contains("'Abrir na SuperFrete'"));
      expect(src, contains("'melhor_envio': 'https://melhorenvio.com.br/'"));
      expect(src, contains("'superfrete': 'https://superfrete.com/'"));
      expect(src, contains('Frete pago pelo cliente:'));
      expect(src, contains('Prazo informado:'));
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
    });
  });
}
