// Identidade estável de Sale Intent para pré-pedido / pedido público (M3.2-D).

import '../services/sale_intent_service.dart';

/// `saleIntentId` derivado somente do [pedidoId] do pré-pedido.
abstract final class PrePedidoSaleIntent {
  static const idPrefix = 'pre_pedido:';

  static const origin = SaleIntentOrigins.prePedido;

  /// Ex.: `pre_pedido:abc-123-checkout`
  static String saleIntentIdForPedido(String pedidoId) {
    final id = pedidoId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(pedidoId, 'pedidoId', 'obrigatório');
    }
    return '$idPrefix$id';
  }
}
