// Recovery-mode-only variation stock diagnostic (read-only, no mutations).
// Available only when SyncQueueRecoveryMode.isActive.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import '../core/hive_box_names.dart';
import '../core/produto_variacao_extra.dart';
import '../models/produto.dart';
import 'produto_stock_catalog_cadastro_sync.dart';
import 'sync_queue_recovery_mode.dart';
import 'sync_queue_service.dart';

/// Schema version for on-device diagnostic export.
const String kVariationStockRecoveryDiagnosticVersion = '1.0.0';

/// Same dart-define as app bootstrap (`CATALOG_BUILD_ID`).
const String kVariationStockDiagnosticClientBuildId = String.fromEnvironment(
  'CATALOG_BUILD_ID',
  defaultValue: 'dev',
);

const int kVariationStockDiagnosticMaxProducts = 80;
const int kVariationStockDiagnosticMaxQueueIntents = 40;

/// Thrown when diagnostic is requested outside recovery mode.
class VariationStockDiagnosticGuardException implements Exception {
  VariationStockDiagnosticGuardException(this.message);
  final String message;
  @override
  String toString() => message;
}

class VariationStockRecoveryDiagnosticSnapshot {
  const VariationStockRecoveryDiagnosticSnapshot({
    required this.diagnosticVersion,
    required this.capturedAtUtc,
    required this.recoveryMode,
    required this.clientWebVersion,
    required this.serverWebVersion,
    required this.storeId,
    required this.products,
    required this.queue,
    required this.summary,
  });

  final String diagnosticVersion;
  final String capturedAtUtc;
  final bool recoveryMode;
  final String clientWebVersion;
  final String? serverWebVersion;
  final String storeId;
  final List<VariationStockDiagnosticProduct> products;
  final List<VariationStockDiagnosticQueueIntent> queue;
  final VariationStockDiagnosticSummary summary;

  Map<String, dynamic> toJson() => {
        'diagnosticVersion': diagnosticVersion,
        'capturedAt': capturedAtUtc,
        'recoveryMode': recoveryMode,
        'clientWebVersion': clientWebVersion,
        'serverWebVersion': serverWebVersion,
        'storeId': storeId,
        'products': products.map((e) => e.toJson()).toList(),
        'queue': queue.map((e) => e.toJson()).toList(),
        'summary': summary.toJson(),
      };

  String toPrettyJson() {
    final tree = VariationStockRecoveryDiagnosticBuilder.redactSecrets(toJson());
    return const JsonEncoder.withIndent('  ').convert(tree);
  }
}

class VariationStockDiagnosticSummary {
  const VariationStockDiagnosticSummary({
    required this.variableProductCount,
    required this.zeroQtyProductCount,
    required this.missingQtyProductCount,
    required this.representationMismatchCount,
    required this.priceKeyWithoutStockKeyCount,
    required this.pendingProductIntentCount,
    required this.staleIntentCount,
  });

  final int variableProductCount;
  final int zeroQtyProductCount;
  final int missingQtyProductCount;
  final int representationMismatchCount;
  final int priceKeyWithoutStockKeyCount;
  final int pendingProductIntentCount;
  final int staleIntentCount;

  Map<String, dynamic> toJson() => {
        'variableProductCount': variableProductCount,
        'zeroQtyProductCount': zeroQtyProductCount,
        'missingQtyProductCount': missingQtyProductCount,
        'representationMismatchCount': representationMismatchCount,
        'priceKeyWithoutStockKeyCount': priceKeyWithoutStockKeyCount,
        'pendingProductIntentCount': pendingProductIntentCount,
        'staleIntentCount': staleIntentCount,
      };
}

class VariationStockDiagnosticProduct {
  const VariationStockDiagnosticProduct({
    required this.productId,
    required this.hiveKey,
    required this.nameFingerprint,
    required this.stockRevision,
    required this.usaVariacoes,
    required this.baseEstoque,
    required this.variationCount,
    required this.variations,
    required this.estoquePorTamanho,
    required this.precoPorTamanhoKeys,
    required this.hasZeroVariationQty,
    required this.hasMissingVariationQty,
    required this.hasStockMapWithPositiveQty,
    required this.hasPriceKeyWithoutStockKey,
    required this.representationMismatch,
  });

