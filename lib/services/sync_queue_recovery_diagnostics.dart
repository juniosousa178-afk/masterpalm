// lib/services/sync_queue_recovery_diagnostics.dart
//
// Session-scoped, recovery-mode-only runtime observability.
// Counters/flags only — no queue payloads, PII, auth, or Firestore.

import 'package:flutter/foundation.dart' show visibleForTesting, kIsWeb;

import 'sync_queue_recovery_diagnostics_bridge_stub.dart'
    if (dart.library.html) 'sync_queue_recovery_diagnostics_bridge_web.dart'
    as recovery_diag_bridge;

/// Non-sensitive recovery-mode diagnostics for production smoke proof.
class SyncQueueRecoveryDiagnostics {
  SyncQueueRecoveryDiagnostics._();

  static const int schemaVersion = 1;
  static const int maxEventTrace = 50;

  static bool _recoveryModeActive = false;
  static bool _recoveryModeResolved = false;
  static bool _recoveryResolvedBeforeBootstrap = false;
  static bool _bootstrapStarted = false;
  static DateTime? _recoverySessionStartedAt;

  static int bootstrapAutosyncSuppressedCount = 0;
  static int homeAutosyncSuppressedCount = 0;
  static int autoSyncServiceSuppressedCount = 0;
  static int connectivityAutosyncSuppressedCount = 0;
  static int processPendingBlockedCount = 0;
  static int retryItemBlockedCount = 0;
  static int queueHandlerExecutionCount = 0;
  static int queueNetworkExecutionCount = 0;

  static final List<String> _eventTrace = <String>[];

  static bool get recoveryModeActive => _recoveryModeActive;
  static bool get recoveryModeResolved => _recoveryModeResolved;
  static bool get recoveryResolvedBeforeBootstrap =>
      _recoveryResolvedBeforeBootstrap;
  static bool get bootstrapStarted => _bootstrapStarted;
  static DateTime? get recoverySessionStartedAt => _recoverySessionStartedAt;
  static List<String> get eventTrace =>
      List<String>.unmodifiable(_eventTrace);

  /// Called when recovery mode becomes active (URI / explicit).
  static void markRecoveryResolved({String source = 'uri'}) {
    _recoveryModeActive = true;
    _recoveryModeResolved = true;
    _recoverySessionStartedAt ??= DateTime.now().toUtc();
    _pushEvent('recovery_resolved');
    if (kIsWeb) {
      recovery_diag_bridge.installRecoveryDiagnosticsBridge();
    }
  }

  /// Mark the first queue-bootstrap gate; records order vs recovery resolve.
  static void markBootstrapStarted() {
    if (_bootstrapStarted) return;
    _bootstrapStarted = true;
    _pushEvent('bootstrap_started');
    if (_recoveryModeResolved) {
      _recoveryResolvedBeforeBootstrap = true;
    }
  }

  static void noteBootstrapAutosyncSuppressed() {
    markBootstrapStarted();
    if (!_recoveryModeActive) return;
    bootstrapAutosyncSuppressedCount++;
    _pushEvent('bootstrap_autosync_suppressed');
  }

  static void noteHomeAutosyncSuppressed() {
    if (!_recoveryModeActive) return;
    homeAutosyncSuppressedCount++;
    _pushEvent('home_autosync_suppressed');
  }

  static void noteAutoSyncServiceSuppressed() {
    if (!_recoveryModeActive) return;
    autoSyncServiceSuppressedCount++;
    _pushEvent('autosync_service_suppressed');
  }

  static void noteConnectivityAutosyncSuppressed() {
    if (!_recoveryModeActive) return;
    connectivityAutosyncSuppressedCount++;
    _pushEvent('connectivity_sync_suppressed');
  }

  static void noteProcessPendingBlocked() {
    if (!_recoveryModeActive) return;
    processPendingBlockedCount++;
    _pushEvent('process_pending_blocked');
  }

  static void noteRetryItemBlocked() {
    if (!_recoveryModeActive) return;
    retryItemBlockedCount++;
    _pushEvent('retry_item_blocked');
  }

  /// Escape counter: any business handler start while recovery is active.
  static void noteQueueHandlerExecution() {
    if (!_recoveryModeActive) return;
    queueHandlerExecutionCount++;
    _pushEvent('queue_handler_escape');
  }

  /// Optional network-origin counter (only if a reliable central point exists).
  static void noteQueueNetworkExecution() {
    if (!_recoveryModeActive) return;
    queueNetworkExecutionCount++;
  }

  /// Sanitized read-only snapshot. Zero mutations / network / remote writes.
  static Map<String, Object?> getRecoveryDiagnosticsSnapshot() {
    return <String, Object?>{
      'diagnosticSchemaVersion': schemaVersion,
      'recoveryModeActive': _recoveryModeActive,
      'recoveryModeResolved': _recoveryModeResolved,
      'recoveryResolvedBeforeBootstrap': _recoveryResolvedBeforeBootstrap,
      'bootstrapStarted': _bootstrapStarted,
      'bootstrapAutosyncSuppressedCount': bootstrapAutosyncSuppressedCount,
      'homeAutosyncSuppressedCount': homeAutosyncSuppressedCount,
      'autoSyncServiceSuppressedCount': autoSyncServiceSuppressedCount,
      'connectivityAutosyncSuppressedCount':
          connectivityAutosyncSuppressedCount,
      'processPendingBlockedCount': processPendingBlockedCount,
      'retryItemBlockedCount': retryItemBlockedCount,
      'queueHandlerExecutionCount': queueHandlerExecutionCount,
      'queueNetworkExecutionCount': queueNetworkExecutionCount,
      'recoverySessionStartedAtMs':
          _recoverySessionStartedAt?.millisecondsSinceEpoch,
      'eventTrace': List<String>.from(_eventTrace),
    };
  }

  static void _pushEvent(String name) {
    if (_eventTrace.length >= maxEventTrace) {
      _eventTrace.removeAt(0);
    }
    _eventTrace.add(name);
  }

  /// Clears in-memory session diagnostics (tests / deactivate).
  static void clearSession() {
    _recoveryModeActive = false;
    _recoveryModeResolved = false;
    _recoveryResolvedBeforeBootstrap = false;
    _bootstrapStarted = false;
    _recoverySessionStartedAt = null;
    bootstrapAutosyncSuppressedCount = 0;
    homeAutosyncSuppressedCount = 0;
    autoSyncServiceSuppressedCount = 0;
    connectivityAutosyncSuppressedCount = 0;
    processPendingBlockedCount = 0;
    retryItemBlockedCount = 0;
    queueHandlerExecutionCount = 0;
    queueNetworkExecutionCount = 0;
    _eventTrace.clear();
    if (kIsWeb) {
      recovery_diag_bridge.uninstallRecoveryDiagnosticsBridge();
    }
  }

  @visibleForTesting
  static void resetForTests() => clearSession();
}
