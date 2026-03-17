// lib/catalog/data/catalog_order_sink.dart
// Contrato: para onde o catálogo envia o pedido.
// Hoje: Firestore + lógica MasterPalm. Amanhã: POST para API MasterPalm.

/// Destino do pedido (registro de venda). Implementações: Firestore ou API.
abstract class CatalogOrderSink {
  /// Envia o pedido. Payload tipicamente: itens, cliente, frete, cupom, etc.
  Future<void> submitOrder(
    String lojaId,
    Map<String, dynamic> orderPayload,
  );
}
