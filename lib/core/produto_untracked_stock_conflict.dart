// LOCAL-ONLY forensic evidence for same-rev/same-op qty divergence.
// Never writes Firestore. Survives subsequent remote hydrates that would
// otherwise silently erase local=1/remote=0 fingerprints.
//
// Not a pending stock mutation: never flush / CAS / revision bump / UI sync block.

import 'package:meta/meta.dart';

import '../models/produto.dart';
import 'produto_estoque_grade_snapshot.dart';
import 'produto_pending_stock_reconciliation.dart';
import 'produto_stock_revision.dart';

/// Snapshot of a LOCAL_UNTRACKED_MUTATION observed before hydrate overwrite.
@immutable
class UntrackedStockConflict {
  const UntrackedStockConflict({
    required this.storeId,
    required this.productId,
    required this.observedLocalQty,
    required this.observedRemoteQty,
    required this.localRevision,
    required this.remoteRevision,
    required this.localOperationId,
    required this.remoteOperationId,
    required this.detectedAt,
    required this.source,
    this.code,
    this.name,
    this.localUpdatedAt,
    this.remoteUpdatedAt,
  });

  final String storeId;
  final String productId;
  final int observedLocalQty;
  final int observedRemoteQty;
  final int localRevision;
  final int remoteRevision;
  final String localOperationId;
  final String remoteOperationId;
  final DateTime detectedAt;
  final String source;
  final String? code;
  final String? name;
  final DateTime? localUpdatedAt;
  final DateTime? remoteUpdatedAt;

  /// Stable fingerprint for dedup (same state → one conflict).
  String get fingerprint => [
        storeId.trim(),
        productId.trim(),
        observedLocalQty,
        observedRemoteQty,
        localRevision,
        remoteRevision,
        localOperationId.trim(),
        remoteOperationId.trim(),
      ].join('|');

  /// Backward-compatible alias used by older call sites.
  int get revision => localRevision;

  /// Backward-compatible alias used by older call sites.
  String get operationId => localOperationId;

  String get key => fingerprint;

  Map<String, dynamic> toJson() => {
        'storeId': storeId,
        'productId': productId,
        'code': code,
        'name': name,
        'observedLocalQty': observedLocalQty,
        'observedRemoteQty': observedRemoteQty,
        'localRevision': localRevision,
        'remoteRevision': remoteRevision,
        'revision': localRevision,
        'localOperationId': localOperationId,
        'remoteOperationId': remoteOperationId,
        'operationId': localOperationId,
        'localUpdatedAt': localUpdatedAt?.toIso8601String(),
        'remoteUpdatedAt': remoteUpdatedAt?.toIso8601String(),
        'detectedAt': detectedAt.toIso8601String(),
        'source': source,
        'fingerprint': fingerprint,
        'CLASSIFICATION': 'LOCAL_UNTRACKED_MUTATION',
      };

  /// Diagnostic exporter row (no storeId noise / PII).
  Map<String, dynamic> toDiagnosticRow() => {
        'PRODUCT_ID': productId,
        'CODE': code,
        'NAME': name,
        'OBSERVED_LOCAL_QTY': observedLocalQty,
        'OBSERVED_REMOTE_QTY': observedRemoteQty,
        'LOCAL_REVISION': localRevision,
        'REMOTE_REVISION': remoteRevision,
        'REVISION': localRevision,
        'LOCAL_OPERATION_ID': localOperationId,
        'REMOTE_OPERATION_ID': remoteOperationId,
        'OPERATION_ID': localOperationId,
        'LOCAL_UPDATED_AT': localUpdatedAt?.toIso8601String(),
        'REMOTE_UPDATED_AT': remoteUpdatedAt?.toIso8601String(),
        'DETECTED_AT': detectedAt.toIso8601String(),
        'SOURCE': source,
        'FINGERPRINT': fingerprint,
        'CLASSIFICATION': 'LOCAL_UNTRACKED_MUTATION',
      };

