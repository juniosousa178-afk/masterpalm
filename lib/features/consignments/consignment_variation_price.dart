import 'consignment_models.dart';

/// Shown when a variation price should exist but is missing, invalid or ambiguous.
const consignmentVariationPriceUnavailableMessage =
    'Não foi possível identificar o preço desta variação.';

enum ConsignmentUnitPriceSource {
  /// Product without variation: product price (unchanged behaviour).
  simpleProduct,

  /// `precoPorTamanho[size]` of the selected variation.
  variationPrice,

  /// Size has no own price; inherits the product price (same rule as
  /// `Produto.precoParaVariacao`, PDV and public catalog).
  inheritedProductPrice,

  unavailable,
}

class ConsignmentUnitPriceResult {
  const ConsignmentUnitPriceResult._(this.price, this.source);

  const ConsignmentUnitPriceResult.unavailable()
      : this._(null, ConsignmentUnitPriceSource.unavailable);

  final double? price;
  final ConsignmentUnitPriceSource source;

  bool get isAvailable => price != null;
}

/// Same normalization as `produtoNormalizarChavePrecoPorTamanho`.
String consignmentNormalizeSizePriceKey(String size) {
  final raw = size.trim();
  if (raw.isEmpty) return 'sem-tamanho';
  final lower = raw.toLowerCase();
  if (lower == 'sem-tamanho') return 'sem-tamanho';
  return lower.replaceAll(RegExp(r'\s+'), '');
}

double? _validMoney(dynamic raw) {
  final n = raw is num ? raw.toDouble() : double.tryParse('${raw ?? ''}'.trim());
  if (n == null || !n.isFinite || n <= 0) return null;
  return (n * 100).round() / 100;
}

/// Sanitized `precoPorTamanho` from a server/Firestore map. Invalid values are kept
/// as `null` so the resolver can fail closed for that size instead of dropping it.
Map<String, double?>? consignmentParseSizePrices(dynamic raw) {
  if (raw is! Map) return null;
  final out = <String, double?>{};
  for (final e in raw.entries) {
    final key = e.key.toString();
    if (key.trim().isEmpty) continue;
    out[key] = _validMoney(e.value);
  }
  return out;
}

/// Unit price snapshot for a new consignment line.
///
/// Never uses min/max/first of the size table: either the selected size price, the
/// documented product-price inheritance, or [ConsignmentUnitPriceResult.unavailable].
ConsignmentUnitPriceResult resolveConsignmentUnitPrice({
  required String productType,
  required double productPrice,
  required ConsignmentVariationKey variation,
  required bool sizePricesLoaded,
  Map<String, double?>? sizePrices,
}) {
  if (productType != 'variation' && productType != 'grade') {
    return ConsignmentUnitPriceResult._(productPrice, ConsignmentUnitPriceSource.simpleProduct);
  }
  if (!sizePricesLoaded) return const ConsignmentUnitPriceResult.unavailable();

  ConsignmentUnitPriceResult inherit() {
    final base = _validMoney(productPrice);
    return base == null
        ? const ConsignmentUnitPriceResult.unavailable()
        : ConsignmentUnitPriceResult._(base, ConsignmentUnitPriceSource.inheritedProductPrice);
  }

  if (sizePrices == null || sizePrices.isEmpty) return inherit();

  final size = variation.size.trim();
  final exactKey = size.isEmpty ? 'sem-tamanho' : size;
  if (sizePrices.containsKey(exactKey)) {
    final v = sizePrices[exactKey];
    return v == null
        ? const ConsignmentUnitPriceResult.unavailable()
        : ConsignmentUnitPriceResult._(v, ConsignmentUnitPriceSource.variationPrice);
  }

  final wanted = consignmentNormalizeSizePriceKey(size);
  final matches = [
    for (final e in sizePrices.entries)
      if (consignmentNormalizeSizePriceKey(e.key) == wanted) e.value,
  ];
  if (matches.isEmpty) return inherit();
  if (matches.any((v) => v == null)) return const ConsignmentUnitPriceResult.unavailable();
  final cents = matches.map((v) => (v! * 100).round()).toSet();
  if (cents.length != 1) return const ConsignmentUnitPriceResult.unavailable();
  return ConsignmentUnitPriceResult._(cents.single / 100, ConsignmentUnitPriceSource.variationPrice);
}

/// "Tam. 15 / Azul" — technical placeholders are hidden.
String consignmentVariationShortLabel(ConsignmentVariationKey vk) {
  bool technical(String v) {
    final n = v.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
    return n.isEmpty || n == 'sem-tamanho' || n == 'semtamanho' || n == 'sem-cor' || n == 'semcor';
  }

  return [
    if (!technical(vk.size)) 'Tam. ${vk.size.trim()}',
    if (!technical(vk.color)) vk.color.trim(),
    if (vk.extra.trim().isNotEmpty) vk.extra.trim(),
  ].join(' / ');
}
