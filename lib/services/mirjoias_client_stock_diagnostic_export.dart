// Exportador forense READ-ONLY do estoque Hive (tenants autorizados).
// Não chama flush, sync, save, stockCatalogCommand nem qualquer write.

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/hive_box_names.dart';
import '../core/produto_estoque_grade_snapshot.dart';
import '../core/produto_stock_revision.dart';
import '../models/produto.dart';
import 'catalogo_sync_diagnostics_access.dart';
import 'firestore_paths.dart';
import 'produtos_firestore_service.dart';

/// IDs técnicos canônicos autorizados (estado real Firestore).
const String kMirjoiasDiagnosticStoreId = 'mirjoias';
const String kNathyDiagnosticStoreId = 'nathy-pratas-e-folheados';

/// Conjunto estável de tenants do exportador de diagnóstico de estoque.
const Set<String> kStockDiagnosticAllowedStoreIds = {
  kMirjoiasDiagnosticStoreId,
  kNathyDiagnosticStoreId,
};

/// Códigos canário / mismatches conhecidos da auditoria MIRJOIAS.
const String kAn05smCode = 'AN05SM';
const List<String> kAggregateMismatchCodes = ['AN13PR', 'BR01SM', 'PL01PR'];

enum MirjoiasPendingClassification {
  realPending,
  stalePending,
  corruptPending,
  ambiguousPending,
}

extension on MirjoiasPendingClassification {
  String get wire => switch (this) {
        MirjoiasPendingClassification.realPending => 'REAL_PENDING',
        MirjoiasPendingClassification.stalePending => 'STALE_PENDING',
        MirjoiasPendingClassification.corruptPending => 'CORRUPT_PENDING',
        MirjoiasPendingClassification.ambiguousPending => 'AMBIGUOUS_PENDING',
      };
}

/// Resultado do export (JSON + TXT) — sem efeitos colaterais.
class MirjoiasClientStockDiagnosticResult {
  MirjoiasClientStockDiagnosticResult({
    required this.payload,
    required this.txtSummary,
    required this.jsonFileName,
    required this.txtFileName,
  });

  final Map<String, dynamic> payload;
  final String txtSummary;
  final String jsonFileName;
  final String txtFileName;

  String get jsonPretty =>
      const JsonEncoder.withIndent('  ').convert(payload);
}

/// Tenant atual está na allowlist do exportador.
bool isAllowedDiagnosticTenant(String? storeId) {
  final id = (storeId ?? '').trim().toLowerCase();
  return kStockDiagnosticAllowedStoreIds.contains(id);
}

/// Prefixo de arquivo por tenant (sem cross-store).
String stockDiagnosticFilePrefix(String storeId) {
  final id = storeId.trim().toLowerCase();
  if (id == kNathyDiagnosticStoreId) return 'NATHY_CLIENT_STOCK_DIAGNOSTIC';
  if (id == kMirjoiasDiagnosticStoreId) {
    return 'MIRJOIAS_CLIENT_STOCK_DIAGNOSTIC';
  }
  return 'CLIENT_STOCK_DIAGNOSTIC';
}

/// Gate síncrono de UI (tenant + flag admin já resolvida).
/// Preferir [canAccessStockDiagnosticExport] na tela (mesmo predicate do
/// "Diagnóstico de sincronização do catálogo").
bool stockDiagnosticExportVisible({
  required String? storeId,
  required bool canAccessExistingAdminDiagnostic,
}) {
  return isAllowedDiagnosticTenant(storeId) &&
      canAccessExistingAdminDiagnostic;
}

/// @deprecated Use [stockDiagnosticExportVisible] / [canAccessStockDiagnosticExport].
bool mirjoiasDiagnosticExportVisible({
  required String? storeId,
  required bool isAdmin,
}) {
  return stockDiagnosticExportVisible(
    storeId: storeId,
    canAccessExistingAdminDiagnostic: isAdmin,
  );
}

/// OWNER/ADMIN (mesmo predicate do diagnóstico de catálogo) + tenant allowlist.
Future<bool> canAccessStockDiagnosticExport({
  required String? storeId,
  Future<bool> Function()? adminDiagnosticAccess,
}) async {
  if (!isAllowedDiagnosticTenant(storeId)) return false;
  final check = adminDiagnosticAccess ?? CatalogoSyncDiagnosticsAccess.podeAcessar;
  return check();
}