  factory UntrackedStockConflict.fromJson(Map<String, dynamic> json) {
    return UntrackedStockConflict(
      storeId: (json['storeId'] ?? '').toString(),
      productId: (json['productId'] ?? '').toString(),
      observedLocalQty: (json['observedLocalQty'] as num?)?.toInt() ?? 0,
      observedRemoteQty: (json['observedRemoteQty'] as num?)?.toInt() ?? 0,
      localRevision: (json['localRevision'] as num?)?.toInt() ??
          (json['revision'] as num?)?.toInt() ??
          0,
      remoteRevision: (json['remoteRevision'] as num?)?.toInt() ??
          (json['revision'] as num?)?.toInt() ??
          0,
      localOperationId: (json['localOperationId'] ?? json['operationId'] ?? '')
          .toString(),
      remoteOperationId:
          (json['remoteOperationId'] ?? json['operationId'] ?? '').toString(),
      detectedAt: DateTime.tryParse((json['detectedAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      source: (json['source'] ?? '').toString(),
      code: json['code']?.toString(),
      name: json['name']?.toString(),
      localUpdatedAt:
          DateTime.tryParse((json['localUpdatedAt'] ?? '').toString()),
      remoteUpdatedAt:
          DateTime.tryParse((json['remoteUpdatedAt'] ?? '').toString()),
    );
  }
}

DateTime? _remoteUpdatedAtFromMap(Map<String, dynamic> remote) {
  final stockAt = parseFirestoreStockUpdatedAtField(remote);
  if (stockAt != null) return stockAt;
  final u = remote['updatedAt'];
  if (u is DateTime) return u;
  return null;
}

/// Process-local forensic store (no backend). Tests / diagnostic can read it.
class UntrackedStockConflictStore {
  UntrackedStockConflictStore._();

  /// Keyed by [UntrackedStockConflict.fingerprint].
  static final Map<String, UntrackedStockConflict> _byFingerprint = {};

  @visibleForTesting
  static void clearAll() => _byFingerprint.clear();

  static UntrackedStockConflict? get({
    required String storeId,
    required String productId,
  }) {
    final s = storeId.trim();
    final p = productId.trim();
    UntrackedStockConflict? earliest;
    for (final c in _byFingerprint.values) {
      if (c.storeId != s || c.productId != p) continue;
      if (earliest == null || c.detectedAt.isBefore(earliest.detectedAt)) {
        earliest = c;
      }
    }
    return earliest;
  }

  static List<UntrackedStockConflict> allForStore(String storeId) {
    final s = storeId.trim();
    return _byFingerprint.values
        .where((c) => c.storeId == s)
        .toList(growable: false);
  }

  static List<UntrackedStockConflict> get all =>
      List.unmodifiable(_byFingerprint.values);

  static int countForStore(String storeId) => allForStore(storeId).length;

  /// Insert by fingerprint; same state returns existing (idempotent).
  static UntrackedStockConflict captureExplicit(UntrackedStockConflict conflict) {
    final fp = conflict.fingerprint;
    final existing = _byFingerprint[fp];
    if (existing != null) return existing;
    _byFingerprint[fp] = conflict;
    return conflict;
  }

  /// Captures when [isLocalUntrackedQtyMutation]; dedupes by fingerprint.
  static UntrackedStockConflict? captureIfUntracked({
    required Produto local,
    required Map<String, dynamic> remote,
    required String source,
  }) {
    if (!isLocalUntrackedQtyMutation(local: local, remote: remote)) {
      return null;
    }
    final storeId = local.lojaId.trim();
    final productId = local.idFirebase.trim();
    if (storeId.isEmpty || productId.isEmpty) return null;

    final remoteQty = (remote['quantidade'] as num?)?.toInt() ?? 0;
    final remoteRev = parseStockRevisionFromRemote(remote);
    final remoteOp = parseStockOperationIdFromRemote(remote) ?? '';
    final conflict = UntrackedStockConflict(
      storeId: storeId,
      productId: productId,
      observedLocalQty: local.quantidade,
      observedRemoteQty: remoteQty < 0 ? 0 : remoteQty,
      localRevision: local.stockRevision,
      remoteRevision: remoteRev,
      localOperationId: (local.confirmedStockOperationId ?? '').trim(),
      remoteOperationId: remoteOp,
      detectedAt: DateTime.now().toUtc(),
      source: source,
      code: local.codigoBarras.trim().isEmpty ? null : local.codigoBarras.trim(),
      name: local.nome.trim().isEmpty ? null : local.nome.trim(),
      localUpdatedAt: local.updatedAt,
      remoteUpdatedAt: _remoteUpdatedAtFromMap(remote),
    );
    return captureExplicit(conflict);
  }
}

/// Call before any hydrate that would replace local qty with remote.
/// Returns the captured conflict (if any). Does not block hydrate by itself.
UntrackedStockConflict? preserveUntrackedConflictBeforeHydrate({
  required Produto local,
  required Map<String, dynamic> remote,
  required String source,
}) {
  return UntrackedStockConflictStore.captureIfUntracked(
    local: local,
    remote: remote,
    source: source,
  );
}

/// Adopting remote rev/op while qty still diverges creates/extends untracked.
bool tryConfirmWouldCreateUntrackedFingerprint({
  required Produto local,
  required Map<String, dynamic> remote,
}) {
  if (hasPendingStockMutation(local)) return false;
  final remoteQty = (remote['quantidade'] as num?)?.toInt();
  if (remoteQty == null) return false;
  if (local.quantidade == remoteQty) return false;
  final remoteRev = parseStockRevisionFromRemote(remote);
  final remoteOp = parseStockOperationIdFromRemote(remote) ?? '';
  if (remoteOp.isEmpty) return false;
  // After tryConfirm: local rev/op become remote's while qty stays divergent.
  return remoteRev >= local.stockRevision;
}
