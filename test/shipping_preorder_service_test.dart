import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShippingPreOrderService', () {
    test('mensagens seguras presentes', () {
      final source =
          File('lib/services/shipping_preorder_service.dart').readAsStringSync();
      expect(
        source,
        contains(
          'Alguns produtos ainda não possuem peso ou medidas para gerar o envio.',
        ),
      );
      expect(source, contains('retryShippingPreOrder'));
      expect(source, contains('confirmSuperFreteCartCreated'));
      expect(source, contains('external_state_unknown'));
      expect(source, contains('SUPERFRETE_PREORDER_SANDBOX_ONLY'));
      expect(
        source,
        contains(
          'Pré-pedido automático da SuperFrete está em homologação. O carrinho não foi criado automaticamente.',
        ),
      );
      expect(source, contains('Necessita conferência no painel SuperFrete'));
      expect(
        source,
        contains(
          'Confira o carrinho no painel da SuperFrete antes de qualquer nova ação.',
        ),
      );
      expect(source.contains('api.superfrete.com'), isFalse);
      expect(source.contains('melhorenvio.com.br'), isFalse);
      expect(source.contains('Authorization'), isFalse);
    });
  });

  group('pre_pedidos_screen — status SuperFrete', () {
    test('exibe ação manual sem retry para external_state_unknown', () {
      final source =
          File('lib/screens/pre_pedidos_screen.dart').readAsStringSync();
      expect(source, contains('Marcar como carrinho criado'));
      expect(source, contains('_confirmSuperFreteCartManual'));
      expect(source, contains('external_state_unknown'));
    });
  });

  group('pre_pedido_service — envio no backend', () {
    test('não chama FreteService.criarPrePedidoNaPlataforma', () {
      final source =
          File('lib/services/pre_pedido_service.dart').readAsStringSync();
      expect(source, contains('onPrePedidoShippingPreOrder'));
      expect(source.contains('criarPrePedidoNaPlataforma'), isFalse);
    });
  });
}