  final String productId;
  final int? hiveKey;
  final String nameFingerprint;
  final int stockRevision;
  final bool usaVariacoes;
  final int baseEstoque;
  final int variationCount;
  final List<VariationStockDiagnosticCell> variations;
  final Map<String, int> estoquePorTamanho;
  final List<String> precoPorTamanhoKeys;
  final bool hasZeroVariationQty;
  final bool hasMissingVariationQty;
  final bool hasStockMapWithPositiveQty;
  final bool hasPriceKeyWithoutStockKey;
  final bool representationMismatch;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        if (hiveKey != null) 'hiveKey': hiveKey,
        'nameFingerprint': nameFingerprint,
        'stockRevision': stockRevision,
        'usaVariacoes': usaVariacoes,
        'baseEstoque': baseEstoque,
        'variationCount': variationCount,
        'variations': variations.map((e) => e.toJson()).toList(),
        'estoquePorTamanho': estoquePorTamanho,
        'precoPorTamanhoKeys': precoPorTamanhoKeys,
        'HAS_ZERO_VARIATION_QTY': hasZeroVariationQty,
        'HAS_MISSING_VARIATION_QTY': hasMissingVariationQty,
        'HAS_STOCK_MAP_WITH_POSITIVE_QTY': hasStockMapWithPositiveQty,
        'HAS_PRICE_KEY_WITHOUT_STOCK_KEY': hasPriceKeyWithoutStockKey,
        'REPRESENTATION_MISMATCH': representationMismatch,
      };
}

class VariationStockDiagnosticCell {
  const VariationStockDiagnosticCell({
    required this.canonicalKey,
    required this.size,
    required this.color,
    required this.extra,
    required this.quantity,
    required this.quantityMissing,
  });

  final String canonicalKey;
  final String size;
  final String color;
  final String extra;
  final int? quantity;
  final bool quantityMissing;

  Map<String, dynamic> toJson() => {
        'canonicalKey': canonicalKey,
        'size': size,
        'color': color,
        'extra': extra,
        'quantity': quantity,
        'quantityMissing': quantityMissing,
      };
}

class VariationStockDiagnosticQueueIntent {
  const VariationStockDiagnosticQueueIntent({
    required this.intentId,
    required this.operationId,
    required this.productId,
    required this.operationType,
    required this.createdAtMs,
    required this.attemptCount,
    required this.status,
    required this.deadLetter,
    required this.expectedStockRevision,
    required this.kind,
    required this.variationKeyFingerprint,
    required this.staleVsLocalRevision,
    required this.localStockRevision,
  });

  final String intentId;
  final String operationId;
  final String productId;
  final String operationType;
  final int createdAtMs;
  final int attemptCount;
  final String status;
  final bool deadLetter;
  final int? expectedStockRevision;
  final String? kind;
  final List<String> variationKeyFingerprint;
  final bool? staleVsLocalRevision;
  final int? localStockRevision;

  Map<String, dynamic> toJson() => {
        'intentId': intentId,
        'operationId': operationId,
        'productId': productId,
        'operationType': operationType,
        'createdAtMs': createdAtMs,
        'attemptCount': attemptCount,
        'status': status,
        'deadLetter': deadLetter,
        'expectedStockRevision': expectedStockRevision,
        'kind': kind,
        'variationKeyFingerprint': variationKeyFingerprint,
        'staleVsLocalRevision': staleVsLocalRevision,
        'localStockRevision': localStockRevision,
      };
}

/// Pure helpers for tests / fixtures (no Hive).
class VariationStockRecoveryDiagnosticBuilder {
  VariationStockRecoveryDiagnosticBuilder._();

  static String nameFingerprint(String nome) {
    final norm = nome.trim().toLowerCase();
    if (norm.isEmpty) return 'empty';
    final digest = sha256.convert(utf8.encode(norm));
    return digest.toString().substring(0, 12);
  }

