// lib/catalog/data/catalog_product_source.dart
// Contrato: de onde o catálogo obtém a lista de produtos.
// Hoje: Firestore. Amanhã (APK separado): API HTTP.

/// Fonte de produtos do catálogo. Implementações: Firestore ou API.
abstract class CatalogProductSource {
  /// Stream de produtos publicados (live) da loja.
  Stream<List<Map<String, dynamic>>> watchProducts(
    String lojaId, {
    bool onlyLive = true,
  });

  /// Uma leitura pontual dos produtos.
  Future<List<Map<String, dynamic>>> getProducts(
    String lojaId, {
    bool onlyLive = true,
  });
}