class MirjoiasClientStockDiagnosticExport {
  MirjoiasClientStockDiagnosticExport({
    FirebaseFirestore? firestore,
    String liveBuildId = 'dev',
    String liveGitCommit = '',
    String appVersion = '',
    DateTime? generatedAt,
    Future<Map<String, dynamic>?> Function(String lojaId, String docId)?
        remoteDocReader,
  })  : _db = firestore,
        _liveBuildId = liveBuildId,
        _liveGitCommit = liveGitCommit,
        _appVersion = appVersion,
        _generatedAt = generatedAt,
        _remoteDocReader = remoteDocReader;

  final FirebaseFirestore? _db;
  final String _liveBuildId;
  final String _liveGitCommit;
  final String _appVersion;
  final DateTime? _generatedAt;
  final Future<Map<String, dynamic>?> Function(String lojaId, String docId)?
      _remoteDocReader;

  /// Contador de writes — deve permanecer 0 (testes).
  @visibleForTesting
  int writeAttempts = 0;

  FirebaseFirestore get _firestore =>
      _db ??
      ProdutosFirestoreService.debugFirestoreOverride ??
      FirebaseFirestore.instance;

  Future<Map<String, dynamic>?> _readRemoteDoc(
    String lojaId,
    String docId,
  ) async {
    if (_remoteDocReader != null) {
      return _remoteDocReader!(lojaId, docId);
    }
    final snap = await _firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(docId)
        .get();
    if (!snap.exists) return null;
    return snap.data();
  }

