// PII-redacted fiado diagnostic events for Incident Center.

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/client_build_identity.dart';
import '../core/conta_receber_remote_authority.dart';
import 'diagnostic_enums.dart';
import 'diagnostic_incident.dart';
import 'diagnostic_incident_history.dart';

/// Structured fiado / contas-a-receber diagnostic event codes.
abstract final class FiadoDiagnosticEvents {
  static const remotePullStarted = 'FIADO_REMOTE_PULL_STARTED';
  static const remotePullComplete = 'FIADO_REMOTE_PULL_COMPLETE';
  static const cacheReconciled = 'FIADO_CACHE_RECONCILED';
  static const localUpsertAttempt = 'FIADO_LOCAL_UPSERT_ATTEMPT';
  static const localUpsertApplied = 'FIADO_LOCAL_UPSERT_APPLIED';
  static const staleLocalRejected = 'FIADO_STALE_LOCAL_REJECTED';
  static const syncConflict = 'FIADO_SYNC_CONFLICT';
  static const settlementStarted = 'FIADO_SETTLEMENT_STARTED';
  static const settlementConfirmed = 'FIADO_SETTLEMENT_CONFIRMED';
  static const settlementIdempotentRetry = 'FIADO_SETTLEMENT_IDEMPOTENT_RETRY';
  static const overdueRecalculated = 'FIADO_OVERDUE_RECALCULATED';
}

abstract final class FiadoDiagnosticTracer {
  FiadoDiagnosticTracer._();

  static String _hashId(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 'id_none';
    var h = 0;
    for (final c in t.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return 'cr_${h.toRadixString(16).padLeft(8, '0')}';
  }

  static Future<void> emit({
    required String storeId,
    required String eventCode,
    String? accountId,
    String? localStatus,
    String? remoteStatus,
    double? localSaldo,
    double? remoteSaldo,
    String? decision,
    String? origin,
    Map<String, dynamic>? extra,
    DiagnosticSeverity severity = DiagnosticSeverity.info,
  }) async {
    final loja = storeId.trim();
    if (loja.isEmpty) return;
    final traceId = const Uuid().v4();
    try {
      await DiagnosticIncidentHistory.ensureHydrated();
      await DiagnosticIncidentHistory.record(
        DiagnosticIncident(
          incidentId: const Uuid().v4(),
          traceId: traceId,
          storeId: loja,
          timestamp: DateTime.now().toUtc(),
          severity: severity,
          module: DiagnosticModule.sync,
          operationType: eventCode,
          classification: eventCode,
          rootCauseStatus: DiagnosticRootCauseStatus.classifiedNotConfirmed,
          userTitle: 'Fiado sync',
          userMessage: eventCode,
          safeNextAction: 'Somente observação técnica — sem PII.',
          metadataSanitized: {
            'tenantId': loja,
            if (accountId != null && accountId.trim().isNotEmpty)
              'accountIdHash': _hashId(accountId),
            if (localStatus != null) 'localStatus': localStatus,
            if (remoteStatus != null) 'remoteStatus': remoteStatus,
            if (localSaldo != null) 'localSaldo': localSaldo,
            if (remoteSaldo != null) 'remoteSaldo': remoteSaldo,
            if (decision != null) 'decision': decision,
            if (origin != null) 'origin': origin,
            'buildId': kClientBuildId,
            'appVersion': kClientAppVersion,
            'gitCommit': kClientGitCommit,
            'updatedAtPolicy': kContaReceberUpdatedAtConflictPolicy,
            ...?extra,
          },
          buildId: kClientBuildId,
          appVersion: kClientAppVersion,
          gitCommit: kClientGitCommit,
        ),
      );
    } catch (e) {
      debugPrint('[FIADO-DIAG] emit failed type=${e.runtimeType}');
    }
  }
}
