// Identidade estável de Sale Intent para order review (M3.2-C).

/// `saleIntentId` derivado somente do [orderId] do pedido temporário.
abstract final class OrderReviewSaleIntent {
  static const idPrefix = 'order_review:';

  /// Ex.: `order_review:abc-123-temp`
  static String saleIntentIdForOrder(String orderId) {
    final id = orderId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(orderId, 'orderId', 'obrigatório');
    }
    return '$idPrefix$id';
  }
}
