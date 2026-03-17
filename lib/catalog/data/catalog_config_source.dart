// lib/catalog/data/catalog_config_source.dart
// Contrato: de onde o catálogo obtém tema, fretes, cupons, banners.
// Hoje: Firestore. Amanhã: API HTTP.

/// Fonte de config do catálogo (tema, fretes, cupons, mídia).
abstract class CatalogConfigSource {
  /// Stream do documento de config da loja.
  Stream<Map<String, dynamic>> watchConfig(String lojaId);

  /// Uma leitura pontual do config.
  Future<Map<String, dynamic>> getConfig(String lojaId);
}
