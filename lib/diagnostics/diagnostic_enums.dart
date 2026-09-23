/// Diagnostic enums — MasterPalm incident / health center.
library;

enum DiagnosticSeverity {
  info,
  warning,
  critical;

  String get wire => name.toUpperCase();

  static DiagnosticSeverity parse(String? raw) {
    switch ((raw ?? '').trim().toUpperCase()) {
      case 'CRITICAL':
        return DiagnosticSeverity.critical;
      case 'WARNING':
        return DiagnosticSeverity.warning;
      default:
        return DiagnosticSeverity.info;
    }
  }
}

enum DiagnosticHealthStatus {
  healthy,
  warning,
  critical;

  String get wire => name.toUpperCase();

  static DiagnosticHealthStatus parse(String? raw) {
    switch ((raw ?? '').trim().toUpperCase()) {
      case 'CRITICAL':
        return DiagnosticHealthStatus.critical;
      case 'WARNING':
        return DiagnosticHealthStatus.warning;
      default:
        return DiagnosticHealthStatus.healthy;
    }
  }

  static DiagnosticHealthStatus fromSeverities(Iterable<DiagnosticSeverity> xs) {
    var hasWarning = false;
    for (final s in xs) {
      if (s == DiagnosticSeverity.critical) return DiagnosticHealthStatus.critical;
      if (s == DiagnosticSeverity.warning) hasWarning = true;
    }
    return hasWarning ? DiagnosticHealthStatus.warning : DiagnosticHealthStatus.healthy;
  }
}

enum DiagnosticRootCauseStatus {
  confirmed,
  classifiedNotConfirmed,
  unknown;

  String get wire {
    switch (this) {
      case DiagnosticRootCauseStatus.confirmed:
        return 'CONFIRMED';
      case DiagnosticRootCauseStatus.classifiedNotConfirmed:
        return 'CLASSIFIED_NOT_CONFIRMED';
      case DiagnosticRootCauseStatus.unknown:
        return 'UNKNOWN';
    }
  }

  static DiagnosticRootCauseStatus parse(String? raw) {
    switch ((raw ?? '').trim().toUpperCase()) {
      case 'CONFIRMED':
      case 'ROOT_CAUSE_CONFIRMED':
        return DiagnosticRootCauseStatus.confirmed;
      case 'CLASSIFIED_NOT_CONFIRMED':
        return DiagnosticRootCauseStatus.classifiedNotConfirmed;
      default:
        return DiagnosticRootCauseStatus.unknown;
    }
  }
}

enum DiagnosticModule {
  stock,
  sales,
  saleEdit,
  saleDelete,
  restore,
  consignment,
  productEditor,
  catalog,
  sync,
  hive,
  firestore,
  cloudFunction,
  auth,
  network,
  buildIdentity,
  system;

  String get wire {
    switch (this) {
      case DiagnosticModule.stock:
        return 'STOCK';
      case DiagnosticModule.sales:
        return 'SALES';
      case DiagnosticModule.saleEdit:
        return 'SALE_EDIT';
      case DiagnosticModule.saleDelete:
        return 'SALE_DELETE';
      case DiagnosticModule.restore:
        return 'RESTORE';
      case DiagnosticModule.consignment:
        return 'CONSIGNMENT';
      case DiagnosticModule.productEditor:
        return 'PRODUCT_EDITOR';
      case DiagnosticModule.catalog:
        return 'CATALOG';
      case DiagnosticModule.sync:
        return 'SYNC';
      case DiagnosticModule.hive:
        return 'HIVE';
      case DiagnosticModule.firestore:
        return 'FIRESTORE';
      case DiagnosticModule.cloudFunction:
        return 'CLOUD_FUNCTION';
      case DiagnosticModule.auth:
        return 'AUTH';
      case DiagnosticModule.network:
        return 'NETWORK';
      case DiagnosticModule.buildIdentity:
        return 'BUILD_IDENTITY';
      case DiagnosticModule.system:
        return 'SYSTEM';
    }
  }

