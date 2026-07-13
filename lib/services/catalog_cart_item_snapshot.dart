// Snapshot imutável de linha do carrinho / pré-pedido do catálogo público.
// Evita troca silenciosa de produto por lookup ambíguo (produtosId/slug).

import '../screens/public_catalog/catalog_estoque_helper.dart';

/// Versão do contrato de item gravado no pré-pedido.
const int catalogCartItemSchemaVersion = 1;

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

/// Identidade canônica da linha (Firestore doc id / productId estável).
String catalogCartLineCanonicalProductId(Map<String, dynamic> line) {
  return (line['productId'] ?? line['id'] ?? line['produtosId'] ?? '')
      .toString()
      .trim();
}

bool catalogCartLineHasFrozenSnapshot(Map<String, dynamic> line) {
  final schema = line['schemaVersion'];
  if (schema is int && schema >= catalogCartItemSchemaVersion) return true;
  return (line['nomeSnapshot'] ?? '').toString().trim().isNotEmpty;
}

/// Congela snapshot no momento do add-to-cart (antes de checkout/enrich).
void freezeCatalogCartLineSnapshotOnAdd(Map<String, dynamic> line) {
  final productId = catalogCartLineCanonicalProductId(line);
  if (productId.isEmpty) return;

  line['productId'] = productId;
  line['id'] = productId;
  line['firestoreDocId'] = (line['firestoreDocId'] ?? productId).toString().trim();
  line['produtosId'] = (line['produtosId'] ?? productId).toString().trim();

  final nome = (line['nome'] ?? line['name'] ?? '').toString().trim();
  if (nome.isNotEmpty) {
    line['nomeSnapshot'] = nome;
    line['nome'] = nome;
    line['name'] = nome;
  }

  final preco = (line['preco'] as num?)?.toDouble() ??
      (line['price'] as num?)?.toDouble();
  if (preco != null && preco > 0) {
    line['precoUnitarioSnapshot'] = preco;
    line['preco'] = preco;
  }

  final img = (line['imageUrl'] ?? line['url_foto'] ?? line['image'] ?? '')
      .toString()
      .trim();
  if (img.isNotEmpty) {
    line['imagemSnapshot'] = img;
  }

  line['schemaVersion'] = catalogCartItemSchemaVersion;
}

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
  freezeCatalogCartLineSnapshotOnAdd(existingLine);
}

/// Lookup estrito: apenas `p['id'] == productId` (sem produtosId/slug).
Map<String, dynamic>? findCatalogProductForCartLineStrict(
  List<Map<String, dynamic>> catalogProducts,
  String canonicalProductId,
) {
  final key = canonicalProductId.trim();
  if (key.isEmpty) return null;
  for (final p in catalogProducts) {
    final id = '${p['id'] ?? ''}'.trim();
    if (id.isNotEmpty && id == key) return p;
  }
  return null;
}

/// Resolve produto publicado no catálogo por id/slug (mesma ordem que estoque).
/// Uso legado — preferir [findCatalogProductForCartLineStrict] no checkout.
Map<String, dynamic>? findCatalogProductForCartLine(
  List<Map<String, dynamic>> catalogProducts,
  Map<String, dynamic> line,
) {
  final id = catalogCartLineCanonicalProductId(line);
  if (id.isEmpty) return null;
  return CatalogEstoqueHelper.findProductInList(catalogProducts, id);
}

/// Enriquece linha do carrinho antes do checkout: preserva snapshot congelado.
Map<String, dynamic> enrichCatalogCartLineSnapshot({
  required Map<String, dynamic> line,
  List<Map<String, dynamic>> catalogProducts = const [],
  String pagamento = '',
}) {
  final out = Map<String, dynamic>.from(line);
  final frozen = catalogCartLineHasFrozenSnapshot(out);
  final productId = catalogCartLineCanonicalProductId(out);

  if (productId.isNotEmpty) {
    out['productId'] = productId;
    out['id'] = productId;
    out['firestoreDocId'] =
        (out['firestoreDocId'] ?? productId).toString().trim();
    out['produtosId'] = (out['produtosId'] ?? productId).toString().trim();
  }

  if (frozen) {
    final nomeSnap = (out['nomeSnapshot'] ?? '').toString().trim();
    if (nomeSnap.isNotEmpty) {
      out['nome'] = nomeSnap;
      out['name'] = nomeSnap;
    }
    final precoSnap = (out['precoUnitarioSnapshot'] as num?)?.toDouble();
    if (precoSnap != null && precoSnap > 0) {
      out['preco'] = precoSnap;
    }
    final imgSnap = (out['imagemSnapshot'] ?? '').toString().trim();
    if (imgSnap.isNotEmpty) {
      out['imageUrl'] = imgSnap;
      out['url_foto'] = imgSnap;
    }
  } else if (catalogProducts.isNotEmpty && productId.isNotEmpty) {
    final catalog =
        findCatalogProductForCartLineStrict(catalogProducts, productId);
    if (catalog != null) {
      final nomeCat =
          (catalog['nome'] ?? catalog['name'] ?? '').toString().trim();
      if (nomeCat.isNotEmpty) {
        out['nome'] = nomeCat;
        out['name'] = nomeCat;
        out['nomeSnapshot'] = nomeCat;
      }
      final precoCat = catalog['preco'];
      if (precoCat is num && precoCat > 0) {
        out['preco'] = precoCat.toDouble();
        out['precoUnitarioSnapshot'] = precoCat.toDouble();
      }
      final slugCat = (catalog['slug'] ?? '').toString().trim();
      if (slugCat.isNotEmpty) out['slug'] = slugCat;
      out['schemaVersion'] = catalogCartItemSchemaVersion;
    }
  }

  final nomeSnap =
      (out['nomeSnapshot'] ?? out['nome'] ?? out['name'] ?? '').toString().trim();
  final precoBase = (out['precoUnitarioSnapshot'] as num?)?.toDouble() ??
      (out['preco'] as num?)?.toDouble() ??
      (out['price'] as num?)?.toDouble() ??
      0.0;
  final pctPix = (out['percentualDescontoPix'] as num?)?.toDouble() ?? 0.0;
  final isPix = pagamento.toUpperCase() == 'PIX';
  final precoPix =
      (isPix && pctPix > 0) ? precoBase * (1 - pctPix / 100) : precoBase;

  if (nomeSnap.isNotEmpty) {
    out['nomeSnapshot'] = nomeSnap;
    out['nome'] = nomeSnap;
    out['name'] = nomeSnap;
  }
  out['precoUnitarioSnapshot'] = precoBase;
  if (isPix) out['precoPixSnapshot'] = precoPix;
  out['schemaVersion'] = out['schemaVersion'] ?? catalogCartItemSchemaVersion;

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
  final id = catalogCartLineCanonicalProductId(line);
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
