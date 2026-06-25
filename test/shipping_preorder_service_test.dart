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
      expect(
        source,
        contains('retryShippingPreOrder'),
      );
      expect(source.contains('api.superfrete.com'), isFalse);
      expect(source.contains('melhorenvio.com.br'), isFalse);
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