  /// Gera diagnóstico. Lança [StateError] se loja não estiver na allowlist.
  Future<MirjoiasClientStockDiagnosticResult> build({
    required String storeId,
    required Iterable<Produto> hiveProducts,
  }) async {
    final loja = storeId.trim().toLowerCase();
    if (!isAllowedDiagnosticTenant(loja)) {
      throw StateError(
        'Diagnostic export is restricted to authorized stores '
        '(${kStockDiagnosticAllowedStoreIds.join(", ")}).',
      );
    }

    final filePrefix = stockDiagnosticFilePrefix(loja);
    final now = _generatedAt ?? DateTime.now().toUtc();
    final stamp = _fileStamp(now);

    final products = hiveProducts
        .where((p) =>
            p.lojaId.trim().isEmpty ||
            p.lojaId.trim().toLowerCase() == loja)
        .where((p) {
          // Isolamento: nunca incluir produto cujo idFirebase aponta outra loja.
          final id = p.idFirebase.trim().toLowerCase();
          if (id.isEmpty) return true;
          for (final other in kStockDiagnosticAllowedStoreIds) {
            if (other == loja) continue;
            if (id.startsWith('$other-') || id.startsWith('${other}_')) {
              return false;
            }
          }
          return true;
        })
        .toList();

    final hiveRows = <Map<String, dynamic>>[];
    final pendingRows = <Map<String, dynamic>>[];
    final pendingByProduct = <String, List<Map<String, dynamic>>>{};
    final pendingOpIds = <String, List<String>>{};

    var localQtySum = 0;
    for (final p in products) {
      localQtySum += p.quantidade;
      final row = _hiveProductRow(p);
      hiveRows.add(row);

      if (hasPendingStockMutation(p)) {
        final pend = _pendingRow(p);
        pendingRows.add(pend);
        final key = _productKey(p);
        pendingByProduct.putIfAbsent(key, () => []).add(pend);
        final op = (p.pendingStockOperationId ?? '').trim();
        if (op.isNotEmpty) {
          pendingOpIds.putIfAbsent(op, () => []).add(key);
        }
      }
    }

    // Orphans / invalids (pending vive no próprio Produto — sem box separada).
    var orphanPending = 0;
    var invalidPending = 0;
    var duplicatePending = 0;
    for (final e in pendingByProduct.entries) {
      if (e.value.length > 1) duplicatePending += e.value.length - 1;
    }
    for (final pend in pendingRows) {
      final op = (pend['PENDING_OPERATION_ID'] as String?)?.trim() ?? '';
      final base = pend['PENDING_BASE_REVISION'];
      final pid = (pend['PRODUCT_ID'] as String?)?.trim() ?? '';
      if (op.isEmpty || base == null) {
        invalidPending++;
        pend['INVALID_REASON'] = op.isEmpty ? 'EMPTY_OPERATION_ID' : 'NO_BASE_REVISION';
      }
      if (pid.isEmpty) {
        orphanPending++;
        pend['ORPHAN'] = true;
      }
    }
    for (final e in pendingOpIds.entries) {
      if (e.value.length > 1) {
        // same operationId on multiple products — flag invalid/corrupt
        invalidPending += e.value.length;
      }
    }

    // Remote comparison targets: pending OR all products (need full qty for delta).
    final remoteById = <String, Map<String, dynamic>>{};
    for (final p in products) {
      final id = p.idFirebase.trim();
      if (id.isEmpty) continue;
      try {
        final data = await _readRemoteDoc(loja, id);
        if (data != null) remoteById[id] = data;
      } catch (e) {
        remoteById[id] = {'_readError': e.runtimeType.toString()};
      }
    }

    var remoteQtySum = 0;
    for (final data in remoteById.values) {
      if (data.containsKey('_readError')) continue;
      remoteQtySum += (data['quantidade'] as num?)?.toInt() ?? 0;
    }

    final comparisons = <Map<String, dynamic>>[];
    final deltaProducts = <Map<String, dynamic>>[];
    final pendingClassified = <Map<String, dynamic>>[];
    final pendingZeroUi = <Map<String, dynamic>>[];
    final orphanVariations = <Map<String, dynamic>>[];
    final aggregateMismatches = <Map<String, dynamic>>[];

    Map<String, dynamic>? an05smSection;

    for (final p in products) {
      final id = p.idFirebase.trim();
      final remote = id.isEmpty ? null : remoteById[id];
      final remoteOk = remote != null && !remote.containsKey('_readError');
      final remoteQty =
          remoteOk ? ((remote['quantidade'] as num?)?.toInt() ?? 0) : null;
      final localGrade = ProdutoEstoqueGradeSnapshot.fromProduto(p);
      final remoteGrade =
          remoteOk ? ProdutoEstoqueGradeSnapshot.fromRemote(remote) : null;

      final needsCompare = hasPendingStockMutation(p) ||
          (remoteQty != null && remoteQty != p.quantidade) ||
          (remoteGrade != null && !localGrade.gradeEquals(remoteGrade));

      Map<String, dynamic>? classificationRow;
      if (hasPendingStockMutation(p)) {
        classificationRow = _classifyPending(
          p: p,
          remote: remoteOk ? remote : null,
          localGrade: localGrade,
          remoteGrade: remoteGrade,
        );
        pendingClassified.add(classificationRow);

        if (p.quantidade == 0) {
          pendingZeroUi.add({
            'PRODUCT_CODE': p.codigoBarras,
            'PRODUCT_NAME': p.nome,
            'PENDING_EXISTS': true,
            'PENDING_INTENDED_QTY': p.quantidade,
            'PENDING_OPERATION_ID': p.pendingStockOperationId,
            'NOTE':
                'UI label number is intended qty (0), not pending operation count',
          });
        }
      }

      if (remoteQty != null && remoteQty != p.quantidade) {
        deltaProducts.add({
          'CODE': p.codigoBarras,
          'NAME': p.nome,
          'PRODUCT_ID': id,
          'LOCAL_QTY': p.quantidade,
          'REMOTE_QTY': remoteQty,
          'DELTA': p.quantidade - remoteQty,
          'PENDING_STATUS': hasPendingStockMutation(p),
          'CLASSIFICATION': classificationRow?['CLASSIFICATION'] ??
              (hasPendingStockMutation(p) ? 'PENDING_UNCLASSIFIED' : 'NO_PENDING'),
        });
      }

      if (needsCompare) {
        comparisons.add({
          'PRODUCT_ID': id,
          'PRODUCT_CODE': p.codigoBarras,
          'LOCAL_QTY': p.quantidade,
          'REMOTE_QTY': remoteQty,
          'REMOTE_STOCK_KIND': remoteOk ? remote['stockKind'] : null,
          'REMOTE_STOCK_REVISION':
              remoteOk ? parseStockRevisionFromRemote(remote) : null,
          'REMOTE_OPERATION_ID':
              remoteOk ? parseStockOperationIdFromRemote(remote) : null,
          'REMOTE_CANONICAL_VARIATIONS': remoteGrade?.cells,
          'REMOTE_GRADE_CELLS': remoteGrade?.cells,
          'REMOTE_UPDATED_AT': remoteOk
              ? remote['updatedAt']?.toString() ??
                  remote['stockUpdatedAt']?.toString()
              : null,
          'REMOTE_READ_ERROR': remote?['_readError'],
          'CLASSIFICATION': classificationRow?['CLASSIFICATION'],
          'REMOTE_REV_EQUALS_BASE':
              classificationRow?['REMOTE_REV_EQUALS_BASE'],
          'STATE_EQUIVALENT': classificationRow?['STATE_EQUIVALENT'],
        });
      }

      // Orphan variation identities (tamanhos[] vs cells).
      final tamanhos = p.tamanhos;
      if (tamanhos.isNotEmpty) {
        final cellKeys = localGrade.cells.keys
            .map((k) => k.split('|').first)
            .toSet();
        final remoteKeys = remoteGrade?.cells.keys
                .map((k) => k.split('|').first)
                .toSet() ??
            <String>{};
        for (final t in tamanhos) {
          final tt = t.trim();
          if (tt.isEmpty) continue;
          final inLocalCells = cellKeys.contains(tt);
          final inRemote = remoteKeys.contains(tt);
          if (!inLocalCells || !inRemote) {
            orphanVariations.add({
              'CODE': p.codigoBarras,
              'NAME': p.nome,
              'LOCAL_IDENTITY': tt,
              'REMOTE_IDENTITY': inRemote ? tt : null,
              'SOURCE_FIELD': 'tamanhos',
              'IN_LOCAL_CELLS': inLocalCells,
              'IN_REMOTE_CELLS': inRemote,
              'QTY': localGrade.cells.entries
                  .where((e) => e.key.startsWith('$tt|'))
                  .fold<int>(0, (a, e) => a + e.value),
              'HAS_PENDING_REFERENCE': hasPendingStockMutation(p),
            });
          }
        }
      }

      final code = p.codigoBarras.trim().toUpperCase();
      if (kAggregateMismatchCodes.contains(code) ||
          (localGrade.cells.isNotEmpty &&
              localGrade.cells.values.fold(0, (a, b) => a + b) !=
                  p.quantidade) ||
          (remoteGrade != null &&
              remoteGrade.cells.isNotEmpty &&
              remoteGrade.cells.values.fold(0, (a, b) => a + b) !=
                  (remoteQty ?? -1))) {
        if (kAggregateMismatchCodes.contains(code) ||
            (localGrade.cells.isNotEmpty &&
                localGrade.cells.values.fold(0, (a, b) => a + b) !=
                    p.quantidade)) {
          aggregateMismatches.add({
            'CODE': p.codigoBarras,
            'NAME': p.nome,
            'LOCAL_AGGREGATE': p.quantidade,
            'LOCAL_CANONICAL_CELLS': localGrade.cells,
            'LOCAL_CELL_SUM':
                localGrade.cells.values.fold(0, (a, b) => a + b),
            'REMOTE_AGGREGATE': remoteQty,
            'REMOTE_CANONICAL_CELLS': remoteGrade?.cells,
            'REMOTE_CELL_SUM': remoteGrade?.cells.values.fold(0, (a, b) => a + b),
            'PENDING_STATE': hasPendingStockMutation(p),
            'CLASSIFICATION': classificationRow?['CLASSIFICATION'],
          });
        }
      }

      if (code == kAn05smCode ||
          id == 'mirjoias-anel-bolinha-t-25-semijoia-3') {
        an05smSection = {
          'AN05SM_LOCAL_PRODUCT': id,
          'AN05SM_PENDING': hasPendingStockMutation(p),
          'AN05SM_LOCAL_QTY': p.quantidade,
          'AN05SM_LOCAL_VARIATIONS': localGrade.cells,
          'AN05SM_LOCAL_STOCK_REVISION': p.stockRevision,
          'AN05SM_LOCAL_OPERATION_ID': p.confirmedStockOperationId,
          'AN05SM_PENDING_OPERATION_ID': p.pendingStockOperationId,
          'AN05SM_PENDING_BASE_REVISION': p.pendingStockBaseRevision,
          'AN05SM_PENDING_INTENDED_STATE': {
            'qty': p.quantidade,
            'cells': localGrade.cells,
          },
          'AN05SM_REMOTE_QTY': remoteQty,
          'AN05SM_REMOTE_VARIATIONS': remoteGrade?.cells,
          'AN05SM_REMOTE_REVISION':
              remoteOk ? parseStockRevisionFromRemote(remote) : null,
          'AN05SM_REMOTE_OPERATION_ID':
              remoteOk ? parseStockOperationIdFromRemote(remote) : null,
          'AN05SM_CLASSIFICATION':
              classificationRow?['CLASSIFICATION'] ?? 'NO_PENDING',
          'AN05SM_REMOTE_REV_EQUALS_BASE':
              classificationRow?['REMOTE_REV_EQUALS_BASE'],
          'AN05SM_STATE_EQUIVALENT': classificationRow?['STATE_EQUIVALENT'],
        };
      }
    }

    final deltaSum =
        deltaProducts.fold<int>(0, (a, e) => a + (e['DELTA'] as int));
    final expectedDelta = localQtySum - remoteQtySum;
    final deltaAccountingPass = deltaSum == expectedDelta;

    final payload = <String, dynamic>{
      'generatedAt': now.toIso8601String(),
      'liveBuildId': _liveBuildId,
      'liveGitCommit': _liveGitCommit,
      'storeId': loja,
      'appVersion': _appVersion,
      'browserPlatform': {
        'kIsWeb': kIsWeb,
        'defaultTargetPlatform': defaultTargetPlatform.name,
      },
      'hiveSchemaNote':
          'Pending mutations live on Produto fields (pendingStockOperationId); no separate pending Hive box.',
      'READ_ONLY': true,
      'TENANT_ISOLATION': true,
      'CROSS_STORE_READS': 0,
      'CROSS_STORE_WRITES': 0,
      'WRITE_ATTEMPTS': writeAttempts,
      'HIVE_PRODUCT_COUNT': hiveRows.length,
      'HIVE_TOTAL_QTY': localQtySum,
      'REMOTE_COMPARED_COUNT': remoteById.length,
      'REMOTE_TOTAL_QTY': remoteQtySum,
      'LOCAL_REMOTE_QTY_DELTA': localQtySum - remoteQtySum,
      'DELTA_ACCOUNTING_PASS': deltaAccountingPass,
      'DELTA_SUM_FROM_PRODUCTS': deltaSum,
      'ORPHAN_PENDING_COUNT': orphanPending,
      'DUPLICATE_PENDING_COUNT': duplicatePending,
      'INVALID_PENDING_COUNT': invalidPending,
      'PENDING_COUNT': pendingRows.length,
      'hiveProducts': hiveRows,
      'pendingMutations': pendingRows,
      'pendingClassified': pendingClassified,
      'remoteComparisons': comparisons,
      'LOCAL_REMOTE_QTY_DELTA_PRODUCTS': deltaProducts,
      'ORPHAN_VARIATION_IDENTITIES': orphanVariations,
      'AGGREGATE_MISMATCHES': aggregateMismatches,
      'PENDING_ZERO_UI_PRODUCTS': pendingZeroUi,
      'AN05SM': an05smSection ??
          {
            'AN05SM_LOCAL_PRODUCT': null,
            'AN05SM_PENDING': false,
            'NOTE': 'AN05SM not found in local Hive box',
          },
      'redaction': {
        'authToken': 'REDACTED_NEVER_EXPORTED',
        'refreshToken': 'REDACTED_NEVER_EXPORTED',
        'apiKey': 'REDACTED_NEVER_EXPORTED',
        'cookies': 'REDACTED_NEVER_EXPORTED',
        'customerPii': 'NOT_INCLUDED',
        'financialData': 'NOT_INCLUDED',
      },
    };

    // Safety: strip accidental secrets by key name.
    _redactSecretsDeep(payload);

    final txt = _buildTxt(payload, now, filePrefix: filePrefix);
    return MirjoiasClientStockDiagnosticResult(
      payload: payload,
      txtSummary: txt,
      jsonFileName: '${filePrefix}_$stamp.json',
      txtFileName: '${filePrefix}_$stamp.txt',
    );
  }