  static List<VariationStockDiagnosticCell> extractVariationCells(
    Map<String, dynamic>? variacoes,
  ) {
    final out = <VariationStockDiagnosticCell>[];
    if (variacoes == null || variacoes.isEmpty) return out;
    for (final te in variacoes.entries) {
      final tamanho = te.key.toString();
      final cmap = te.value;
      if (cmap is! Map) continue;
      for (final ce in cmap.entries) {
        final cor = ce.key.toString();
        final raw = ce.value;
        if (raw is num) {
          out.add(
            VariationStockDiagnosticCell(
              canonicalKey: '$tamanho|$cor',
              size: tamanho,
              color: cor,
              extra: '',
              quantity: raw.toInt(),
              quantityMissing: false,
            ),
          );
          continue;
        }
        if (raw is Map) {
          var anyQty = false;
          for (final ie in raw.entries) {
            final ek = ie.key.toString();
            if (ProdutoVariacaoExtra.isMetaKey(ek)) continue;
            anyQty = true;
            final missing = ie.value == null ||
                (ie.value is! num &&
                    int.tryParse(ie.value?.toString() ?? '') == null);
            final q = missing
                ? null
                : (ie.value is num
                    ? (ie.value as num).toInt()
                    : int.tryParse(ie.value.toString()));
            final evDisp =
                ProdutoVariacaoExtra.isSemExtraMapKey(ek) ? '' : ek;
            out.add(
              VariationStockDiagnosticCell(
                canonicalKey: evDisp.isEmpty
                    ? '$tamanho|$cor'
                    : '$tamanho|$cor|$evDisp',
                size: tamanho,
                color: cor,
                extra: evDisp,
                quantity: q,
                quantityMissing: missing || q == null,
              ),
            );
          }
          if (!anyQty) {
            out.add(
              VariationStockDiagnosticCell(
                canonicalKey: '$tamanho|$cor',
                size: tamanho,
                color: cor,
                extra: '',
                quantity: null,
                quantityMissing: true,
              ),
            );
          }
        } else {
          out.add(
            VariationStockDiagnosticCell(
              canonicalKey: '$tamanho|$cor',
              size: tamanho,
              color: cor,
              extra: '',
              quantity: null,
              quantityMissing: true,
            ),
          );
        }
      }
    }
    return out;
  }

  static VariationStockDiagnosticProduct fromProdutoFields({
    required String productId,
    int? hiveKey,
    required String nome,
    required int stockRevision,
    required bool usaVariacoes,
    required int baseEstoque,
    required Map<String, dynamic>? variacoes,
    required Map<String, int> estoquePorTamanho,
    required Map<String, double>? precoPorTamanho,
  }) {
    final cells = extractVariationCells(variacoes);
    final ept = Map<String, int>.from(estoquePorTamanho);
    final pptKeys = (precoPorTamanho ?? const <String, double>{})
        .keys
        .map((e) => e.toString())
        .toList()
      ..sort();
    final hasZero = cells.any((c) => c.quantity == 0);
    final hasMissing = cells.any((c) => c.quantityMissing || c.quantity == null);
    final hasStockMapPositive = ept.values.any((v) => v > 0);
    final stockKeys = <String>{
      ...ept.keys.map((e) => e.toString()),
      ...cells.map((c) => c.size).where((s) => s.isNotEmpty),
    };
    final hasPriceWithoutStock = pptKeys.any((k) {
      if (stockKeys.contains(k)) return false;
      // also check compound ept keys starting with size
      return !ept.keys.any((ek) => ek.toString() == k || ek.toString().startsWith('$k|'));
    });
    final varSum = cells.fold<int>(
      0,
      (a, c) => a + (c.quantity ?? 0),
    );
    final eptSum = ept.values.fold<int>(0, (a, b) => a + b);
    final mismatch = usaVariacoes &&
        ((hasZero && hasStockMapPositive) ||
            (hasMissing && hasStockMapPositive) ||
            (cells.isNotEmpty && ept.isNotEmpty && varSum != eptSum) ||
            hasPriceWithoutStock);

    return VariationStockDiagnosticProduct(
      productId: productId,
      hiveKey: hiveKey,
      nameFingerprint: nameFingerprint(nome),
      stockRevision: stockRevision,
      usaVariacoes: usaVariacoes,
      baseEstoque: baseEstoque,
      variationCount: cells.length,
      variations: cells,
      estoquePorTamanho: ept,
      precoPorTamanhoKeys: pptKeys,
      hasZeroVariationQty: hasZero,
      hasMissingVariationQty: hasMissing,
      hasStockMapWithPositiveQty: hasStockMapPositive,
      hasPriceKeyWithoutStockKey: hasPriceWithoutStock,
      representationMismatch: mismatch,
    );
  }

