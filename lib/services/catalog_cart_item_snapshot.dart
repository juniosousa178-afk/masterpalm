// Snapshot imutável de linha do carrinho / pré-pedido do catálogo público.
// Evita troca silenciosa de produto por lookup ambíguo (produtosId/slug).

import '../screens/public_catalog/catalog_cart_identity_trace.dart';
import '../screens/public_catalog/catalog_estoque_helper.dart';

/// Versão do contrato de item gravado no pré-pedido.
const int catalogCartItemSchemaVersion = 1;

/// Rejeição estrutural offline (aliases conflitantes, preço inválido, etc.).
class CatalogCartLineRejectedException implements Exception {
  CatalogCartLineRejectedException(this.code, [this.detail = '']);

  final String code;
  final String detail;

  @override
  String toString() =>
      'CatalogCartLineRejectedException($code${detail.isNotEmpty ? ': $detail' : ''})';
}

String _normCartField(dynamic v) => (v ?? '').toString().trim();

/// Primeiro alias de produto não vazio (prioridade: productId → id → produtosId).
String catalogCartLineFirstNonEmptyProductId(Map<String, dynamic> line) {
  for (final key in ['productId', 'id', 'produtosId']) {
    final v = _normCartField(line[key]);
    if (v.isNotEmpty) return v;
  }
  return '';
}

/// Coleta aliases brutos não vazios de produto (antes de canonicalizar).
Set<String> catalogCartLineRawProductIds(Map<String, dynamic> line) {
  final ids = <String>{};
  for (final key in ['id', 'produtosId', 'productId']) {
    final v = _normCartField(line[key]);
    if (v.isNotEmpty) ids.add(v);
  }
  return ids;
}

bool catalogCartLineIsFrozenHistorical(Map<String, dynamic> line) {
  final schema = line['schemaVersion'];
  if (schema is! int || schema < catalogCartItemSchemaVersion) return false;
  return _normCartField(line['nomeSnapshot']).isNotEmpty ||
      (line['precoUnitarioSnapshot'] is num);
}

/// Validação estrutural offline — executar **antes** de canonicalizar aliases.
/// Retorna código de rejeição ou `null` se OK.
/// [allowPartial]: incoming de merge pode omitir nome/preço (preservados na linha existente).
String? catalogCartLineStructuralRejectionCode(
  Map<String, dynamic> line, {
  bool allowPartial = false,
}) {
  final distinct = catalogCartLineRawProductIds(line);
  if (distinct.length > 1) return 'alias_conflict';
  if (distinct.isEmpty) return 'empty_identity';

  final frozenHistorical = catalogCartLineIsFrozenHistorical(line);

  final hasNomeKey = line.containsKey('nome') || line.containsKey('name');
  final nome = _normCartField(line['nome']).isNotEmpty
      ? _normCartField(line['nome'])
      : _normCartField(line['name']);
  final snapNome = _normCartField(line['nomeSnapshot']);
  if (!allowPartial || hasNomeKey) {
    if (nome.isEmpty && !(frozenHistorical && snapNome.isNotEmpty)) {
      return 'empty_nome';
    }
  }

  final hasPrecoKey =
      line.containsKey('preco') || line.containsKey('price');
  final precoRaw = line['preco'] ?? line['price'];
  final precoSnap = line['precoUnitarioSnapshot'];
  if (!allowPartial || hasPrecoKey) {
    if (precoRaw == null &&
        !(frozenHistorical && precoSnap is num && precoSnap >= 0)) {
      return 'invalid_preco';
    }
    if (precoRaw != null) {
      final preco = precoRaw is num
          ? precoRaw.toDouble()
          : double.tryParse(precoRaw.toString());
      if (preco == null || preco.isNaN || preco.isInfinite || preco < 0) {
        return 'invalid_preco';
      }
    }
  }

  if (!frozenHistorical &&
      line.containsKey('nomeSnapshot') &&
      (line.containsKey('nome') || line.containsKey('name'))) {
    if (snapNome.isNotEmpty && nome.isNotEmpty && snapNome != nome) {
      return 'snapshot_nome_conflict';
    }
  }

  if (line.containsKey('productIdSnapshot')) {
    final snapPid = _normCartField(line['productIdSnapshot']);
    final canon = catalogCartLineFirstNonEmptyProductId(line);
    if (snapPid.isNotEmpty && canon.isNotEmpty && snapPid != canon) {
      return 'snapshot_product_conflict';
    }
  }

  return null;
}