  /// Abre a box Hive da loja (somente leitura de values).
  static Future<Box<Produto>?> openProdutosBox(String lojaId) async {
    final name = HiveBoxNames.produtos(lojaId);
    if (Hive.isBoxOpen(name)) return Hive.box<Produto>(name);
    try {
      return await Hive.openBox<Produto>(name);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _hiveProductRow(Produto p) {
    final grade = ProdutoEstoqueGradeSnapshot.fromProduto(p);
    return {
      'LOCAL_PRODUCT_ID': p.idFirebase,
      'LOCAL_PRODUCT_CODE': p.codigoBarras,
      'LOCAL_PRODUCT_NAME': p.nome,
      'LOCAL_PRODUCT_TYPE': p.ehCombo ? 'combo' : 'simples',
      'LOCAL_STOCK_KIND': _inferStockKind(p),
      'LOCAL_QTY': p.quantidade,
      'LOCAL_STOCK_REVISION': p.stockRevision,
      'LOCAL_STOCK_OPERATION_ID': p.confirmedStockOperationId,
      'LOCAL_USA_VARIACOES': p.usaVariacoes,
      'LOCAL_VARIATIONS': p.variacoes,
      'LOCAL_ESTOQUE_POR_TAMANHO': p.estoquePorTamanho,
      'LOCAL_GRADE_CELLS': grade.cells,
      'LOCAL_TAMANHOS': p.tamanhos,
      'LOCAL_UPDATED_AT': p.updatedAt?.toIso8601String(),
      'LOCAL_PENDING_OPERATION_ID': p.pendingStockOperationId,
      'LOCAL_PENDING_BASE_REVISION': p.pendingStockBaseRevision,
    };
  }

  Map<String, dynamic> _pendingRow(Produto p) {
    final grade = ProdutoEstoqueGradeSnapshot.fromProduto(p);
    return {
      'PRODUCT_ID': p.idFirebase,
      'PRODUCT_CODE': p.codigoBarras,
      'PRODUCT_NAME': p.nome,
      'PENDING_OPERATION_ID': p.pendingStockOperationId,
      'PENDING_BASE_REVISION': p.pendingStockBaseRevision,
      'PENDING_CREATED_AT': null,
      'PENDING_UPDATED_AT': p.updatedAt?.toIso8601String(),
      'PENDING_RETRY_COUNT': null,
      'PENDING_LAST_ERROR': p.stockSyncState,
      'PENDING_MUTATION_TYPE': 'STOCK_ADJUST_PENDING',
      'PENDING_INTENDED_QTY': p.quantidade,
      'PENDING_VARIATION_KEY': null,
      'PENDING_VARIATION_QTY': null,
      'PENDING_GRADE_KEY': null,
      'PENDING_GRADE_QTY': null,
      'PENDING_PAYLOAD_FIELDS': {
        'quantidade': p.quantidade,
        'variacoes': p.variacoes,
        'estoquePorTamanho': p.estoquePorTamanho,
        'gradeCells': grade.cells,
        'stockRevision': p.stockRevision,
        'confirmedStockOperationId': p.confirmedStockOperationId,
      },
    };
  }

  Map<String, dynamic> _classifyPending({
    required Produto p,
    required Map<String, dynamic>? remote,
    required ProdutoEstoqueGradeSnapshot localGrade,
    required ProdutoEstoqueGradeSnapshot? remoteGrade,
  }) {
    final pendingOp = (p.pendingStockOperationId ?? '').trim();
    final base = p.pendingStockBaseRevision ?? p.stockRevision;
    final intended = {
      'qty': p.quantidade,
      'cells': Map<String, int>.from(localGrade.cells),
    };

    if (pendingOp.isEmpty) {
      return {
        'PRODUCT_ID': p.idFirebase,
        'PRODUCT_CODE': p.codigoBarras,
        'CLASSIFICATION': MirjoiasPendingClassification.corruptPending.wire,
        'PENDING_OPERATION_ID': pendingOp,
        'PENDING_BASE_REVISION': base,
        'REMOTE_REVISION': null,
        'REMOTE_OPERATION_ID': null,
        'INTENDED_STATE': intended,
        'REMOTE_STATE': null,
        'STATE_EQUIVALENT': false,
        'REMOTE_REV_EQUALS_BASE': false,
        'REASON': 'EMPTY_PENDING_OPERATION_ID',
      };
    }

    if (remote == null) {
      return {
        'PRODUCT_ID': p.idFirebase,
        'PRODUCT_CODE': p.codigoBarras,
        'CLASSIFICATION': MirjoiasPendingClassification.ambiguousPending.wire,
        'PENDING_OPERATION_ID': pendingOp,
        'PENDING_BASE_REVISION': base,
        'REMOTE_REVISION': null,
        'REMOTE_OPERATION_ID': null,
        'INTENDED_STATE': intended,
        'REMOTE_STATE': null,
        'STATE_EQUIVALENT': false,
        'REMOTE_REV_EQUALS_BASE': false,
        'REASON': 'REMOTE_MISSING_OR_UNREADABLE',
      };
    }

    final remoteRev = parseStockRevisionFromRemote(remote);
    final remoteOp = parseStockOperationIdFromRemote(remote) ?? '';
    final remoteState = {
      'qty': (remote['quantidade'] as num?)?.toInt() ?? 0,
      'cells': remoteGrade?.cells ?? {},
    };
    final stateEq = _statesEquivalent(intended, remoteState);
    final revEqBase = remoteRev == base;

    MirjoiasPendingClassification cls;
    String reason;

    if (remoteOp == pendingOp && remoteRev > base) {
      cls = MirjoiasPendingClassification.stalePending;
      reason = 'REMOTE_CONFIRMED_SAME_OPERATION';
    } else if (remoteOp != pendingOp && remoteRev > base) {
      cls = MirjoiasPendingClassification.stalePending;
      reason = 'REMOTE_ADVANCED_OTHER_OPERATION';
    } else if (remoteOp != pendingOp && revEqBase && stateEq) {
      // Evidência de stale sem remoteRev>base (gap auditado) — NÃO altera abandon.
      cls = MirjoiasPendingClassification.stalePending;
      reason = 'REMOTE_REV_EQ_BASE_BUT_STATE_EQUIVALENT_OTHER_OP';
    } else if (remoteOp == pendingOp && remoteRev <= base) {
      cls = MirjoiasPendingClassification.realPending;
      reason = 'SAME_OP_NOT_YET_ADVANCED';
    } else if (remoteOp != pendingOp && revEqBase && !stateEq) {
      cls = MirjoiasPendingClassification.ambiguousPending;
      reason = 'REMOTE_REV_EQ_BASE_STATE_DIVERGES';
    } else if (!stateEq && remoteRev < base) {
      cls = MirjoiasPendingClassification.ambiguousPending;
      reason = 'REMOTE_REV_BEHIND_BASE';
    } else if (!stateEq) {
      cls = MirjoiasPendingClassification.realPending;
      reason = 'INTENDED_STATE_NOT_ON_REMOTE';
    } else {
      cls = MirjoiasPendingClassification.ambiguousPending;
      reason = 'INSUFFICIENT_EVIDENCE';
    }

    return {
      'PRODUCT_ID': p.idFirebase,
      'PRODUCT_CODE': p.codigoBarras,
      'CLASSIFICATION': cls.wire,
      'PENDING_OPERATION_ID': pendingOp,
      'PENDING_BASE_REVISION': base,
      'REMOTE_REVISION': remoteRev,
      'REMOTE_OPERATION_ID': remoteOp,
      'INTENDED_STATE': intended,
      'REMOTE_STATE': remoteState,
      'STATE_EQUIVALENT': stateEq,
      'REMOTE_REV_EQUALS_BASE': revEqBase,
      'REASON': reason,
    };
  }

  bool _statesEquivalent(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    if ((a['qty'] as int?) != (b['qty'] as int?)) return false;
    final ca = Map<String, int>.from(a['cells'] as Map? ?? {});
    final cb = Map<String, int>.from(b['cells'] as Map? ?? {});
    if (ca.length != cb.length) return false;
    for (final e in ca.entries) {
      if (cb[e.key] != e.value) return false;
    }
    return true;
  }

  String _inferStockKind(Produto p) {
    if (p.ehCombo) return 'combo';
    if (p.usaVariacoes || p.estoquePorTamanho.isNotEmpty) return 'variation';
    return 'simple';
  }

  String _productKey(Produto p) {
    final id = p.idFirebase.trim();
    if (id.isNotEmpty) return id;
    return '${p.codigoBarras}|${p.nome}';
  }

  String _fileStamp(DateTime utc) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utc.year}${two(utc.month)}${two(utc.day)}_'
        '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
  }