  static DiagnosticModule parse(String? raw) {
    switch ((raw ?? '').trim().toUpperCase()) {
      case 'STOCK':
        return DiagnosticModule.stock;
      case 'SALES':
        return DiagnosticModule.sales;
      case 'SALE_EDIT':
        return DiagnosticModule.saleEdit;
      case 'SALE_DELETE':
        return DiagnosticModule.saleDelete;
      case 'RESTORE':
        return DiagnosticModule.restore;
      case 'CONSIGNMENT':
        return DiagnosticModule.consignment;
      case 'PRODUCT_EDITOR':
        return DiagnosticModule.productEditor;
      case 'CATALOG':
        return DiagnosticModule.catalog;
      case 'SYNC':
        return DiagnosticModule.sync;
      case 'HIVE':
        return DiagnosticModule.hive;
      case 'FIRESTORE':
        return DiagnosticModule.firestore;
      case 'CLOUD_FUNCTION':
        return DiagnosticModule.cloudFunction;
      case 'AUTH':
        return DiagnosticModule.auth;
      case 'NETWORK':
        return DiagnosticModule.network;
      case 'BUILD_IDENTITY':
        return DiagnosticModule.buildIdentity;
      default:
        return DiagnosticModule.system;
    }
  }
}

/// Known error / anomaly classification codes.
abstract final class DiagnosticClassification {
  static const firebasePermissionDenied = 'FIREBASE_PERMISSION_DENIED';
  static const firebaseFailedPrecondition = 'FIREBASE_FAILED_PRECONDITION';
  static const firebaseUnavailable = 'FIREBASE_UNAVAILABLE';
  static const functionTimeout = 'FUNCTION_TIMEOUT';
  static const networkOffline = 'NETWORK_OFFLINE';

  static const stockLocalRemoteMismatch = 'STOCK_LOCAL_REMOTE_MISMATCH';
  static const stockPendingOperation = 'STOCK_PENDING_OPERATION';
  static const stockOrphanPending = 'STOCK_ORPHAN_PENDING';
  static const stockDuplicatePending = 'STOCK_DUPLICATE_PENDING';
  static const stockInvalidPending = 'STOCK_INVALID_PENDING';

  static const stockAggregateMismatch = 'STOCK_AGGREGATE_MISMATCH';
  static const stockCanonicalCellMismatch = 'STOCK_CANONICAL_CELL_MISMATCH';
  static const stockRevisionMismatch = 'STOCK_REVISION_MISMATCH';
  static const stockOperationIdMismatch = 'STOCK_OPERATION_ID_MISMATCH';
  static const stockEditorialLineageAnomaly = 'STOCK_EDITORIAL_LINEAGE_ANOMALY';

  static const saleMissingStockOperationBinding =
      'SALE_MISSING_STOCK_OPERATION_BINDING';
  static const saleSourceOperationNotFound = 'SALE_SOURCE_OPERATION_NOT_FOUND';
  static const saleRestoreAlreadyApplied = 'SALE_RESTORE_ALREADY_APPLIED';
  static const saleRestoreFailed = 'SALE_RESTORE_FAILED';
  static const salePersistAfterStockFailure =
      'SALE_PERSIST_AFTER_STOCK_FAILURE';

  static const staleTombstoneLiveRemoteCell =
      'STALE_TOMBSTONE_LIVE_REMOTE_CELL';

  static const cacheLocalUntrackedMutation = 'CACHE_LOCAL_UNTRACKED_MUTATION';
  static const cacheRemoteNewer = 'CACHE_REMOTE_NEWER';
  static const cacheHydrationFailed = 'CACHE_HYDRATION_FAILED';

  static const buildIdentityMismatch = 'BUILD_IDENTITY_MISMATCH';
  static const unknownError = 'UNKNOWN_ERROR';