/// `true` se congelou; `false` se rejeitou (carrinho inalterado).
bool tryFreezeCatalogCartLineSnapshotOnAdd(Map<String, dynamic> line) {
  final code = catalogCartLineStructuralRejectionCode(line);
  if (code != null) return false;
  freezeCatalogCartLineSnapshotOnAdd(line);
  return true;
}

List<Map<String, dynamic>> filterStructurallyValidCatalogCartLines(
  Iterable<Map<String, dynamic>> lines, {
  void Function(String code, Map<String, dynamic> line, int index)? onRejected,
}) {
  return restoreCatalogCartLines(lines, onRejected: onRejected).validLines;
}

/// Resultado estruturado da restauração/validação offline do carrinho.
class CatalogCartRestoreResult {
  const CatalogCartRestoreResult({
    required this.validLines,
    required this.rejectedCount,
    required this.rejectionReasons,
    required this.rejectedLines,
  });

  final List<Map<String, dynamic>> validLines;
  final int rejectedCount;
  final List<String> rejectionReasons;
  final List<Map<String, dynamic>> rejectedLines;
}

CatalogCartRestoreResult restoreCatalogCartLines(
  Iterable<Map<String, dynamic>> lines, {
  void Function(String code, Map<String, dynamic> line, int index)? onRejected,
}) {
  final valid = <Map<String, dynamic>>[];
  final reasons = <String>[];
  final rejected = <Map<String, dynamic>>[];
  var index = 0;
  for (final line in lines) {
    final code = catalogCartLineStructuralRejectionCode(line);
    if (code != null) {
      onRejected?.call(code, line, index);
      reasons.add(code);
      rejected.add(line);
    } else {
      valid.add(line);
    }
    index++;
  }
  return CatalogCartRestoreResult(
    validLines: valid,
    rejectedCount: rejected.length,
    rejectionReasons: reasons,
    rejectedLines: rejected,
  );
}

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
  return catalogCartLineFirstNonEmptyProductId(line);
}

bool catalogCartLineHasFrozenSnapshot(Map<String, dynamic> line) {
  final schema = line['schemaVersion'];
  if (schema is int && schema >= catalogCartItemSchemaVersion) return true;
  return (line['nomeSnapshot'] ?? '').toString().trim().isNotEmpty;
}

/// Selo atômico produto+variação+preço no momento do commit (UI).
String catalogCartCommitSeal({
  required String productId,
  required String nome,
  required String tamanho,
  required String cor,
  required double preco,
}) {
  final pid = productId.trim();
  final n = nome.trim();
  final tam = tamanho.trim();
  final c = cor.trim();
  final p = preco.toStringAsFixed(4);
  return '$pid|$n|$tam|$c|$p';
}

/// Se campos da linha divergirem do selo de commit, restaura do selo.
void _reconcileCatalogLineWithCommitSeal(Map<String, dynamic> line) {
  final seal = (line['_catalogCommitSeal'] ?? '').toString().trim();
  if (seal.isEmpty) return;
  final parts = seal.split('|');
  if (parts.length < 5) return;
  final pid = parts[0].trim();
  final nome = parts[1];
  final tam = parts[2];
  final cor = parts[3];
  final preco = double.tryParse(parts[4]) ?? 0.0;
  final linePid = catalogCartLineCanonicalProductId(line);
  final lineNome = (line['nome'] ?? line['name'] ?? '').toString().trim();
  final lineTam = (line['tamanho'] ?? '').toString();
  final lineCor = (line['cor'] ?? '').toString();
  final linePreco = (line['preco'] as num?)?.toDouble() ?? 0.0;
  final mismatch = linePid != pid ||
      lineNome != nome.trim() ||
      lineTam != tam ||
      lineCor != cor ||
      (linePreco - preco).abs() > 0.001;
  if (!mismatch) return;
  line['productId'] = pid;
  line['id'] = pid;
  line['produtosId'] = pid;
  line['firestoreDocId'] = pid;
  line['nome'] = nome;
  line['name'] = nome;
  line['tamanho'] = tam;
  line['cor'] = cor;
  line['preco'] = preco;
}

