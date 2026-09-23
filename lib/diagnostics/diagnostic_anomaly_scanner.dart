import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../core/client_build_identity.dart';
import '../core/hive_box_names.dart';
import '../core/produto_estoque_grade_snapshot.dart';
import '../core/produto_untracked_stock_conflict.dart';
import '../models/produto.dart';
import '../models/venda.dart';
import '../services/firestore_paths.dart';
import '../services/loja_id_service.dart';
import '../services/produto_exclusao_tombstone_service.dart';
import 'diagnostic_enums.dart';
import 'diagnostic_error_classifier.dart';
import 'diagnostic_incident.dart';
import 'diagnostic_incident_history.dart';
import 'diagnostic_result.dart';
import 'diagnostic_sanitize.dart';
import 'diagnostic_trace_service.dart';

/// Read-only anomaly scanner for the **current** tenant only.
/// Never mutates stock, sales, deletes, or restores.
class DiagnosticAnomalyScanner {
  DiagnosticAnomalyScanner({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const int _maxRemoteDocs = 5000;
  static const int _maxComparisonsInExport = 200;

  Future<DiagnosticResult> scanCurrentStore({
    String? storeIdOverride,
    bool recordIncidents = true,
  }) async {
    final storeId =
        (storeIdOverride ?? await LojaIdService.get() ?? '').trim();
    if (storeId.isEmpty) {
      throw StateError('STORE_ID required for diagnostic scan');
    }

    final diagnosticId = const Uuid().v4();
    final generatedAt = DateTime.now().toUtc();
    final build = clientBuildProofMap();
    final incidents = <DiagnosticIncident>[];
    final stockComparisons = <Map<String, dynamic>>[];
    final saleDiagnostics = <Map<String, dynamic>>[];
    final pendingDiagnostics = <Map<String, dynamic>>[];
    final tombstoneDiagnostics = <Map<String, dynamic>>[];

    var online = true;
    var networkState = 'unknown';
    try {
      final c = await Connectivity().checkConnectivity();
      networkState = c.map((e) => e.name).join(',');
      online = !c.contains(ConnectivityResult.none);
    } catch (_) {}

    if (kClientBuildMetadataMissing) {
      incidents.add(_incident(
        storeId: storeId,
        diagnosticId: diagnosticId,
        classification: DiagnosticClassification.buildIdentityMismatch,
        module: DiagnosticModule.buildIdentity,
        operationType: 'scan',
        productIds: const [],
        online: online,
        networkState: networkState,
        meta: {'BUILD_METADATA_MISSING': true},
      ));
    }

    final localProducts = await _loadLocalProducts(storeId);
    final localTotal =
        localProducts.fold<int>(0, (s, p) => s + (p.quantidade));

    Map<String, Map<String, dynamic>> remoteById = {};
    Map<String, Map<String, dynamic>> tombsById = {};
    var remoteTotal = 0;
    var remoteCount = 0;
    try {
      if (online) {
        remoteById = await _loadRemoteCollection(
          storeId,
          FSPaths.estoqueProdutosCol,
        );
        tombsById = await _loadRemoteCollection(
          storeId,
          FSPaths.exclusaoProdutoCol,
        );
        remoteCount = remoteById.length;
        for (final d in remoteById.values) {
          remoteTotal += _asInt(d['quantidade']);
        }
      }
    } catch (e, st) {
      incidents.add(_incident(
        storeId: storeId,
        diagnosticId: diagnosticId,
        classification: DiagnosticClassification.firebaseUnavailable,
        module: DiagnosticModule.firestore,
        operationType: 'remote_stock_list',
        productIds: const [],
        online: online,
        networkState: networkState,
        error: e,
        stack: st,
      ));
    }

    final pendingSeen = <String, int>{};

    for (final p in localProducts) {
      final pid = p.idFirebase;
      final snap = ProdutoEstoqueGradeSnapshot.fromProduto(p);
      final cellSum = snap.cells.values.fold<int>(0, (a, b) => a + b);
      final hasCells = snap.cells.isNotEmpty;
      final remote = remoteById[pid];

      if (p.pendingStockOperationId != null &&
          p.pendingStockOperationId!.trim().isNotEmpty) {
        final pend = p.pendingStockOperationId!.trim();
        pendingSeen[pend] = (pendingSeen[pend] ?? 0) + 1;
        pendingDiagnostics.add({
          'productId': pid,
          'pendingOperationId': pend,
          'localQty': p.quantidade,
          'stockRevision': p.stockRevision,
        });
        incidents.add(_incident(
          storeId: storeId,
          diagnosticId: diagnosticId,
          classification: DiagnosticClassification.stockPendingOperation,
          module: DiagnosticModule.stock,
          operationType: 'pending_scan',
          productIds: [pid],
          online: online,
          networkState: networkState,
          stockOperationId: pend,
          meta: {'localQty': p.quantidade},
        ));
      }

      if (hasCells && cellSum != p.quantidade) {
        stockComparisons.add({
          'productId': pid,
          'scope': 'local_aggregate_vs_cells',
          'aggregate': p.quantidade,
          'cellSum': cellSum,
          'delta': p.quantidade - cellSum,
        });
      }

      if (remote != null) {
        final rQty = _asInt(remote['quantidade']);
        final rRev = remote['stockRevision'];
        final rOp = remote['stockOperationId']?.toString();
        final rCells = _cellsFromRemote(remote);
        final rSum = rCells.values.fold<int>(0, (a, b) => a + b);

        if (p.quantidade != rQty) {
          final row = {
            'productId': pid,
            'scope': 'local_vs_remote',
            'localQty': p.quantidade,
            'remoteQty': rQty,
            'localRevision': p.stockRevision,
            'remoteRevision': rRev,
            'localOp': p.confirmedStockOperationId,
            'remoteOp': rOp,
          };
          if (stockComparisons.length < _maxComparisonsInExport) {
            stockComparisons.add(row);
          }
          incidents.add(_incident(
            storeId: storeId,
            diagnosticId: diagnosticId,
            classification: DiagnosticClassification.stockLocalRemoteMismatch,
            module: DiagnosticModule.stock,
            operationType: 'local_remote_compare',
            productIds: [pid],
            online: online,
            networkState: networkState,
            meta: row,
            severityOverride: DiagnosticSeverity.warning,
          ));
        }

        if (rCells.isNotEmpty && rSum != rQty) {
          incidents.add(_incident(
            storeId: storeId,
            diagnosticId: diagnosticId,
            classification: DiagnosticClassification.stockAggregateMismatch,
            module: DiagnosticModule.stock,
            operationType: 'remote_aggregate_vs_cells',
            productIds: [pid],
            online: online,
            networkState: networkState,
            stockOperationId: rOp,
            meta: {
              'AGGREGATE_QTY': rQty,
              'CANONICAL_CELL_SUM': rSum,
              'DELTA': rQty - rSum,
              'STOCK_REVISION': rRev,
            },
            forceConfirmed: true,
            severityOverride: DiagnosticSeverity.warning,
          ));
        }

        final tomb = tombsById[pid];
        if (tomb != null && tomb['p'] != true) {
          final bloq = _tombKeys(tomb);
          if (bloq.isNotEmpty) {
            final liveHits = <String>[];
            for (final e in rCells.entries) {
              if (e.value <= 0) continue;
              final parts = e.key.split('|');
              final tam = parts.isNotEmpty ? parts[0] : '';
              final cor = parts.length > 1 ? parts.sublist(1).join('|') : '';
              if (_tombHits(bloq, tam, cor)) {
                liveHits.add('${e.key}=${e.value}');
              }
            }
            if (liveHits.isNotEmpty) {
              tombstoneDiagnostics.add({
                'productId': pid,
                'staleKeys': bloq.toList(),
                'liveCellQty': liveHits,
              });
              incidents.add(_incident(
                storeId: storeId,
                diagnosticId: diagnosticId,
                classification:
                    DiagnosticClassification.staleTombstoneLiveRemoteCell,
                module: DiagnosticModule.stock,
                operationType: 'tombstone_scan',
                productIds: [pid],
                online: online,
                networkState: networkState,
                meta: {'liveCellQty': liveHits},
                forceConfirmed: true,
              ));
            }
          }
        }
      }
    }

    for (final e in pendingSeen.entries) {
      if (e.value > 1) {
        incidents.add(_incident(
          storeId: storeId,
          diagnosticId: diagnosticId,
          classification: DiagnosticClassification.stockDuplicatePending,
          module: DiagnosticModule.stock,
          operationType: 'pending_scan',
          productIds: const [],
          online: online,
          networkState: networkState,
          stockOperationId: e.key,
          meta: {'count': e.value},
          forceConfirmed: true,
        ));
      }
    }

    try {
      final conflicts = UntrackedStockConflictStore.allForStore(storeId);
      for (final c in conflicts.take(50)) {
        incidents.add(_incident(
          storeId: storeId,
          diagnosticId: diagnosticId,
          classification: DiagnosticClassification.cacheLocalUntrackedMutation,
          module: DiagnosticModule.hive,
          operationType: 'untracked_scan',
          productIds: [c.productId],
          online: online,
          networkState: networkState,
          meta: c.toJson(),
        ));
      }
    } catch (_) {}

    try {
      final sales = await _loadLocalSales(storeId);
      var missingListed = 0;
      for (final v in sales) {
        final sid = (v.idFirebase ?? v.key?.toString() ?? '').toString();
        final bound = (v.stockOperationId ?? '').trim();
        if (bound.isEmpty) {
          saleDiagnostics.add({
            'saleId': sid,
            'classification':
                DiagnosticClassification.saleMissingStockOperationBinding,
            'bindingClass': 'C_OR_MISSING_EXPLICIT',
          });
          if (missingListed < 30) {
            missingListed++;
            incidents.add(_incident(
              storeId: storeId,
              diagnosticId: diagnosticId,
              classification:
                  DiagnosticClassification.saleMissingStockOperationBinding,
              module: DiagnosticModule.sales,
              operationType: 'sale_binding_scan',
              productIds: const [],
              saleId: sid,
              online: online,
              networkState: networkState,
              severityOverride: DiagnosticSeverity.info,
            ));
          }
        }
      }
    } catch (_) {}

    final health = DiagnosticHealthStatus.fromSeverities(
      incidents.map((i) => i.severity),
    );

    final summary = <String, dynamic>{
      'PRODUCT_COUNT_LOCAL': localProducts.length,
      'PRODUCT_COUNT_REMOTE': remoteCount,
      'LOCAL_TOTAL': localTotal,
      'REMOTE_TOTAL': remoteTotal,
      'DELTA': localTotal - remoteTotal,
      'PENDING_COUNT': pendingDiagnostics.length,
      'ANOMALY_COUNT': incidents.length,
      'CRITICAL_COUNT':
          incidents.where((i) => i.severity == DiagnosticSeverity.critical).length,
      'ONLINE': online,
      'NETWORK_STATE': networkState,
    };

    if (recordIncidents) {
      for (final i in incidents) {
        if (i.severity == DiagnosticSeverity.info) continue;
        await DiagnosticIncidentHistory.record(i);
      }
    }

    return DiagnosticResult(
      diagnosticId: diagnosticId,
      storeId: storeId,
      generatedAt: generatedAt,
      health: health,
      summary: summary,
      incidents: incidents,
      buildIdentity: build,
      operationTraces:
          DiagnosticTraceService.toDiagnosticSection(storeId: storeId),
      stockComparisons: stockComparisons,
      saleDiagnostics: saleDiagnostics.take(100).toList(),
      pendingDiagnostics: pendingDiagnostics,
      tombstoneDiagnostics: tombstoneDiagnostics,
      extra: {
        'LAST_DIAGNOSTIC_AT': generatedAt.toIso8601String(),
        'CURRENT_BUILD_ID': build['CLIENT_BUILD_ID'],
        'APP_VERSION': build['APP_VERSION'],
        'GIT_COMMIT': build['CLIENT_GIT_COMMIT'],
      },
    );
  }

  DiagnosticIncident _incident({
    required String storeId,
    required String diagnosticId,
    required String classification,
    required DiagnosticModule module,
    required String operationType,
    required List<String> productIds,
    required bool online,
    required String networkState,
    Object? error,
    StackTrace? stack,
    String? saleId,
    String? stockOperationId,
    Map<String, dynamic>? meta,
    DiagnosticSeverity? severityOverride,
    bool forceConfirmed = false,
  }) {
    final classified = error != null
        ? DiagnosticErrorClassifier.classify(
            error,
            stack: stack,
            hintClassification: classification,
            online: online,
          )
        : DiagnosticErrorClassifier.fromAnomalyCode(
            classification,
            technicalMessage: meta?.toString(),
            severityOverride: severityOverride,
          );
    final build = clientBuildProofMap();
    return DiagnosticIncident(
      incidentId: const Uuid().v4(),
      traceId: diagnosticId,
      storeId: storeId,
      timestamp: DateTime.now().toUtc(),
      severity: severityOverride ?? classified.severity,
      module: module,
      operationType: operationType,
      classification: classified.classification,
      rootCauseStatus: forceConfirmed
          ? DiagnosticRootCauseStatus.confirmed
          : classified.rootCauseStatus,
      userTitle: classified.userTitle,
      userMessage: classified.userMessage,
      safeNextAction: classified.safeNextAction,
      technicalMessage: classified.technicalMessage,
      firebaseCode: classified.firebaseCode,
      productIds: productIds,
      saleId: saleId,
      stockOperationId: stockOperationId,
      stackFrames: stackFramesList(stack),
      appVersion: build['APP_VERSION']?.toString(),
      gitCommit: build['CLIENT_GIT_COMMIT']?.toString(),
      buildId: build['CLIENT_BUILD_ID']?.toString(),
      networkState: networkState,
      online: online,
      metadataSanitized: meta,
    );
  }

  Future<List<Produto>> _loadLocalProducts(String storeId) async {
    final name = HiveBoxNames.produtos(storeId);
    if (!Hive.isBoxOpen(name)) {
      try {
        await Hive.openBox(name);
      } catch (_) {
        return const [];
      }
    }
    final box = Hive.box(name);
    final out = <Produto>[];
    for (final v in box.values) {
      if (v is Produto) out.add(v);
    }
    return out;
  }

  Future<List<Venda>> _loadLocalSales(String storeId) async {
    final name = HiveBoxNames.vendas(storeId);
    if (!Hive.isBoxOpen(name)) {
      try {
        await Hive.openBox(name);
      } catch (_) {
        return const [];
      }
    }
    final box = Hive.box(name);
    final out = <Venda>[];
    for (final v in box.values) {
      if (v is Venda) out.add(v);
    }
    return out;
  }

  Future<Map<String, Map<String, dynamic>>> _loadRemoteCollection(
    String storeId,
    String collection,
  ) async {
    final col = _db.collection('lojas').doc(storeId).collection(collection);
    final out = <String, Map<String, dynamic>>{};
    QueryDocumentSnapshot<Map<String, dynamic>>? last;
    while (out.length < _maxRemoteDocs) {
      Query<Map<String, dynamic>> q =
          col.orderBy(FieldPath.documentId).limit(200);
      if (last != null) q = q.startAfterDocument(last);
      final snap = await q.get(const GetOptions(source: Source.server));
      if (snap.docs.isEmpty) break;
      for (final d in snap.docs) {
        out[d.id] = d.data();
      }
      last = snap.docs.last;
      if (snap.docs.length < 200) break;
    }
    return out;
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  static Map<String, int> _cellsFromRemote(Map<String, dynamic> data) {
    final vars = data['variacoes'];
    if (vars is! Map) return {};
    final out = <String, int>{};
    vars.forEach((tam, cores) {
      if (cores is! Map) return;
      cores.forEach((cor, qtd) {
        if (cor.toString().startsWith('__')) return;
        final key = ProdutoEstoqueGradeSnapshot.variacaoId(
          tam.toString(),
          cor.toString(),
        );
        if (qtd is Map) {
          var sum = 0;
          qtd.forEach((k, v) {
            if (k.toString().startsWith('__')) return;
            sum += _asInt(v);
          });
          out[key] = sum;
        } else {
          out[key] = _asInt(qtd);
        }
      });
    });
    return out;
  }

  static Set<String> _tombKeys(Map<String, dynamic> tomb) {
    final keys = <String>{};
    final v = tomb['v'];
    if (v is Map) {
      v.forEach((k, val) {
        if (val == true || val == 1 || val == 'true') keys.add(k.toString());
      });
    }
    tomb.forEach((k, val) {
      if (k == 'v' || k == 'p' || k == 'productId' || k == 'operationId') return;
      if (val == true || val == 1) {
        if (k.startsWith('T::') || k.startsWith('V::') || k.contains('|')) {
          keys.add(k);
        }
      }
    });
    return keys;
  }

  static bool _tombHits(Set<String> bloq, String tam, String cor) {
    final t = tam.trim();
    final c = cor.trim();
    if (t.isEmpty) return false;
    if (bloq.contains(ProdutoExclusaoTombstoneService.tKeySoloTamanho(t))) {
      return true;
    }
    if (c.isNotEmpty &&
        bloq.contains(ProdutoExclusaoTombstoneService.vKeyCelula(t, c))) {
      return true;
    }
    final compact = bloq.map((k) => k.replaceAll('\u001e', '|')).toSet();
    if (compact.contains('T::$t') || compact.contains(t)) return true;
    if (c.isNotEmpty &&
        (compact.contains('V::$t|$c') || compact.contains('$t|$c'))) {
      return true;
    }
    return false;
  }
}