  static List<String> variationKeysFromDefinition(Map<String, dynamic>? definition) {
    if (definition == null) return const [];
    final v = definition['variacoes'];
    if (v is! Map) return const [];
    return extractVariationCells(Map<String, dynamic>.from(v))
        .map((e) => e.canonicalKey)
        .toList();
  }

  /// Redacts known secret/PII patterns from an arbitrary JSON tree (defense).
  static dynamic redactSecrets(dynamic value) {
    if (value is Map) {
      final out = <String, dynamic>{};
      for (final e in value.entries) {
        final k = e.key.toString().toLowerCase();
        if (_secretKey(k)) continue;
        out[e.key.toString()] = redactSecrets(e.value);
      }
      return out;
    }
    if (value is List) return value.map(redactSecrets).toList();
    if (value is String) {
      if (_looksLikeJwt(value) || _looksLikeToken(value)) return '[REDACTED]';
      return value;
    }
    return value;
  }

  static bool _secretKey(String k) {
    const keys = {
      'password',
      'token',
      'idtoken',
      'id_token',
      'accesstoken',
      'access_token',
      'refreshtoken',
      'refresh_token',
      'authorization',
      'authheader',
      'credential',
      'secret',
      'apikey',
      'api_key',
      'email',
      'telefone',
      'phone',
      'cpf',
      'cnpj',
      'endereco',
      'address',
      'clientenome',
      'cliente_nome',
      'customername',
      'customer_name',
    };
    return keys.contains(k.replaceAll(RegExp(r'[^a-z0-9_]'), ''));
  }

  static bool _looksLikeJwt(String s) {
    final parts = s.split('.');
    return parts.length == 3 && parts.every((p) => p.length > 8);
  }

  static bool _looksLikeToken(String s) {
    if (s.length < 32) return false;
    return RegExp(r'^[A-Za-z0-9_\-]{32,}$').hasMatch(s);
  }
}

class VariationStockRecoveryDiagnosticService {
  VariationStockRecoveryDiagnosticService({
    http.Client? httpClient,
    this.clientWebVersion = kVariationStockDiagnosticClientBuildId,
    this.maxProducts = kVariationStockDiagnosticMaxProducts,
    this.maxQueueIntents = kVariationStockDiagnosticMaxQueueIntents,
  }) : _http = httpClient ?? http.Client();

  final http.Client _http;
  final String clientWebVersion;
  final int maxProducts;
  final int maxQueueIntents;

  /// Ensures recovery mode is active before any diagnostic read.
  void assertRecoveryModeActive() {
    if (!SyncQueueRecoveryMode.isActive) {
      throw VariationStockDiagnosticGuardException(
        'Diagnóstico disponível apenas em modo de recuperação (?mpQueueRecovery=1).',
      );
    }
    if (SyncQueueRecoveryMode.allowsAutomaticQueueProcessing) {
      throw VariationStockDiagnosticGuardException(
        'Supressão de sincronização não está activa.',
      );
    }
  }