/// Congela snapshot no momento do add-to-cart (antes de checkout/enrich).
void freezeCatalogCartLineSnapshotOnAdd(Map<String, dynamic> line) {
  final rejection = catalogCartLineStructuralRejectionCode(line);
  if (rejection != null) {
    throw CatalogCartLineRejectedException(rejection);
  }
  _reconcileCatalogLineWithCommitSeal(line);
  final traceId = (line['_cartTraceId'] ?? '').toString().trim();
  if (traceId.isNotEmpty) {
    catalogCartIdentityTrace(
      CatalogCartIdentityTraceEvent(
        traceId: traceId,
        stage: 'before_freeze',
        sourcePath: 'before_freeze',
        productId: catalogCartLineCanonicalProductId(line),
        nome: (line['nome'] ?? line['name'] ?? '').toString(),
        preco: (line['preco'] as num?)?.toDouble(),
        tamanho: (line['tamanho'] ?? '').toString(),
        cor: (line['cor'] ?? '').toString(),
        extra: (line['extraValor'] ?? line['variacaoExtra'] ?? '').toString(),
        imagem: (line['imageUrl'] ?? line['url_foto'] ?? '').toString(),
      ),
    );
  }

  final productId = catalogCartLineCanonicalProductId(line);
  if (productId.isEmpty) return;

  line['productId'] = productId;
  line['id'] = productId;
  line['productIdSnapshot'] = productId;
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

  if (traceId.isNotEmpty) {
    catalogCartIdentityTrace(
      CatalogCartIdentityTraceEvent(
        traceId: traceId,
        stage: 'after_freeze',
        sourcePath: 'after_freeze',
        productId: productId,
        nome: (line['nomeSnapshot'] ?? line['nome'] ?? '').toString(),
        preco: (line['precoUnitarioSnapshot'] as num?)?.toDouble() ??
            (line['preco'] as num?)?.toDouble(),
        tamanho: (line['tamanho'] ?? '').toString(),
        cor: (line['cor'] ?? '').toString(),
        extra: (line['extraValor'] ?? line['variacaoExtra'] ?? '').toString(),
        imagem: (line['imagemSnapshot'] ?? line['imageUrl'] ?? '').toString(),
      ),
    );
  }
}

/// Atualiza a linha já existente no carrinho com dados do último clique (mesma identidade).
void refreshCatalogCartLineFromAdd(
  Map<String, dynamic> existingLine,
  Map<String, dynamic> incoming,
) {
  final incomingReject = catalogCartLineStructuralRejectionCode(
    incoming,
    allowPartial: true,
  );
  if (incomingReject != null) {
    throw CatalogCartLineRejectedException(incomingReject);
  }
  final existIds = catalogCartLineRawProductIds(existingLine);
  final incIds = catalogCartLineRawProductIds(incoming);
  if (existIds.length == 1 &&
      incIds.length == 1 &&
      existIds.single != incIds.single) {
    throw CatalogCartLineRejectedException('merge_product_mismatch');
  }

  for (final key in _cartLineFieldsRefreshedOnMerge) {
    if (incoming.containsKey(key)) {
      existingLine[key] = incoming[key];
    }
  }
  existingLine.remove('nomeSnapshot');
  existingLine.remove('precoUnitarioSnapshot');
  existingLine.remove('imagemSnapshot');
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