  void _redactSecretsDeep(Object? node) {
    if (node is Map) {
      final keys = node.keys.toList();
      for (final k in keys) {
        final ks = k.toString().toLowerCase();
        if (ks.contains('token') ||
            ks.contains('password') ||
            ks.contains('secret') ||
            ks.contains('apikey') ||
            ks.contains('api_key') ||
            ks.contains('authorization') ||
            ks.contains('cookie') ||
            ks.contains('refresh')) {
          node[k] = 'REDACTED';
          continue;
        }
        _redactSecretsDeep(node[k]);
      }
    } else if (node is List) {
      for (final item in node) {
        _redactSecretsDeep(item);
      }
    }
  }

  String _buildTxt(
    Map<String, dynamic> payload,
    DateTime now, {
    required String filePrefix,
  }) {
    final an = payload['AN05SM'] as Map? ?? {};
    final buf = StringBuffer()
      ..writeln('$filePrefix (READ-ONLY)')
      ..writeln('generatedAt: ${now.toIso8601String()}')
      ..writeln('storeId: ${payload['storeId']}')
      ..writeln('TENANT_ISOLATION: true')
      ..writeln('liveBuildId: ${payload['liveBuildId']}')
      ..writeln('liveGitCommit: ${payload['liveGitCommit']}')
      ..writeln('HIVE_PRODUCT_COUNT: ${payload['HIVE_PRODUCT_COUNT']}')
      ..writeln('HIVE_TOTAL_QTY: ${payload['HIVE_TOTAL_QTY']}')
      ..writeln('REMOTE_TOTAL_QTY: ${payload['REMOTE_TOTAL_QTY']}')
      ..writeln('LOCAL_REMOTE_QTY_DELTA: ${payload['LOCAL_REMOTE_QTY_DELTA']}')
      ..writeln('DELTA_ACCOUNTING_PASS: ${payload['DELTA_ACCOUNTING_PASS']}')
      ..writeln('PENDING_COUNT: ${payload['PENDING_COUNT']}')
      ..writeln('ORPHAN_PENDING_COUNT: ${payload['ORPHAN_PENDING_COUNT']}')
      ..writeln('DUPLICATE_PENDING_COUNT: ${payload['DUPLICATE_PENDING_COUNT']}')
      ..writeln('INVALID_PENDING_COUNT: ${payload['INVALID_PENDING_COUNT']}')
      ..writeln(
          'DELTA_PRODUCTS: ${(payload['LOCAL_REMOTE_QTY_DELTA_PRODUCTS'] as List).length}')
      ..writeln(
          'ORPHAN_VARIATIONS: ${(payload['ORPHAN_VARIATION_IDENTITIES'] as List).length}')
      ..writeln(
          'AGGREGATE_MISMATCHES: ${(payload['AGGREGATE_MISMATCHES'] as List).length}')
      ..writeln(
          'PENDING_ZERO_UI: ${(payload['PENDING_ZERO_UI_PRODUCTS'] as List).length}')
      ..writeln('AN05SM_CLASSIFICATION: ${an['AN05SM_CLASSIFICATION']}')
      ..writeln('AN05SM_PENDING: ${an['AN05SM_PENDING']}')
      ..writeln('AN05SM_LOCAL_QTY: ${an['AN05SM_LOCAL_QTY']}')
      ..writeln('AN05SM_REMOTE_QTY: ${an['AN05SM_REMOTE_QTY']}')
      ..writeln('READ_ONLY: true')
      ..writeln('Envie o .json completo ao suporte.');
    return buf.toString();
  }
}
