// lib/catalog/catalog_module.dart
// Barrel do módulo catálogo: contratos + implementação Firestore.
// O restante do app importa daqui quando for usar o catálogo de forma desacoplada.

export 'data/catalog_product_source.dart';
export 'data/catalog_config_source.dart';
export 'data/catalog_order_sink.dart';
export 'data/firestore_catalog_impl.dart';