  static const List<String> allKnown = [
    firebasePermissionDenied,
    firebaseFailedPrecondition,
    firebaseUnavailable,
    functionTimeout,
    networkOffline,
    stockLocalRemoteMismatch,
    stockPendingOperation,
    stockOrphanPending,
    stockDuplicatePending,
    stockInvalidPending,
    stockAggregateMismatch,
    stockCanonicalCellMismatch,
    stockRevisionMismatch,
    stockOperationIdMismatch,
    stockEditorialLineageAnomaly,
    saleMissingStockOperationBinding,
    saleSourceOperationNotFound,
    saleRestoreAlreadyApplied,
    saleRestoreFailed,
    salePersistAfterStockFailure,
    staleTombstoneLiveRemoteCell,
    cacheLocalUntrackedMutation,
    cacheRemoteNewer,
    cacheHydrationFailed,
    buildIdentityMismatch,
    unknownError,
  ];
}

/// Sale / delete / stock-edit stage name constants.
abstract final class DiagnosticStages {
  // Sale
  static const saleStart = 'SALE_START';
  static const saleItemsNormalized = 'SALE_ITEMS_NORMALIZED';
  static const saleVariationsResolved = 'SALE_VARIATIONS_RESOLVED';
  static const stockCommandStart = 'STOCK_COMMAND_START';
  static const stockCommandSuccess = 'STOCK_COMMAND_SUCCESS';
  static const stockCommandAlreadyApplied = 'STOCK_COMMAND_ALREADY_APPLIED';
  static const salePersistStart = 'SALE_PERSIST_START';
  static const salePersistSuccess = 'SALE_PERSIST_SUCCESS';
  static const localRefreshStart = 'LOCAL_REFRESH_START';
  static const localRefreshSuccess = 'LOCAL_REFRESH_SUCCESS';
  static const saleComplete = 'SALE_COMPLETE';
  static const saleAbort = 'SALE_ABORT';

  // Delete / restore
  static const deleteStart = 'DELETE_START';
  static const sourceOperationResolved = 'SOURCE_OPERATION_RESOLVED';
  static const restoreCommandStart = 'RESTORE_COMMAND_START';
  static const restoreCommandHttpSuccess = 'RESTORE_COMMAND_HTTP_SUCCESS';
  static const restoreNewlyApplied = 'RESTORE_NEWLY_APPLIED';
  static const restoreAlreadyApplied = 'RESTORE_ALREADY_APPLIED';
  static const localHiveApplyStart = 'LOCAL_HIVE_APPLY_START';
  static const localHiveApplySuccess = 'LOCAL_HIVE_APPLY_SUCCESS';
  static const remoteRefreshStart = 'REMOTE_REFRESH_START';
  static const remoteRefreshSuccess = 'REMOTE_REFRESH_SUCCESS';
  static const saleSoftDeleteStart = 'SALE_SOFT_DELETE_START';
  static const saleSoftDeleteSuccess = 'SALE_SOFT_DELETE_SUCCESS';
  static const deleteComplete = 'DELETE_COMPLETE';
  static const deleteAbort = 'DELETE_ABORT';

  // Stock edit
  static const stockEditStart = 'STOCK_EDIT_START';
  static const localInputCaptured = 'LOCAL_INPUT_CAPTURED';
  static const canonicalStateRead = 'CANONICAL_STATE_READ';
  static const expectedRevisionCaptured = 'EXPECTED_REVISION_CAPTURED';
  static const pendingSet = 'PENDING_SET';
  static const remoteConfirmation = 'REMOTE_CONFIRMATION';
  static const pendingCleared = 'PENDING_CLEARED';
  static const localHydration = 'LOCAL_HYDRATION';
  static const stockEditComplete = 'STOCK_EDIT_COMPLETE';
  static const stockEditAbort = 'STOCK_EDIT_ABORT';
}
