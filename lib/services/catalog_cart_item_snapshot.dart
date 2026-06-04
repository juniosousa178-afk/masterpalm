// Snapshot imutável de linha do carrinho / pré-pedido do catálogo público.
// Evita nome desatualizado no merge por id e incoerência nome × preço no checkout.

import '../screens/public_catalog/catalog_estoque_helper.dart';

/// Campos copiados do item recém-adicionado ao fundir linha existente no carrinho.
const _cartLineFieldsRefreshedOnMerge = <String>[
  'nome',
  'name',
  'preco',
  'price',
  'slug',
  'imageUrl',
  'url_foto',
  'image',
  'imagens',
  'percentualDescontoPix',
  'divideSemJuros',
  'maxParcelasSemJuros',
  'peso',
  'tipoEmbalagem',
  'variacaoExtraResumo',
  'extraValor',
  'variacaoExtra',
  'extraTipo',
  'itensComboComSelecao',
  'comboConfiguravelResumo',
];

/// Atualiza a linha já existente no carrinho com dados do último clique (mesma identidade).
void refreshCatalogCartLineFromAdd(
  Map<String, dynamic> existingLine,
  Map<String, dynamic> incoming,
) {
  for (final key in _cartLineFieldsRefreshedOnMerge) {
    if (incoming.containsKey(key)) {
      existingLine[key] = incoming[key];
    }
  }
}

/// Resolve produto publicado no catálogo por id/slug (mesma ordem que estoque).
Map<String, dynamic>? findCatalogProductForCartLine(
  List<Map<String, dynamic>> catalogProducts,
  Map<String, dynamic> line,
) {
  final id =
      (line['id'] ?? line['produtosId'] ?? line['productId'] ?? '').toString().trim();
  if (id.isEmpty) return null;
  return CatalogEstoqueHelper.findProductInList(catalogProducts, id);
}

/// Enriquece linha do carrinho antes do checkout: nome/preço alinhados ao catálogo atual + snapshots.
Map<String, dynamic> enrichCatalogCartLineSnapshot({
  required Map<String, dynamic> line,
  List<Map<String, dynamic>> catalogProducts = const [],
  String pagamento = '',
}) {
  final out = Map<String, dynamic>.from(line);
  final catalog = catalogProducts.isEmpty
      ? null
      : findCatalogProductForCartLine(catalogProducts, out);

  if (catalog != null) {
    final nomeCat = (catalog['nome'] ?? catalog['name'] ?? '').toString().trim();
    if (nomeCat.isNotEmpty) {
      out['nome'] = nomeCat;
      out['name'] = nomeCat;
    }
    final precoCat = catalog['preco'];
    if (precoCat is num && precoCat > 0) {
      out['preco'] = precoCat.toDouble();
    }
    final slugCat = (catalog['slug'] ?? '').toString().trim();
    if (slugCat.isNotEmpty) out['slug'] = slugCat;
  }

  final productId =
      (out['id'] ?? out['produtosId'] ?? out['productId'] ?? '').toString().trim();
  final nomeSnap = (out['nome'] ?? out['name'] ?? '').toString().trim();
  final precoBase = (out['preco'] as num?)?.toDouble() ??
      (out['price'] as num?)?.toDouble() ??
      0.0;
  final pctPix = (out['percentualDescontoPix'] as num?)?.toDouble() ?? 0.0;
  final isPix = pagamento.toUpperCase() == 'PIX';
  final precoPix = (isPix && pctPix > 0)
      ? precoBase * (1 - pctPix / 100)
      : precoBase;

  if (productId.isNotEmpty) {
    out['productId'] = productId;
    out['id'] = productId;
    out['produtosId'] = out['produtosId'] ?? productId;
  }
  if (nomeSnap.isNotEmpty) {
    out['nomeSnapshot'] = nomeSnap;
    out['nome'] = nomeSnap;
    out['name'] = nomeSnap;
  }
  out['precoUnitarioSnapshot'] = precoBase;
  if (isPix) out['precoPixSnapshot'] = precoPix;

  return out;
}

List<Map<String, dynamic>> prepareCatalogCheckoutCartItems({
  required List<Map<String, dynamic>> cartLines,
  List<Map<String, dynamic>> catalogProducts = const [],
  String pagamento = '',
}) {
  return cartLines
      .map(
        (line) => enrichCatalogCartLineSnapshot(
          line: line,
          catalogProducts: catalogProducts,
          pagamento: pagamento,
        ),
      )
      .toList(growable: false);
}

/// Parte do fingerprint de reutilização de pré-pedido (inclui nome para não reaproveitar pedido antigo).
String catalogCartFingerprintPart(Map<String, dynamic> line) {
  final id = '${line['id'] ?? line['produtosId'] ?? ''}';
  final q = CatalogEstoqueHelper.parseCartItemQuantidade(line['quantidade']);
  final tam = (line['tamanho'] ?? '').toString();
  final cor = (line['cor'] ?? '').toString();
  final ex = (line['extraValor'] ?? line['variacaoExtra'] ?? '').toString();
  final nome = (line['nomeSnapshot'] ?? line['nome'] ?? line['name'] ?? '')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');
  return '$id|$q|$tam|$cor|$ex|$nome';
}

/// Nome exibido no painel do lojista: prioriza snapshot gravado no pedido.
String catalogPedidoItemDisplayName(Map<String, dynamic> item) {
  final snap = (item['nomeSnapshot'] ?? '').toString().trim();
  if (snap.isNotEmpty) return snap;
  return (item['nome'] ?? item['name'] ?? '').toString().trim();
}