  Future<String?> fetchServerWebVersion({Uri? baseUri}) async {
    try {
      final origin = _httpOrigin(baseUri);
      if (origin == null) return null;
      final versionUri = Uri.parse('$origin/version.json').replace(
        queryParameters: {
          'v': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );
      final res =
          await _http.get(versionUri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is Map && decoded['buildId'] != null) {
        return decoded['buildId'].toString();
      }
    } catch (_) {}
    return null;
  }

  /// Returns http(s) origin for optional read-only version.json fetch.
  /// Non-web / file:// bases (unit tests) skip remote read.
  static String? _httpOrigin(Uri? baseUri) {
    final u = baseUri ?? Uri.base;
    try {
      if (u.scheme == 'http' || u.scheme == 'https') {
        return u.origin;
      }
    } catch (_) {}
    return null;
  }

  Future<List<Produto>> loadLocalProducts(String lojaId) async {
    assertRecoveryModeActive();
    final id = lojaId.trim();
    if (id.isEmpty) return const [];
    final name = HiveBoxNames.produtos(id);
    Box<Produto> box;
    if (Hive.isBoxOpen(name)) {
      box = Hive.box<Produto>(name);
    } else {
      box = await Hive.openBox<Produto>(name);
    }
    return box.values
        .where((p) => (p.lojaId.trim().isEmpty || p.lojaId.trim() == id))
        .toList();
  }

  VariationStockDiagnosticProduct productFromHive(Produto p) {
    final productId = p.idFirebase.trim().isNotEmpty
        ? p.idFirebase.trim()
        : (p.slug.trim().isNotEmpty ? p.slug.trim() : 'hive_${p.key}');
    int? hiveKey;
    try {
      final k = p.key;
      if (k is int) hiveKey = k;
    } catch (_) {}
    return VariationStockRecoveryDiagnosticBuilder.fromProdutoFields(
      productId: productId,
      hiveKey: hiveKey,
      nome: p.nome,
      stockRevision: p.stockRevision,
      usaVariacoes: p.usaVariacoes,
      baseEstoque: p.quantidade,
      variacoes: p.variacoes == null
          ? null
          : Map<String, dynamic>.from(p.variacoes!),
      estoquePorTamanho: Map<String, int>.from(p.estoquePorTamanho),
      precoPorTamanho: p.precoPorTamanho,
    );
  }

  Future<VariationStockRecoveryDiagnosticSnapshot> generate({
    required String storeId,
    String? nameFilter,
    Uri? baseUri,
    List<Produto>? productsOverride,
    List<SyncQueueItem>? queueOverride,
  }) async {
    assertRecoveryModeActive();
    final store = storeId.trim();
    final filter = (nameFilter ?? '').trim().toLowerCase();

    final productsRaw =
        productsOverride ?? await loadLocalProducts(store);
    final variable = productsRaw.where((p) {
      if (!p.usaVariacoes &&
          p.estoquePorTamanho.isEmpty &&
          (p.precoPorTamanho == null || p.precoPorTamanho!.isEmpty)) {
        return false;
      }
      if (filter.isEmpty) return true;
      return p.nome.toLowerCase().contains(filter) ||
          p.idFirebase.toLowerCase().contains(filter) ||
          p.slug.toLowerCase().contains(filter);
    }).toList();

    // Prioritize zero/mismatch products, then cap.
    final mapped = variable.map(productFromHive).toList();
    mapped.sort((a, b) {
      int score(VariationStockDiagnosticProduct p) {
        var s = 0;
        if (p.hasZeroVariationQty) s += 8;
        if (p.hasMissingVariationQty) s += 4;
        if (p.representationMismatch) s += 4;
        if (p.hasPriceKeyWithoutStockKey) s += 2;
        return -s;
      }

      return score(a).compareTo(score(b));
    });
    final products = mapped.take(maxProducts).toList();

    final byProductId = {
      for (final p in products) p.productId: p,
    };
    final byHiveKey = {
      for (final p in products)
        if (p.hiveKey != null) p.hiveKey!: p,
    };

    final queueItems = queueOverride ??
        await _loadProductQueueItems(store);
    final queueOut = <VariationStockDiagnosticQueueIntent>[];
    for (final item in queueItems) {
      if (queueOut.length >= maxQueueIntents) break;
      if (item.type != SyncOperationType.upsertProduto) continue;
      final intent = ProdutoStockCatalogCadastroIntent.tryDecode(
        item.stockIntentJson,
      );
      String? productIdFromItems;
      if (intent != null) {
        for (final it in intent.items) {
          final pid = it['productId']?.toString().trim();
          if (pid != null && pid.isNotEmpty) {
            productIdFromItems = pid;
            break;
          }
        }
      }

      final localByKey = byHiveKey[item.entityKey];
      final localByItems = productIdFromItems == null
          ? null
          : byProductId[productIdFromItems];
      final String productId;
      if (localByKey != null) {
        productId = localByKey.productId;
      } else if (productIdFromItems != null) {
        productId = productIdFromItems;
      } else {
        productId = 'hive_${item.entityKey}';
      }

      // Include intents for products in the diagnostic set or any replace intent.
      final kind = intent?.kind;
      final related = byProductId.containsKey(productId) ||
          localByKey != null ||
          localByItems != null ||
          kind == 'replace';
      if (!related && products.isNotEmpty && kind != 'replace') {
        continue;
      }

      final localProduct = localByKey ?? localByItems ?? byProductId[productId];
      final localRev = localProduct?.stockRevision;
      final expected = intent?.expectedRevision;
      bool? stale;
      if (expected != null && localRev != null) {
        stale = expected < localRev;
      }

      final keys = VariationStockRecoveryDiagnosticBuilder
          .variationKeysFromDefinition(intent?.definition);

      queueOut.add(
        VariationStockDiagnosticQueueIntent(
          intentId: item.id,
          operationId: (intent?.operationId.trim().isNotEmpty ?? false)
              ? intent!.operationId
              : item.operationId,
          productId: productId,
          operationType: item.type.name,
          createdAtMs: item.createdAt,
          attemptCount: item.attemptCount,
          status: item.deadLetter ? 'deadLetter' : 'pending',
          deadLetter: item.deadLetter,
          expectedStockRevision: expected,
          kind: kind,
          variationKeyFingerprint: keys,
          staleVsLocalRevision: stale,
          localStockRevision: localRev,
        ),
      );
    }

    final serverVersion = await fetchServerWebVersion(baseUri: baseUri);

    final summary = VariationStockDiagnosticSummary(
      variableProductCount: products.length,
      zeroQtyProductCount:
          products.where((p) => p.hasZeroVariationQty).length,
      missingQtyProductCount:
          products.where((p) => p.hasMissingVariationQty).length,
      representationMismatchCount:
          products.where((p) => p.representationMismatch).length,
      priceKeyWithoutStockKeyCount:
          products.where((p) => p.hasPriceKeyWithoutStockKey).length,
      pendingProductIntentCount: queueOut.length,
      staleIntentCount:
          queueOut.where((q) => q.staleVsLocalRevision == true).length,
    );

    final snap = VariationStockRecoveryDiagnosticSnapshot(
      diagnosticVersion: kVariationStockRecoveryDiagnosticVersion,
      capturedAtUtc: DateTime.now().toUtc().toIso8601String(),
      recoveryMode: true,
      clientWebVersion: clientWebVersion,
      serverWebVersion: serverVersion,
      storeId: store,
      products: products,
      queue: queueOut,
      summary: summary,
    );
    return snap;
  }

  Future<List<SyncQueueItem>> _loadProductQueueItems(String storeId) async {
    assertRecoveryModeActive();
    // listDiagnosticEntries is read-only; reconstruct minimal SyncQueueItem
    // via metadata + stockIntent from box without mutating.
    await SyncQueueService.listDiagnosticEntries(); // warm box open
    // Use listQueueMetadata for store filter; then open raw for stockIntentJson only.
    final meta = await SyncQueueService.listQueueMetadata(
      storeId: storeId,
      type: SyncOperationType.upsertProduto,
    );
    final out = <SyncQueueItem>[];
    for (final m in meta) {
      if (out.length >= maxQueueIntents * 2) break;
      // Re-read single item through diagnostic entries path is insufficient for
      // stockIntentJson. Use SyncQueueService internal via exportRaw is forbidden
      // (sensitive). Instead decode only stockIntentJson field via metadata id.
      final item = await _readQueueItemSafe(m.queueItemId);
      if (item != null) out.add(item);
    }
    return out;
  }

  Future<SyncQueueItem?> _readQueueItemSafe(String id) async {
    // Open the sync queue box the same way SyncQueueService does — read only.
    const boxName = 'sync_queue';
    Box box;
    if (Hive.isBoxOpen(boxName)) {
      box = Hive.box(boxName);
    } else {
      try {
        box = await Hive.openBox(boxName);
      } catch (_) {
        return null;
      }
    }
    final raw = box.get(id);
    if (raw == null) return null;
    Map<String, dynamic>? map;
    if (raw is String) {
      try {
        map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {
        return null;
      }
    } else if (raw is Map) {
      map = Map<String, dynamic>.from(raw);
    }
    if (map == null) return null;
    // Strip editorial/definition bulk before decode by keeping stockIntentJson
    // and parsing with tryDecode (we only export keys/revision).
    return SyncQueueItem.fromMap(map);
  }
}
